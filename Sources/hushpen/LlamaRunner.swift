import Foundation
import llama

// A loaded llama.cpp model with one context. Greedy decoding, so the same
// input always gives the same output.
//
// Each system prompt gets its own sequence in the context, and the tokens it
// last processed are kept: a request with the same instructions only
// processes the user text. The cleanup and layout prompts therefore do not
// push each other out.
//
// Generation drafts tokens from the user text: cleaned text mostly repeats
// the dictation, so the tokens that followed the last few generated ones
// there are checked in one step. Greedy checking keeps the output exactly
// what one-token-at-a-time decoding gives (prompt lookup decoding).
final class LlamaRunner {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private let batchSize: Int
    private var sequences: [String: llama_seq_id] = [:]
    private var cached: [llama_seq_id: [llama_token]] = [:]

    static let contextLength: UInt32 = 8192
    static let sequenceCount: UInt32 = 2
    static let draftLength = 16

    init(modelPath: String) throws {
        _ = Self.setUp
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            throw ToolError(.failure, "The cleanup model could not be loaded.")
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = Self.contextLength
        contextParams.n_batch = 2048
        contextParams.n_ubatch = 512
        contextParams.n_seq_max = Self.sequenceCount
        // Both sequences share the context length.
        contextParams.kv_unified = true
        // Gemma's sliding-window layers need the full cache, so that rejected
        // draft tokens and old user text can be removed from a sequence.
        contextParams.swa_full = true
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw ToolError(.failure, "The cleanup model could not be started.")
        }
        self.model = model
        self.context = context
        vocab = llama_model_get_vocab(model)
        batchSize = Int(contextParams.n_batch)
        sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
    }

    deinit {
        llama_sampler_free(sampler)
        llama_free(context)
        llama_model_free(model)
    }

    // The backend is set up once per process; llama.cpp's own log output is
    // dropped so it cannot end up in hushpen's log.
    private static let setUp: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    // Gemma 4's chat format, as its template in the model file renders it
    // (the template trims each message). The prefix ends where the user text
    // starts.
    static func gemmaPrefix(system: String) -> String {
        "<|turn>system\n\(system.trimmingCharacters(in: .whitespacesAndNewlines))<turn|>\n<|turn>user\n"
    }

    static func gemmaPrompt(system: String, user: String) -> String {
        gemmaPrefix(system: system) + user.trimmingCharacters(in: .whitespacesAndNewlines) + "<turn|>\n<|turn>model\n"
    }

    // Processes the instructions ahead of time, while the user is speaking.
    func warm(system: String) throws {
        try reuse(tokenize(Self.gemmaPrefix(system: system)), in: sequence(for: system), keepingLast: false)
    }

    func generate(system: String, user: String, maxTokens: Int) throws -> String {
        let sequence = sequence(for: system)
        let tokens = tokenize(Self.gemmaPrompt(system: system, user: user))
        let prefixLength = min(tokens.count, tokenize(Self.gemmaPrefix(system: system)).count)
        let others = cached.filter { $0.key != sequence }.values.reduce(0) { $0 + $1.count }
        guard others + tokens.count + maxTokens + Self.draftLength <= Int(Self.contextLength) else {
            throw ToolError(.failure, "The text is too long for the cleanup model.")
        }
        try reuse(tokens, in: sequence, keepingLast: true)

        let source = Array(tokens[prefixLength...])
        var output: [llama_token] = []
        var next = llama_sampler_sample(sampler, context, -1)
        while output.count < maxTokens, !llama_vocab_is_eog(vocab, next) {
            output.append(next)
            let draft = Self.draft(after: output, from: source)
            let predicted = try decodeChecking([next] + draft, in: sequence)
            // predicted[i] is the model's token after position i of the batch.
            var accepted = 0
            while accepted < draft.count, predicted[accepted] == draft[accepted],
                  !llama_vocab_is_eog(vocab, draft[accepted]), output.count < maxTokens {
                output.append(draft[accepted])
                accepted += 1
            }
            // Positions after the last accepted token hold rejected drafts.
            try truncate(sequence, to: (cached[sequence]?.count ?? 0) - (draft.count - accepted))
            next = predicted[accepted]
        }
        return String(decoding: output.flatMap(piece), as: UTF8.self)
    }

    private func sequence(for system: String) -> llama_seq_id {
        if let id = sequences[system] { return id }
        let id = llama_seq_id(sequences.count % Int(Self.sequenceCount))
        // A third prompt takes over a sequence; forget the one it replaces.
        sequences = sequences.filter { $0.value != id }
        sequences[system] = id
        try? truncate(id, to: 0)
        return id
    }

    // Keeps the processed tokens shared with the last request in this
    // sequence and processes the rest. For a generation the last token is
    // always processed again, so its logits are fresh.
    private func reuse(_ tokens: [llama_token], in sequence: llama_seq_id, keepingLast: Bool) throws {
        let previous = cached[sequence] ?? []
        var common = zip(previous, tokens).prefix(while: { $0 == $1 }).count
        if keepingLast { common = min(common, tokens.count - 1) }
        try truncate(sequence, to: common)
        var start = common
        while start < tokens.count {
            let end = min(tokens.count, start + batchSize)
            try run(Array(tokens[start..<end]), in: sequence, logitsForAll: false)
            start = end
        }
    }

    private func truncate(_ sequence: llama_seq_id, to length: Int) throws {
        guard llama_memory_seq_rm(llama_get_memory(context), sequence, llama_pos(length), -1) else {
            throw ToolError(.failure, "The cleanup model could not reuse its cache.")
        }
        cached[sequence] = Array((cached[sequence] ?? []).prefix(length))
    }

    // The tokens that followed the latest occurrence of the last two or three
    // generated tokens in the source text.
    static func draft(after history: [llama_token], from source: [llama_token]) -> [llama_token] {
        for size in stride(from: 3, through: 2, by: -1) where history.count >= size {
            let key = history.suffix(size)
            var start = source.count - size
            while start >= 0 {
                if source[start..<start + size].elementsEqual(key) {
                    let from = start + size
                    let draft = Array(source[from..<min(source.count, from + draftLength)])
                    if !draft.isEmpty { return draft }
                }
                start -= 1
            }
        }
        return []
    }

    // Processes the tokens with logits at every position and returns the
    // greedy token after each one.
    private func decodeChecking(_ tokens: [llama_token], in sequence: llama_seq_id) throws -> [llama_token] {
        try run(tokens, in: sequence, logitsForAll: true)
        return tokens.indices.map { llama_sampler_sample(sampler, context, Int32($0)) }
    }

    // Without logitsForAll, only the last token gets logits.
    private func run(_ tokens: [llama_token], in sequence: llama_seq_id, logitsForAll: Bool) throws {
        let position = cached[sequence]?.count ?? 0
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = llama_pos(position + index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]![0] = sequence
            batch.logits[index] = (logitsForAll || index == tokens.count - 1) ? 1 : 0
        }
        batch.n_tokens = Int32(tokens.count)
        let status = llama_decode(context, batch)
        guard status == 0 else {
            throw ToolError(.failure, "The cleanup model failed (llama_decode \(status)).")
        }
        cached[sequence, default: []] += tokens
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let utf8 = Array(text.utf8CString)
        let length = Int32(utf8.count - 1)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        var count = llama_tokenize(vocab, utf8, length, &tokens, Int32(tokens.count), true, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, utf8, length, &tokens, Int32(tokens.count), true, true)
        }
        return Array(tokens.prefix(Int(max(0, count))))
    }

    // Raw bytes, because one character can be split across tokens.
    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, count))).map { UInt8(bitPattern: $0) }
    }
}
