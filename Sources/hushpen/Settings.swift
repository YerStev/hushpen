import Foundation

struct Settings: Codable {
    var hotkey: String
    var pasteAutomatically: Bool

    static let `default` = Settings(hotkey: FnKeyMonitor.specification, pasteAutomatically: true)

    var hotkeyName: String { FnKeyMonitor.matches(hotkey) ? "Fn (🌐)" : hotkey }
}

enum SettingsStore {
    private static var url: URL { Paths.stateDirectory.appendingPathComponent("settings.json") }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        return settings
    }

    static func save(_ settings: Settings) throws {
        try Paths.ensureStateDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
