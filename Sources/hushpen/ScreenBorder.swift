import AppKit

// A transparent, click-through orange border around the active display.
// No transcript is rendered and the panel never takes keyboard focus.
@MainActor
final class ScreenBorder {
    private var panel: NSPanel
    private let edge = EdgeGlowView()
    private var container: NSView { edge }
    private var animation: Timer?
    private var isVisible = false
    private var dismissal: Task<Void, Never>?
    private var generation = 0

    init() {
        panel = Self.makePanel(size: Self.activeScreen().size)
        edge.autoresizingMask = [.width, .height]
        panel.contentView = edge
    }

    // MARK: - Lifecycle

    func show() {
        dismissal?.cancel()
        panel.setFrame(Self.activeScreen(), display: true)
        edge.reset()
        edge.mode = .voice
        generation += 1
        if !isVisible { panel.alphaValue = 0 }
        // Ordered in on every show: cheap when it is already in front, and it
        // recovers a panel that is no longer on screen.
        panel.orderFrontRegardless()
        isVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        startAnimation()
    }

    func setLevel(_ level: Float) {
        edge.level = CGFloat(level)
    }

    func transcribing() {
        edge.mode = .calm
    }

    func dismiss() {
        guard isVisible else { return }
        dismissal?.cancel()
        edge.mode = .off
        let hiding = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHiding(hiding) }
        }
    }

    // Whether the panel actually reached the current screen.
    var isOnScreen: Bool {
        panel.isVisible && panel.isOnActiveSpace && panel.alphaValue > 0.5
    }

    // For the log: which part of isOnScreen failed, and where.
    var screenReport: String {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        return "visible \(panel.isVisible), active space \(panel.isOnActiveSpace), "
            + String(format: "alpha %.2f, ", panel.alphaValue)
            + "occluded \(!panel.occlusionState.contains(.visible)), front app \(front)"
    }

    // A long-lived panel can stop appearing after Space or Stage Manager
    // changes while a new one appears normally, so the border moves its content
    // to a new panel.
    func recover() {
        guard isVisible else { return }
        let old = panel
        panel = Self.makePanel(size: old.frame.size)
        old.contentView = nil
        old.orderOut(nil)
        panel.contentView = container
        panel.setFrame(old.frame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    #if DEBUG
    // For tests: the panel drops off screen, as macOS sometimes does.
    func simulateLostPanel() {
        panel.orderOut(nil)
    }
    #endif

    private static func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        return panel
    }

    // Paste failed or nothing was recognized; the text, if any, is in the clipboard.
    func lingerAndDismiss(after seconds: Double = 0.9) {
        guard isVisible else { return }
        edge.mode = .calm
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func finishHiding(_ hiding: Int) {
        guard hiding == generation else { return }
        panel.orderOut(nil)
        animation?.invalidate()
        animation = nil
        isVisible = false
    }

    private func startAnimation() {
        guard animation == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.edge.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private static func activeScreen() -> NSRect {
        let mouse = NSEvent.mouseLocation
        return (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

@MainActor
final class EdgeGlowView: NSView {
    enum Mode { case voice, calm, off }
    var mode: Mode = .voice
    var level: CGFloat = 0
    private var smoothed: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reset() { smoothed = 0; level = 0 }
    func tick() {
        let target = max(0, min(1, level))
        smoothed += (target - smoothed) * (target > smoothed ? 0.065 : 0.055)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard mode != .off, let context = NSGraphicsContext.current?.cgContext else { return }
        // Geometry stays fixed. Only brightness responds to speech, with a
        // smooth rise so speech becomes clearly visible without sharp flashes.
        // The quieter baseline and response curve preserve room for louder speech.
        let voice = pow(max(0, min(1, (smoothed - 0.06) / 0.65)), 0.95)
        let intensity: CGFloat = mode == .voice ? 0.055 + voice * 0.945 : 0.18
        let orange = NSColor(srgbRed: 1, green: 0.62, blue: 0.10, alpha: 1)
        let path = CGPath(roundedRect: bounds.insetBy(dx: 3, dy: 3),
                          cornerWidth: 18, cornerHeight: 18, transform: nil)
        context.saveGState()
        // Broad, faint strokes build a soft halo up to 60 points into the
        // display. The window clips the outer half at the physical edge.
        let glow: [(CGFloat, CGFloat)] = [
            (120, 0.012), (100, 0.018), (80, 0.026), (64, 0.038),
            (48, 0.055), (34, 0.08), (22, 0.12), (12, 0.20),
            (6, 0.35), (2.5, 1.0),
        ]
        for (width, alpha) in glow {
            context.addPath(path)
            context.setLineWidth(width)
            context.setStrokeColor(orange.withAlphaComponent(alpha * intensity).cgColor)
            context.strokePath()
        }
        context.restoreGState()
    }
}
