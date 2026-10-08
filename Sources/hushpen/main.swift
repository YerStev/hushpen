import AppKit
import Darwin
import Foundation
import Voz

func fail(_ error: ToolError) -> Never {
    FileHandle.standardError.write(Data(("hushpen: " + error.message + "\n").utf8))
    exit(error.code.rawValue)
}

func succeed(_ message: String? = nil) -> Never {
    if let message { print(message) }
    exit(ExitCode.success.rawValue)
}

// Prints download progress in 10 % steps.
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var shown = -1

    func report(_ fraction: Double) {
        let step = Int(fraction * 10)
        lock.lock()
        defer { lock.unlock() }
        guard step > shown else { return }
        shown = step
        print("  \(step * 10) %")
    }
}

func executablePath() throws -> String {
    if let path = Bundle.main.executablePath, FileManager.default.isExecutableFile(atPath: path) {
        return path
    }
    let argument = CommandLine.arguments[0]
    let resolved = URL(fileURLWithPath: argument).standardizedFileURL.path
    guard FileManager.default.isExecutableFile(atPath: resolved) else {
        throw ToolError(.failure, "Could not determine the executable path.")
    }
    return resolved
}

var arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--setup":
    guard arguments.count == 1 else { fail(ToolError(.usage, "Usage: hushpen --setup")) }
    Setup.run()

case "--help", "-h":
    succeed(usageText)

case "--version":
    succeed(Attribution.versionText)

case "--daemon":
    do {
        let daemon = try Daemon(settings: SettingsStore.load())
        try daemon.run()
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.failure, error.localizedDescription))
    }

case "--hotkey":
    guard arguments.count == 2, let specification = arguments.last else {
        fail(ToolError(.usage, """
            Usage: hushpen --hotkey cmd+shift+d
                    hushpen --hotkey fn

            Modifiers: cmd, shift, alt, ctrl. Keys: a–z, 0–9, space, return,
            tab, escape, f1–f20. Function keys may be used alone; other keys
            require a modifier. `fn` means tapping the Fn/Globe key on its own.
            """))
    }
    do {
        let description: String
        if FnKeyMonitor.matches(specification) {
            description = "Tap Fn/🌐"
        } else {
            description = try HotkeyMonitor.parse(specification).description
        }
        var settings = SettingsStore.load()
        settings.hotkey = FnKeyMonitor.matches(specification) ? FnKeyMonitor.specification : specification
        try SettingsStore.save(settings)
        succeed("""
            Shortcut set: \(description)
            Restart the service to apply it:
              launchctl kickstart -k gui/\(getuid())/\(LaunchAgent.label)
            """)
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.failure, error.localizedDescription))
    }

case "--paste-mode":
    guard arguments.count == 2, let value = arguments.last,
          value == "on" || value == "off" else {
        fail(ToolError(.usage, "Usage: hushpen --paste-mode on|off"))
    }
    do {
        var settings = SettingsStore.load()
        settings.pasteAutomatically = (value == "on")
        try SettingsStore.save(settings)
    } catch {
        fail(ToolError(.failure, "Could not save the setting: \(error.localizedDescription)"))
    }
    if value == "on" && !Paste.isTrusted {
        Paste.requestTrust()
        succeed("""
            Automatic paste is enabled but requires Accessibility access.

            \(Paste.missingTrustHint)
            """)
    }
    succeed("Automatic paste \(value == "on" ? "enabled" : "disabled").")

case "--install-agent":
    do {
        succeed(try LaunchAgent.install(executable: try executablePath()))
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.failure, error.localizedDescription))
    }

case "--uninstall-agent":
    do {
        succeed(try LaunchAgent.uninstall())
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.failure, error.localizedDescription))
    }

case "--download-model":
    guard arguments.count == 1 else { fail(ToolError(.usage, "Usage: hushpen --download-model")) }
    print("Downloading \(Attribution.modelRevision) (about 470 MB) from huggingface.co …")
    let reporter = ProgressReporter()
    do {
        let config = try await ModelImport.download { reporter.report($0) }
        try Config.saveModel(config)
        succeed("Model downloaded, checked and registered: \(config.directory)")
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.failure, error.localizedDescription))
    }

case "--set-model":
    guard arguments.count == 2, let path = arguments.last else {
        fail(ToolError(.usage, "Usage: hushpen --set-model /path/to/voz-model"))
    }
    let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        fail(ToolError(.modelMissing, "Not a folder: \(directory.path)"))
    }
    do {
        let config = try ModelImport.prepare(directory: directory)
        try Config.saveModel(config)
        let digest = config.digest
        succeed("""
            Model registered.
              Folder: \(directory.path)
              Checksum:   \(digest)
              Revision:    \(Attribution.modelRevision)
            """)
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.failure, error.localizedDescription))
    }

case "--transcribe-file":
    guard arguments.count == 2, let path = arguments.last else {
        fail(ToolError(.usage, "Usage: hushpen --transcribe-file /path/to/audio.wav"))
    }
    do {
        let samples = try FileInput.samples(at: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        guard !samples.isEmpty else { fail(ToolError(.usage, "The audio file contains no samples.")) }
        let voz = try Voz(modelDirectory: try Config.verifiedModelDirectory())
        guard voz.sampleRate == Recorder.targetSampleRate else {
            fail(ToolError(.failure, "The model expects \(Int(voz.sampleRate)) Hz."))
        }
        do {
            let result = try await voz.transcribe(samples: samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print(text)
        } catch {
            await Telemetry.flushPendingUsage(keeping: voz)
            throw error
        }
        await Telemetry.flushPendingUsage(keeping: voz)
        exit(ExitCode.success.rawValue)
    } catch let error as ToolError {
        fail(error)
    } catch {
        fail(ToolError(.transcription, "Transcription failed: \(String(describing: type(of: error)))"))
    }

case "--verify":
    func row(_ label: String, _ value: String) -> String {
        (label + ":").padding(toLength: 18, withPad: " ", startingAt: 0) + value
    }
    var lines: [String] = []
    if let model = try? Config.loadModel() {
        lines.append(row("Model", model.directory))
        if let actual = try? ModelDigest.compute(directory: URL(fileURLWithPath: model.directory)) {
            lines.append(row("Checksum", actual == model.digest ? "\(actual) (matches)" : "\(actual) (MISMATCH, expected \(model.digest))"))
        } else {
            lines.append(row("Checksum", "folder unreadable"))
        }
    } else {
        lines.append(row("Model", "not registered (run --download-model)"))
    }
    let settings = SettingsStore.load()
    lines.append(row("Hotkey", settings.hotkey))
    lines.append(row("Paste", settings.pasteAutomatically ? "automatic" : "clipboard only"))
    lines.append(row("Service", LaunchAgent.isInstalled
        ? (ServiceLock.isHeldElsewhere ? "running" : "installed, not running")
        : "not installed"))
    lines.append(row("Usage reporting", Telemetry.statusText))
    lines.append(row("SDK", Attribution.sdkVersion))
    lines.append(row("Log", LaunchAgent.logURL.path))
    succeed(lines.joined(separator: "\n"))

case nil:
    if Bundle.main.bundleURL.pathExtension == "app" {
        Setup.run()
    }
    succeed(usageText)

case .some(let unknown) where unknown.hasPrefix("-"):
    fail(ToolError(.usage, "Unknown option: \(unknown)\n\n" + usageText))

case .some(let unexpected):
    fail(ToolError(.usage, "Unexpected argument: \(unexpected)\n\n" + usageText))
}
