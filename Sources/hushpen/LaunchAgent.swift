import Foundation

enum LaunchAgent {
    static let label = "io.github.yerstev.hushpen.agent"

    private static var plistURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/hushpen.log")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func install(executable: String) throws -> String {
        let directory = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardErrorPath": logURL.path,
            "StandardOutPath": "/dev/null",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        // A stopping service sends pending usage first; bootstrap fails
        // until launchd has fully released the old instance.
        var result = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        let deadline = Date().addingTimeInterval(12)
        while result.status != 0 && Date() < deadline {
            usleep(300_000)
            result = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        }
        guard result.status == 0 else {
            throw ToolError(.failure, """
                Could not start the login service (launchctl \(result.status)).
                \(result.output)

                The file is at \(plistURL.path). To start it manually:
                  launchctl bootstrap gui/\(getuid()) \(plistURL.path)
                """)
        }

        return """
            Service started; it also starts at login.
            Log: \(logURL.path)
            """
    }

    static func uninstall() throws -> String {
        guard isInstalled else { return "No login service is installed." }
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
        return """
            Login service removed (\(plistURL.path)).
            Existing system permissions remain. Revoke them in
            System Settings if you no longer need them.
            """
    }

    private static func runLaunchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
