import AppKit
import Foundation

@MainActor
final class Daemon: NSObject, NSApplicationDelegate {
    private let settings: Settings
    private let executable: String
    private var hotkey: HotkeyMonitor?
    private var fnKey: FnKeyMonitor?
    private var setupProcess: Process?
    private let models = ModelHost()
    private var dictation: Dictation!
    private var stopping = false

    init(settings: Settings) throws {
        self.settings = settings
        executable = try executablePath()
        super.init()
        dictation = Dictation(models: models, paste: settings.pasteAutomatically) { [weak self] in self?.log($0) }
    }

    func run() throws -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = self

        try claimSingleInstance()

        let usesFnKey = FnKeyMonitor.matches(settings.hotkey)
        if usesFnKey {
            fnKey = FnKeyMonitor(log: { [weak self] in self?.log($0) }) { [weak self] in self?.toggle() }
        } else {
            let combination = try HotkeyMonitor.parse(settings.hotkey)
            hotkey = try HotkeyMonitor(combination: combination) { [weak self] in
                self?.toggle()
            }
        }

        installSignalHandling()
        preloadModel()

        log("ready. Hotkey \(settings.hotkey). Paste: \(settings.pasteAutomatically ? "automatic" : "off"). Usage reporting: \(Telemetry.statusText)")
        if settings.pasteAutomatically && !Paste.isTrusted {
            log("automatic paste is enabled but Accessibility access is missing; requesting permission.")
            Paste.requestTrust()
            log(Paste.missingTrustHint)
        }

        app.run()
        fatalError("unreachable")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let process = setupProcess, process.isRunning {
            NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: [])
            return true
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--setup"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            setupProcess = process
        } catch {
            log("Could not open the setup assistant.")
        }
        return true
    }

    private func toggle() {
        guard !stopping else { return }
        Task { await dictation.toggle() }
    }

    // Loading here keeps the first dictation fast. A missing model is reported
    // once and retried at the next recording.
    private func preloadModel() {
        let models = self.models
        Task { [weak self] in
            do {
                _ = try await models.verifiedModel()
                self?.log("model loaded.")
            } catch let error as ToolError {
                self?.log("model not loaded yet: \(error.message)")
            } catch {
                self?.log("model not loaded yet: \(String(describing: type(of: error)))")
            }
        }
    }

    // Only one service may own the shortcut and microphone. The lock is
    // released by the kernel when the process exits.
    private func claimSingleInstance() throws {
        guard ServiceLock.acquire() else {
            throw ToolError(.recordingState, "Another hushpen service is already running.")
        }
    }

    private func installSignalHandling() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in self?.shutDown() }
            source.resume()
            signalSources.append(source)
        }
    }

    // Discard an active recording, then let the SDK send pending usage within
    // its bounded transport before exiting.
    private func shutDown() {
        guard !stopping else { return }
        stopping = true
        dictation.cancel()
        let models = self.models
        Task { [weak self] in
            Task.detached {
                try? await Task.sleep(for: .seconds(8))
                exit(ExitCode.success.rawValue)
            }
            await models.flushUsage()
            self?.log("stopped.")
            exit(ExitCode.success.rawValue)
        }
    }

    private var signalSources: [DispatchSourceSignal] = []

    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        FileHandle.standardError.write(Data("[\(stamp)] hushpen: \(message)\n".utf8))
    }
}
