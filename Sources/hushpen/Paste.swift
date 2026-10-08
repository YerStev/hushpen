import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Paste {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func sendCommandV() -> Bool {
        guard isTrusted else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let key = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static let missingTrustHint = """
        Pasting needs Accessibility access. Turn on hushpen under System Settings
        → Privacy & Security → Accessibility, then restart the service:
          launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent
        After an ad-hoc rebuild, remove hushpen from the list and add it again.
        """
}
