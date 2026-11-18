import AppKit

@MainActor
enum Output {
    static func setClipboard(_ text: String, on pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // Keep the dictation available for manual paste even when an app accepts
    // Command-V but exposes no reliable acknowledgement through Accessibility.
    // No delayed restoration can overwrite this or a later clipboard change.
    @discardableResult
    static func deliverAndPaste(_ text: String, paste: Bool, pasteboard: NSPasteboard = .general) -> Bool {
        setClipboard(text, on: pasteboard)
        guard paste, Paste.isTrusted, Paste.Target.current().acceptsPaste else { return false }
        return Paste.sendCommandV()
    }
}
