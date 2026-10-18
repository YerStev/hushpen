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

    // The app in front and its focused element, read through Accessibility.
    // Only the role and the character count are read, never the text.
    struct Target: Equatable {
        let app: String
        let role: String?
        let characters: Int?
        let secureInput: Bool

        static func current() -> Target {
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
            let secureInput = IsSecureEventInputEnabled()
            // Short timeout: a busy app must not stall the service.
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 0.25)
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(systemWide,
                                                kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                  let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                return Target(app: app, role: nil, characters: nil, secureInput: secureInput)
            }
            let element = focused as! AXUIElement
            AXUIElementSetMessagingTimeout(element, 0.25)
            var role: CFTypeRef?
            var count: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count)
            return Target(app: app, role: role as? String, characters: (count as? NSNumber)?.intValue,
                          secureInput: secureInput)
        }

        var description: String {
            "app \(app), focused \(role ?? "nothing"), characters \(characters.map(String.init) ?? "unknown"), "
                + "secure input \(secureInput ? "on" : "off")"
        }
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
