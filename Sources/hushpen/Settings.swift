import Foundation

struct Settings: Codable {
    var hotkey: String
    var pasteAutomatically: Bool
    var cleanup: Bool

    static let `default` = Settings(hotkey: FnKeyMonitor.specification, pasteAutomatically: true, cleanup: false)

    init(hotkey: String, pasteAutomatically: Bool, cleanup: Bool) {
        self.hotkey = hotkey
        self.pasteAutomatically = pasteAutomatically
        self.cleanup = cleanup
    }

    // Settings files written before a field existed keep their other values.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decode(String.self, forKey: .hotkey)
        pasteAutomatically = try container.decode(Bool.self, forKey: .pasteAutomatically)
        cleanup = try container.decodeIfPresent(Bool.self, forKey: .cleanup) ?? false
    }

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
