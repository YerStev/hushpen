import Foundation

// Optional cleanup of the transcript by a local language model (Gemma 4 E4B
// through llama.cpp). It removes filler sounds, self-corrections, sentences the
// speaker takes back and false starts, keeps the better of two phrasings, and
// lays out emails. The steps and prompts match eval/cleanup, where they were
// measured. Any doubt keeps the transcript as it was.
enum TextCleanup {
    enum Outcome: Equatable {
        case changed(String)
        case unchanged
        // The model's text was not used; the reason is safe to log.
        case rejected(String)
    }

    static let cleanupPrompt = prompt("cleanup")
    static let layoutPrompt = prompt("layout")

    private static func prompt(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("The \(name) prompt is missing from the app bundle.")
        }
        return text
    }

    // Processes both prompts ahead of time, so a dictation only waits for
    // its own text.
    static func warm(_ runner: LlamaRunner) throws {
        try runner.warm(system: cleanupPrompt)
        try runner.warm(system: layoutPrompt)
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
        // Words the speaker never said mean the model made something up.
        if !novelWords(in: cleaned, comparedTo: original).isEmpty {
            return .rejected("new words")
        }

        if looksLikeEmail(cleaned) {
            let laidOut = try ask(layoutPrompt, cleaned, maxTokens(for: cleaned))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // The layout may only insert line breaks.
            if exactWords(laidOut) == exactWords(cleaned) {
                cleaned = laidOut
            }
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

    private static let greeting = try! NSRegularExpression(
        pattern: "^(hallo|hi|hey|moin|servus|liebe|lieber|sehr geehrte[rn]?|guten (morgen|tag|abend))\\b",
        options: .caseInsensitive)
    private static let signOff = try! NSRegularExpression(
        pattern: "\\b(gr\\u00FC\\u00DFe|gru\\u00DF|gr\\u00FC\\u00DFen|bis dann|bis bald|bis sp\\u00E4ter|ciao|tsch\\u00FCss|cheers)\\b\\W*(\\w+\\W*){1,3}$",
        options: .caseInsensitive)

    // Starts with a greeting and ends with a sign-off and a name.
    static func looksLikeEmail(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return greeting.firstMatch(in: text, range: range) != nil
            && signOff.firstMatch(in: text, range: range) != nil
    }
}
