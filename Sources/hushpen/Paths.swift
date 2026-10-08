import Foundation

enum Paths {
    static var stateDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("hushpen", isDirectory: true)
    }

    static var modelConfig: URL { stateDirectory.appendingPathComponent("model.json") }
    static var serviceLock: URL { stateDirectory.appendingPathComponent("service.lock") }

    static func ensureStateDirectory() throws {
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
