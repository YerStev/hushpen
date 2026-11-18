import Foundation

// Optional cleanup of the transcript by a local language model (Gemma 4 E4B
// through llama.cpp). It removes filler sounds, self-corrections, sentences the
// speaker takes back and false starts, keeps the better of two phrasings, and
// preserves the wording. The prompt comes from eval/cleanup, where it was
// measured. Any doubt keeps the transcript as it was.
enum TextCleanup {
    enum Outcome: Equatable {
        case changed(String)
        case unchanged
        // The model's text was not used; the reason is safe to log.
        case rejected(String)
    }

    static let cleanupPrompt = prompt("cleanup")

    private static func prompt(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("The \(name) prompt is missing from the app bundle.")
        }
        return text
    }

    // Processes the cleanup prompt ahead of time, so a dictation only waits for
    // its own text.
    static func warm(_ runner: LlamaRunner) throws {
        try runner.warm(system: cleanupPrompt)
    }

    // One model request; the closure gets the system and user text.
    typealias Ask = (_ system: String, _ user: String, _ maxTokens: Int) throws -> String

    static func clean(_ text: String, ask: Ask) throws -> Outcome {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return .unchanged }

        let reply = try ask(cleanupPrompt, numbered(original), maxTokens(for: original))
        var cleaned = unnumbered(reply)
        if cleaned.isEmpty {
            return .rejected("empty result")
        }
        // If one sentence introduces new words, preserve that sentence while
        // keeping independently valid cleanup elsewhere. Strict numbering is
        // required for this fallback; malformed replies keep the whole source.
        if !novelWords(in: cleaned, comparedTo: original).isEmpty {
            guard let partial = preservingUncertainSentences(reply, original: original) else {
                return .rejected("new words")
            }
            cleaned = partial
        }

        return cleaned == original ? .unchanged : .changed(cleaned)
    }

    // Room for the whole text again plus some slack.
    static func maxTokens(for text: String) -> Int {
        max(96, text.utf8.count)
    }

    // MARK: - Steps, kept in line with eval/cleanup/run.py

    // Splits after . ! or ? followed by whitespace, like the evaluation.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            defer { previous = character }
            if character.isWhitespace {
                if let previous, ".!?".contains(previous), !current.isEmpty {
                    result.append(current)
                    current = ""
                } else if !current.isEmpty, previous?.isWhitespace == false {
                    current.append(" ")
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func numbered(_ text: String) -> String {
        sentences(text).enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
    }

    static func unnumbered(_ reply: String) -> String {
        reply.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var line = Substring(line)
                if line.first == "[", let close = line.firstIndex(of: "]"),
                   line[line.index(after: line.startIndex)..<close].allSatisfy(\.isNumber) {
                    line = line[line.index(after: close)...]
                }
                return line.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let wordPattern = try! NSRegularExpression(pattern: "\\w+(?:'\\w+)?")

    static func exactWords(_ text: String) -> [String] {
        wordPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }
    }

    static func words(_ text: String) -> [String] {
        exactWords(text).map { $0.lowercased() }
    }

    static func novelWords(in output: String, comparedTo source: String) -> [String] {
        let said = Set(words(source))
        return words(output).filter { !said.contains($0) }
    }

    static func preservingUncertainSentences(_ reply: String, original: String) -> String? {
        let source = sentences(original)
        var previous = 0
        var result: [String] = []
        for raw in reply.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.first == "[", let close = line.firstIndex(of: "]"),
                  let number = Int(line[line.index(after: line.startIndex)..<close]),
                  number > previous, number <= source.count else { return nil }
            let edited = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard !edited.isEmpty else { return nil }
            let sentence = source[number - 1]
            // New vocabulary is never accepted by this recovery path.
            result.append(novelWords(in: edited, comparedTo: sentence).isEmpty ? edited : sentence)
            previous = number
        }
        return result.isEmpty ? nil : result.joined(separator: " ")
    }
}
