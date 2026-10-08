import AppKit

@MainActor
final class StatusItem {
    enum State {
        case idle
        case recording(seconds: Int, level: Float)
        case transcribing
        case done(manualPaste: Bool)
        case failed(reason: String)

        static func failed(_ error: ToolError) -> State {
            switch error.code {
            case .transcription: .failed(reason: "no speech recognized")
            case .microphone: .failed(reason: "no microphone")
            case .modelMissing, .modelDigestMismatch: .failed(reason: "model unavailable")
            default: .failed(reason: "Error")
            }
        }
    }

    private let item: NSStatusItem
    private let target: Target

    init(onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        target = Target(onStop: onStop, onCancel: onCancel)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.alignment = .left
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        render(.recording(seconds: Int(Dictation.maximumRecordingSeconds), level: 1))
        item.length = ceil(item.button?.fittingSize.width ?? 110)
        render(.idle)
        buildMenu()
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    var diagnostics: String {
        let hasButton = item.button != nil
        let hasImage = item.button?.image != nil
        let visible = item.isVisible
        return "Menu bar: button \(hasButton ? "yes" : "NO"), "
            + "Image \(hasImage ? "loaded" : "MISSING"), "
            + "visible \(visible ? "yes" : "NO")"
    }

    func render(_ state: State) {
        guard let button = item.button else { return }

        switch state {
        case .idle:
            button.image = symbol("mic", description: "Ready to dictate")
            button.title = ""
            button.contentTintColor = nil

        case .recording(let seconds, let level):
            button.image = symbol("mic.fill", description: "Recording")
            button.title = " \(timeString(seconds)) \(meter(level))"
            button.contentTintColor = .systemOrange

        case .transcribing:
            button.image = symbol("waveform", description: "Transcribing")
            button.title = " …"
            button.contentTintColor = .secondaryLabelColor

        case .done(let manualPaste):
            button.image = manualPaste
                ? symbol("doc.on.clipboard", description: "Copied to clipboard")
                : symbol("checkmark.circle", description: "Pasted")
            button.title = ""
            button.contentTintColor = .systemOrange

        case .failed:
            button.image = symbol("exclamationmark.triangle", description: "failed")
            button.title = ""
            button.contentTintColor = .systemRed
        }
    }

    private func symbol(_ name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func meter(_ level: Float) -> String {
        let steps: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"]
        let bars = 5
        var out = ""
        for bar in 0..<bars {
            let share = (level - Float(bar) / Float(bars)) * Float(bars)
            let clamped = max(0, min(1, share))
            let index = Int(clamped * Float(steps.count - 1))
            out.append(steps[index])
        }
        return out
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Stop recording",
                                action: #selector(Target.stop), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Discard recording",
                                action: #selector(Target.cancel), keyEquivalent: ""))
        for entry in menu.items { entry.target = target }
        item.menu = menu
    }

    @MainActor
    private final class Target: NSObject {
        private let onStop: () -> Void
        private let onCancel: () -> Void

        init(onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onStop = onStop
            self.onCancel = onCancel
        }

        @objc func stop() { onStop() }
        @objc func cancel() { onCancel() }
    }
}
