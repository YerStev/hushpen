import AppKit

// A click-through glass box near the bottom of the active screen. It grows
// upward with the live transcript; its bottom edge glows orange with the voice.
// No result is shown: the box simply fades out, or shakes when the text could
// not be pasted or nothing was recognized.
@MainActor
final class DictationBox {
    private enum Mode { case listening, speaking, transcribing }

    private let panel: NSPanel
    private let container: NSView
    private let label: NSTextField
    private let edge = EdgeGlowView()
    private var animation: Timer?
    private var text: String?
    private var mode: Mode = .listening
    private var screenFrame = NSRect.zero
    private var isVisible = false
    private var dismissal: Task<Void, Never>?

    static let width: CGFloat = 560
    static let margin: CGFloat = 26
    static let radius: CGFloat = 22
    private static let padding = NSSize(width: 20, height: 14)
    private static let minHeight: CGFloat = 48
    private static let bottomInset: CGFloat = 84
    private static let font = NSFont.systemFont(ofSize: 15)
    private static let freshWords = 4

    init() {
        let size = NSSize(width: Self.width + 2 * Self.margin, height: Self.minHeight + 2 * Self.margin)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
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

        container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]

        label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = false
        label.drawsBackground = false
        label.lineBreakMode = .byWordWrapping
        label.autoresizingMask = [.width, .height]

        let glassFrame = container.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let content = NSView(frame: NSRect(origin: .zero, size: glassFrame.size))
        content.autoresizingMask = [.width, .height]
        label.frame = content.bounds.insetBy(dx: Self.padding.width, dy: Self.padding.height)
        content.addSubview(label)

        let glass: NSView
        if #available(macOS 26.0, *) {
            let liquid = NSGlassEffectView(frame: glassFrame)
            liquid.cornerRadius = Self.radius
            liquid.contentView = content
            glass = liquid
        } else {
            let material = NSVisualEffectView(frame: glassFrame)
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = Self.radius
            material.layer?.masksToBounds = true
            material.addSubview(content)
            glass = material
        }
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass)

        edge.frame = container.bounds
        edge.autoresizingMask = [.width, .height]
        container.addSubview(edge)
        panel.contentView = container
    }

    // MARK: - Lifecycle

    func show() {
        dismissal?.cancel()
        container.layer?.removeAllAnimations()
        screenFrame = Self.activeScreen()
        mode = .listening
        text = nil
        edge.reset()
        edge.mode = .voice
        layout(animated: false)
        if !isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        isVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        startAnimation()
    }

    func setText(_ newText: String) {
        guard isVisible, newText != text else { return }
        text = newText
        if mode == .listening { mode = .speaking }
        layout(animated: true)
    }

    func setLevel(_ level: Float) {
        edge.level = CGFloat(level)
    }

    func transcribing() {
        mode = .transcribing
        edge.mode = .calm
        layout(animated: false)
    }

    func dismiss() {
        guard isVisible else { return }
        dismissal?.cancel()
        edge.mode = .off
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishHiding() }
        }
    }

    // Paste failed or nothing was recognized; the text, if any, is in the clipboard.
    func shakeAndDismiss() {
        guard isVisible else { return }
        edge.mode = .off
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -14, 12, -9, 6, -3, 0]
        shake.keyTimes = [0, 0.15, 0.32, 0.5, 0.67, 0.84, 1]
        shake.duration = 0.5
        container.layer?.add(shake, forKey: "shake")
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func finishHiding() {
        guard panel.alphaValue < 0.01 else { return }
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

    // MARK: - Layout

    // Grows upward to show the whole transcript. Only beyond 60 % of the
    // screen height are the oldest words dropped.
    private func layout(animated: Bool) {
        let textWidth = Self.width - 2 * Self.padding.width
        let maxTextHeight = screenFrame.height * 0.6 - 2 * Self.padding.height
        let (string, textHeight) = fittedText(width: textWidth, maxHeight: maxTextHeight)
        label.attributedStringValue = string

        let height = max(Self.minHeight, textHeight + 2 * Self.padding.height)
        let frame = NSRect(x: screenFrame.midX - Self.width / 2 - Self.margin,
                           y: screenFrame.minY + Self.bottomInset - Self.margin,
                           width: Self.width + 2 * Self.margin,
                           height: height + 2 * Self.margin)
        guard frame != panel.frame else { return }
        if animated && isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func fittedText(width: CGFloat, maxHeight: CGFloat) -> (NSAttributedString, CGFloat) {
        guard let text, !text.isEmpty else {
            let placeholder = NSAttributedString(string: "Listening…", attributes: [
                .font: Self.font, .foregroundColor: NSColor.tertiaryLabelColor,
            ])
            return (placeholder, measure(placeholder, width: width))
        }
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var trimmed = false
        while true {
            let string = styled(words, trimmed: trimmed)
            let height = measure(string, width: width)
            if height <= maxHeight || words.count <= 1 { return (string, height) }
            words.removeFirst(max(1, words.count / 10))
            trimmed = true
        }
    }

    // Older words recede; the newest ones are in full colour while speaking.
    private func styled(_ words: [String], trimmed: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        let result = NSMutableAttributedString()
        for (index, word) in words.enumerated() {
            let fresh = mode == .speaking && index >= words.count - Self.freshWords
            let color: NSColor = mode == .transcribing ? .secondaryLabelColor : (fresh ? .labelColor : .secondaryLabelColor)
            let prefix = index == 0 ? (trimmed ? "…" : "") : " "
            result.append(NSAttributedString(string: prefix + word, attributes: [
                .font: Self.font, .foregroundColor: color, .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    // Measured by the label's own cell: it has insets of its own and omits a
    // last line that does not fit completely.
    private func measure(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
        label.attributedStringValue = string
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return ceil(size?.height ?? 0) + 2
    }

    private static func activeScreen() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

// The glowing bottom edge. Loudness spreads from the centre outward, so the
// edge reads as a voice rather than a fixed meter.
@MainActor
final class EdgeGlowView: NSView {
    enum Mode { case voice, calm, off }

    var mode: Mode = .voice
    var level: CGFloat = 0
    private var history = [CGFloat](repeating: 0, count: 36)
    private var smoothed: CGFloat = 0
    private var fade: CGFloat = 0
    private let start = Date()

    private static let core = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
    private static let halo = NSColor(srgbRed: 1.0, green: 0.48, blue: 0.0, alpha: 1)

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reset() {
        history = history.map { _ in 0 }
        smoothed = 0
        fade = 0
    }

    func tick() {
        smoothed += (level - smoothed) * 0.35
        history.insert(mode == .voice ? smoothed : 0, at: 0)
        history.removeLast()
        fade += ((mode == .off ? 0 : 1) - fade) * 0.2
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard fade > 0.01 else { return }
        let box = bounds.insetBy(dx: DictationBox.margin, dy: DictationBox.margin)
        let x0 = box.minX + DictationBox.radius * 0.6
        let x1 = box.maxX - DictationBox.radius * 0.6
        let time = Date().timeIntervalSince(start)

        let stops = 64
        var colors: [NSColor] = []
        var locations: [CGFloat] = []
        for i in 0...stops {
            let t = CGFloat(i) / CGFloat(stops)
            colors.append(Self.core.withAlphaComponent(intensity(at: t, time: time) * fade))
            locations.append(t)
        }
        guard let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .sRGB),
              let context = NSGraphicsContext.current?.cgContext else { return }

        let line = CGMutablePath()
        line.move(to: CGPoint(x: x0, y: box.minY + 0.8))
        line.addLine(to: CGPoint(x: x1, y: box.minY + 0.8))

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 12,
                          color: Self.halo.withAlphaComponent(0.85 * fade).cgColor)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(line)
        context.setLineWidth(2.6)
        context.setLineCap(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        gradient.draw(in: NSRect(x: x0, y: box.minY - 4, width: x1 - x0, height: 8), angle: 0)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func intensity(at t: CGFloat, time: TimeInterval) -> CGFloat {
        let ends = pow(sin(.pi * t), 0.6)
        switch mode {
        case .voice, .off:
            let distance = abs(t - 0.5) * 2
            let position = distance * CGFloat(history.count - 1)
            let lower = Int(position)
            let upper = min(history.count - 1, lower + 1)
            let fraction = position - CGFloat(lower)
            let value = history[lower] * (1 - fraction) + history[upper] * fraction
            let shimmer = 0.85 + 0.15 * sin(time * 7 + Double(t) * 18)
            return min(1, 0.1 + value * 1.7 * shimmer) * ends
        case .calm:
            let center = CGFloat((time / 1.4).truncatingRemainder(dividingBy: 1))
            let pulse = exp(-pow((t - center) / 0.14, 2))
            return (0.12 + 0.6 * pulse) * ends
        }
    }
}
