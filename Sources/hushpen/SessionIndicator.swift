import AppKit

// The menu-bar item and text box exist only while a dictation is active or its
// result is being shown. Transcript text appears only in the on-screen box,
// never in the menu bar, logs or files.
@MainActor
final class SessionIndicator {
    private var status: StatusItem?
    private let box = DictationBox()
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private let log: (String) -> Void
    private var display: Timer?
    private var dismissal: Task<Void, Never>?
    private static let resultSeconds = 1.8
    private static let actionSeconds = 3.5

    init(onStop: @escaping () -> Void, onCancel: @escaping () -> Void, log: @escaping (String) -> Void) {
        self.onStop = onStop
        self.onCancel = onCancel
        self.log = log
    }

    func recordingStarted(_ recorder: Recorder, at startedAt: Date) {
        dismissal?.cancel()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let seconds = Int(Date().timeIntervalSince(startedAt))
                let level = recorder.level
                self?.show(.recording(seconds: seconds, level: level))
                self?.box.setLevel(level)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        display = timer
        show(.recording(seconds: 0, level: 0))
        box.show()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard let self, self.display != nil, !self.box.isOnScreen else { return }
            self.log("The dictation box did not appear on the current screen (\(self.box.screenReport)); rebuilding it.")
            self.box.recover()
            try? await Task.sleep(for: .seconds(0.3))
            guard self.display != nil else { return }
            self.log(self.box.isOnScreen ? "The rebuilt dictation box is on screen."
                                         : "The rebuilt dictation box is still not on screen (\(self.box.screenReport)).")
        }
    }

    func liveText(_ text: String) {
        box.setText(text)
    }

    func transcribing() {
        stopDisplay()
        show(.transcribing)
        box.transcribing()
    }

    // The box fades out on success and shakes when pasting failed or nothing
    // was recognized. A held result keeps the menu-bar item until it is
    // delivered or expires.
    func finished(_ outcome: Result<String, ToolError>, manualPaste: Bool,
                  pasteFailed: Bool = false, keepStatus: Bool = false) {
        stopDisplay()
        let seconds: Double
        switch outcome {
        case .success:
            show(.done(manualPaste: manualPaste))
            seconds = manualPaste ? Self.actionSeconds : Self.resultSeconds
            if pasteFailed { box.shakeAndDismiss() } else { box.dismiss() }
        case .failure(let error):
            show(.failed(error))
            seconds = Self.actionSeconds
            box.shakeAndDismiss()
        }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if !keepStatus { self.removeStatus() }
        }
    }

    // The paste was sent but the text field did not change. The box comes
    // back for a moment with a hint, as the text would otherwise seem lost.
    func pasteMissed() {
        show(.done(manualPaste: true))
        box.show()
        box.setText("Not pasted. The text is in the clipboard: press \u{2318}V.")
        box.transcribing()
        box.shakeAndDismiss(after: Self.actionSeconds)
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.actionSeconds))
            guard !Task.isCancelled else { return }
            self?.removeStatus()
        }
    }

    func dismiss() {
        stopDisplay()
        dismissal?.cancel()
        box.dismiss()
        removeStatus()
    }

    private func stopDisplay() {
        display?.invalidate()
        display = nil
    }

    private func removeStatus() {
        status?.remove()
        status = nil
    }

    private func show(_ state: StatusItem.State) {
        if status == nil {
            status = StatusItem(onStop: onStop, onCancel: onCancel)
        }
        status?.render(state)
    }
}
