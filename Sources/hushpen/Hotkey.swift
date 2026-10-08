import AppKit
import Carbon.HIToolbox

final class HotkeyMonitor {
    struct Combination {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let description: String
    }

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    @MainActor private static var active: HotkeyMonitor?

    @MainActor
    init(combination: Combination, action: @escaping @MainActor () -> Void) throws {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                MainActor.assumeIsolated { HotkeyMonitor.active?.action() }
                return noErr
            },
            1, &eventType, nil, &handler
        )
        guard installStatus == noErr else {
            throw ToolError(.failure, "Could not install the hotkey handler (Status \(installStatus)).")
        }

        let identifier = EventHotKeyID(signature: OSType(0x44494354), id: 1)
        let status = RegisterEventHotKey(combination.keyCode, combination.carbonModifiers,
                                         identifier, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, reference != nil else {
            throw ToolError(.failure, """
                Could not register hotkey \(combination.description) (Status \(status)).
                Another app may be using it. Choose a different shortcut:

                  hushpen --hotkey ctrl+alt+d
                """)
        }
        HotkeyMonitor.active = self
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static let namedKeys: [String: Int] = [
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return,
        "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
        "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14,
        "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18,
        "f19": kVK_F19, "f20": kVK_F20,
    ]

    private static let letterKeys: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    static func parse(_ specification: String) throws -> Combination {
        let parts = specification.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let keyPart = parts.last else {
            throw ToolError(.usage, "The shortcut is empty.")
        }

        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
            case "shift", "⇧": modifiers |= UInt32(shiftKey)
            case "alt", "option", "opt", "⌥": modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
            default:
                throw ToolError(.usage, """
                    Unknown modifier: \(modifier)
                    Allowed modifiers: cmd, shift, alt, ctrl.
                    """)
            }
        }

        let keyCode: Int
        if let named = namedKeys[keyPart] {
            keyCode = named
        } else if keyPart.count == 1, let letter = letterKeys[Character(keyPart)] {
            keyCode = letter
        } else {
            throw ToolError(.usage, """
                Unknown key: \(keyPart)
                Allowed keys: a–z, 0–9, space, return, tab, escape and f1–f20.
                """)
        }

        if modifiers == 0 && !keyPart.hasPrefix("f") {
            throw ToolError(.usage, """
                \(specification) has no modifier and would intercept ordinary typing.
                Add a modifier (cmd+shift+d) or use a function key (f18).
                """)
        }

        return Combination(keyCode: UInt32(keyCode), carbonModifiers: modifiers,
                           description: specification)
    }
}

@MainActor
final class FnKeyMonitor {
    static let specification = "fn"
    private static let maximumTapSeconds = 0.4

    private var monitor: Any?
    private var pressedAt: Date?
    private var keyDownsAtPress: UInt32 = 0
    private var isDown = false
    private let action: @MainActor () -> Void
    private let log: @MainActor (String) -> Void

    static func matches(_ specification: String) -> Bool {
        ["fn", "globe", "🌐"].contains(specification.lowercased())
    }

    init(log: @escaping @MainActor (String) -> Void, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.log = log
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.modifierFlags) }
        }
        log("Fn monitor \(monitor == nil ? "NOT installed" : "installed").")
    }

    private static var keyDownCount: UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
    }

    private func handle(_ rawFlags: NSEvent.ModifierFlags) {
        let flags = rawFlags.intersection(.deviceIndependentFlagsMask)
        let fnDown = flags.contains(.function)
        defer { isDown = fnDown }

        guard flags.subtracting(.function).isEmpty else {
            pressedAt = nil
            return
        }

        if fnDown && !isDown {
            pressedAt = Date()
            keyDownsAtPress = Self.keyDownCount
        } else if !fnDown && isDown, let start = pressedAt {
            pressedAt = nil
            let held = Date().timeIntervalSince(start)
            let keyDowns = Self.keyDownCount &- keyDownsAtPress
            guard held <= Self.maximumTapSeconds, keyDowns == 0 else { return }
            action()
        }
    }
}
