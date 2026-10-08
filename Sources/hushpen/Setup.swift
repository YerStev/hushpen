import AppKit
import Foundation

// The setup assistant shown when the app is opened. It never records.
@MainActor
enum Setup {
    @MainActor
    private final class ImportResult {
        var value: Result<ModelConfig, Error>?
    }

    private static let modelSize = "about 470 MB"

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            show("Build the app first", "Run ./scripts/install.sh in the project folder.", ["Close"])
            exit(1)
        }
        if (try? Config.loadModel()) == nil {
            let choice = show("Welcome to hushpen",
                              "hushpen needs the Voz speech model (\(modelSize)). It is downloaded from Hugging Face and checked. Speech is processed on this Mac.",
                              ["Download model", "Choose existing folder", "Later"])
            switch choice {
            case 0: downloadModel()
            case 1: selectModel()
            default: exit(0)
            }
        }
        while true {
            let settings = SettingsStore.load()
            let hasModel = (try? Config.loadModel()) != nil
            let status = """
                Model: \(hasModel ? "ready" : "missing")
                Shortcut: \(settings.hotkeyName)
                Paste: \(settings.pasteAutomatically ? "automatic" : "clipboard only")
                Service: \(LaunchAgent.isInstalled ? "on, starts at login" : "off")
                """
            let choice = show("hushpen", status, [
                "Enable dictation", "Download model", "Choose model folder",
                "Paste mode", "Turn off service", "About & privacy", "Close",
            ])
            do {
                switch choice {
                case 0:
                    _ = try Config.verifiedModelDirectory()
                    _ = try LaunchAgent.install(executable: executablePath())
                    show("Dictation is on",
                         "Press \(settings.hotkeyName), speak, and press it again. The text is pasted where your cursor is.\n\nmacOS asks for microphone access on the first dictation. For pasting, allow hushpen under System Settings → Privacy & Security → Accessibility.",
                         ["OK"])
                case 1: downloadModel()
                case 2: selectModel()
                case 3:
                    let mode = show("Paste mode",
                                    "Automatic: the text is pasted where your cursor is, and your clipboard is restored. This needs Accessibility access.\n\nClipboard only: the text is copied and you paste it with ⌘V.",
                                    ["Automatic", "Clipboard only", "Cancel"])
                    if mode < 2 {
                        var changed = settings
                        changed.pasteAutomatically = mode == 0
                        try SettingsStore.save(changed)
                        if LaunchAgent.isInstalled {
                            _ = try LaunchAgent.install(executable: executablePath())
                        }
                        if mode == 0 && !Paste.isTrusted {
                            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                        }
                    }
                case 4:
                    show("Service", try LaunchAgent.uninstall(), ["OK"])
                case 5:
                    let action = show("About hushpen \(Attribution.toolVersion)", """
                        Speech recognition runs on this Mac with the Voz model by Desert Ant Labs. Audio and text are not uploaded or saved.

                        The model's SDK sends a usage report to Desert Ant Labs: a random installation ID, the number of transcriptions, timestamps, the app identifier and version, the SDK version, and macOS name and major version. No audio and no text.

                        hushpen is MIT-licensed. Voz and its SDK are source-available under the Desert Ant Labs license.
                        """, ["Back", "Model license", "desertant.com"])
                    if action == 1 { open("https://license.desertant.com/1.0") }
                    if action == 2 { open("https://desertant.com") }
                default: exit(0)
                }
            } catch let error as ToolError {
                show("Not finished", error.message, ["Back"])
            } catch {
                show("Not finished", error.localizedDescription, ["Back"])
            }
        }
    }

    private static func downloadModel() {
        let label = NSTextField(labelWithString: "Downloading the model (\(modelSize)) …")
        let result = runWithProgress(title: "Downloading model", label: label) {
            try await ModelImport.download { fraction in
                Task { @MainActor in
                    label.stringValue = fraction < 1
                        ? "Downloading the model … \(Int(fraction * 100)) %"
                        : "Checking the model. The first check can take a minute."
                }
            }
        }
        save(result)
    }

    private static func selectModel() {
        let picker = NSOpenPanel()
        picker.title = "Choose Voz model folder"
        picker.message = "Select the folder containing meta.json, vocab.json, embedding.f16 and the three .mlmodelc folders."
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let directory = picker.url else { return }
        let label = NSTextField(labelWithString: "Checking the model. The first check can take a minute.")
        save(runWithProgress(title: "Checking model", label: label) {
            try ModelImport.prepare(directory: directory)
        })
    }

    private static func save(_ result: Result<ModelConfig, Error>?) {
        guard let result else { return }
        do {
            try Config.saveModel(result.get())
            show("Model ready", "Next, choose Enable dictation.", ["OK"])
        } catch let error as ToolError {
            show("Model not ready", error.message, ["Back"])
        } catch {
            show("Model not ready", error.localizedDescription, ["Back"])
        }
    }

    private static func runWithProgress(title: String, label: NSTextField,
                                        work: @escaping @Sendable () async throws -> ModelConfig) -> Result<ModelConfig, Error>? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 110),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = title
        label.frame = NSRect(x: 20, y: 60, width: 410, height: 36)
        label.lineBreakMode = .byWordWrapping
        window.contentView?.addSubview(label)
        let spinner = NSProgressIndicator(frame: NSRect(x: 212, y: 18, width: 25, height: 25))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        window.contentView?.addSubview(spinner)
        window.center()
        let result = ImportResult()
        Task.detached {
            let outcome: Result<ModelConfig, Error>
            do { outcome = .success(try await work()) } catch { outcome = .failure(error) }
            await MainActor.run {
                result.value = outcome
                NSApplication.shared.stopModal()
            }
        }
        NSApplication.shared.runModal(for: window)
        window.orderOut(nil)
        return result.value
    }

    @MainActor
    private final class Choice: NSObject, NSWindowDelegate {
        var selected = -1
        @objc func press(_ sender: NSButton) {
            selected = sender.tag
            NSApplication.shared.stopModal()
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            NSApplication.shared.stopModal()
            return true
        }
    }

    private static func choose(_ title: String, _ message: String, _ buttons: [String]) -> Int {
        let choice = Choice()
        let textHeight: CGFloat = 110
        let height = 24 + textHeight + 16 + CGFloat(buttons.count) * 44 + 12
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.delegate = choice
        window.isReleasedWhenClosed = false
        let text = NSTextField(wrappingLabelWithString: message)
        text.frame = NSRect(x: 24, y: height - 24 - textHeight, width: 372, height: textHeight)
        window.contentView?.addSubview(text)
        for (index, title) in buttons.enumerated() {
            let button = NSButton(title: title, target: choice, action: #selector(Choice.press(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            button.frame = NSRect(x: 24, y: height - 24 - textHeight - 16 - CGFloat(index + 1) * 44 + 8,
                                  width: 372, height: 36)
            if index == 0 { button.keyEquivalent = "\r" }
            if index == buttons.count - 1 { button.keyEquivalent = "\u{1b}" }
            window.contentView?.addSubview(button)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.runModal(for: window)
        window.orderOut(nil)
        return choice.selected
    }

    @discardableResult
    private static func show(_ title: String, _ message: String, _ buttons: [String]) -> Int {
        if buttons.count > 3 { return choose(title, message, buttons) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    private static func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
