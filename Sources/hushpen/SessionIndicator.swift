import AppKit

// The menu-bar item and screen border show state without displaying text.
@MainActor
final class SessionIndicator {
    private var status: StatusItem?
    private let border = ScreenBorder()
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
                self?.border.setLevel(level)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        display = timer
        show(.recording(seconds: 0, level: 0))
        border.show()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard let self, self.display != nil, !self.border.isOnScreen else { return }
            self.log("The screen border did not appear on the current screen (\(self.border.screenReport)); rebuilding it.")
            self.border.recover()
            try? await Task.sleep(for: .seconds(0.3))
            guard self.display != nil else { return }
            self.log(self.border.isOnScreen ? "The rebuilt screen border is on screen."
                                         : "The rebuilt screen border is still not on screen (\(self.border.screenReport)).")
        }
    }

    func transcribing() {
        stopDisplay()
        show(.transcribing)
        border.transcribing()
    }

    // The border fades out on success and lingers when pasting failed or nothing
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
            if pasteFailed { border.lingerAndDismiss() } else { border.dismiss() }
        case .failure(let error):
            show(.failed(error))
            seconds = Self.actionSeconds
            border.lingerAndDismiss()
        }
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            if !keepStatus { self.removeStatus() }
        }
    }

    func dismiss() {
        stopDisplay()
        dismissal?.cancel()
        border.dismiss()
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
