import Foundation
import Voz

// One recording at a time inside the service. Audio stays in memory; the
// model is verified while the user speaks and then reused across dictations.
@MainActor
final class Dictation {
    static let maximumRecordingSeconds: Double = 300
    static let holdSeconds: Double = 300
    // The live preview re-transcribes only the audio after its last settled
    // word, so each pass stays short; settled words are kept, so the preview
    // still shows the whole dictation.
    static let previewWindowSeconds: Double = 14
    static let previewSettleSeconds: Double = 4
    static let previewInterval: Duration = .milliseconds(700)

    private enum Phase {
        case idle
        case starting
        case recording(Recorder, model: Task<Voz, Error>, startedAt: Date)
        case transcribing
        case holding(Result<String, ToolError>)
    }

    private var phase: Phase = .idle
    private var timeout: Task<Void, Never>?
    private var preview: Task<Void, Never>?
    private let models: ModelHost
    private let paste: Bool
    private let log: (String) -> Void
    private lazy var indicator = SessionIndicator(
        onStop: { [weak self] in Task { await self?.stop() } },
        onCancel: { [weak self] in self?.cancel() }
    )

    // With paste on, the text is inserted and the clipboard restored; it is
    // left in the clipboard only when pasting is off or fails.
    init(models: ModelHost, paste: Bool, log: @escaping (String) -> Void) {
        self.models = models
        self.paste = paste
        self.log = log
    }

    // Presses during start-up or transcription are ignored.
    func toggle() async {
        switch phase {
        case .idle: await start()
        case .recording, .holding: await stop()
        case .starting, .transcribing: log("Shortcut ignored: the previous dictation is still being processed.")
        }
    }

    func stop() async {
        switch phase {
        case .idle, .starting, .transcribing:
            return
        case .holding(let outcome):
            timeout?.cancel()
            phase = .idle
            deliver(outcome)
        case .recording(let recorder, let model, _):
            timeout?.cancel()
            preview?.cancel()
            phase = .transcribing
            indicator.transcribing()
            let outcome = await Self.transcribe(recorder: recorder, model: model)
            phase = .idle
            deliver(outcome)
        }
    }

    func cancel() {
        switch phase {
        case .recording(let recorder, let model, _):
            recorder.cancel()
            model.cancel()
        case .holding:
            break
        case .idle, .starting, .transcribing:
            return
        }
        timeout?.cancel()
        preview?.cancel()
        phase = .idle
        indicator.dismiss()
    }

    private func start() async {
        phase = .starting
        let recorder = Recorder()
        do {
            try await Recorder.ensureMicrophoneAccess()
            try recorder.start()
        } catch {
            phase = .idle
            let failure = error as? ToolError ?? ToolError(.microphone, error.localizedDescription)
            indicator.finished(.failure(failure), manualPaste: false)
            log("Recording failed: \(failure.message)")
            return
        }

        let startedAt = Date()
        let models = self.models
        let model = Task { try await models.verifiedModel() }
        phase = .recording(recorder, model: model, startedAt: startedAt)
        indicator.recordingStarted(recorder, at: startedAt)
        preview = Task { [weak self] in await self?.runPreview(recorder: recorder, model: model) }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumRecordingSeconds))
            guard !Task.isCancelled else { return }
            await self?.stopAtLimit()
        }
    }

    // The automatic stop holds the result for the next toggle instead of
    // pasting into whatever app is in front after five minutes.
    private func stopAtLimit() async {
        guard case .recording(let recorder, let model, _) = phase else { return }
        preview?.cancel()
        phase = .transcribing
        indicator.transcribing()
        let outcome = await Self.transcribe(recorder: recorder, model: model)
        phase = .holding(outcome)
        indicator.finished(outcome, manualPaste: false, keepStatus: true)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }

    // Shows a provisional transcript while the user speaks. It is displayed
    // only in the on-screen preview; the delivered text always comes from the
    // final pass over the complete recording.
    private func runPreview(recorder: Recorder, model: Task<Voz, Error>) async {
        guard let voz = try? await model.value else { return }
        var settled: [String] = []
        var settledUntil = 0
        var lastTotal = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.previewInterval)
            guard !Task.isCancelled,
                  let snapshot = try? recorder.snapshot(from: settledUntil),
                  snapshot.samples.count >= Int(Recorder.targetSampleRate / 2),
                  snapshot.total > lastTotal else { continue }
            lastTotal = snapshot.total
            guard let result = try? await voz.transcribe(samples: snapshot.samples),
                  !Task.isCancelled else { continue }
            var words = result.words

            // Once the window is long, keep the words well before its end and
            // continue the next pass from the pause after the last of them.
            let windowSeconds = Double(snapshot.samples.count) / Recorder.targetSampleRate
            if windowSeconds > Self.previewWindowSeconds,
               let last = words.lastIndex(where: { $0.end < windowSeconds - Self.previewSettleSeconds }),
               last + 1 < words.count {
                settled += words[...last].map(\.text)
                let cut = (words[last].end + words[last + 1].start) / 2
                settledUntil += Int(cut * snapshot.rate)
                words.removeFirst(last + 1)
            }
            let text = (settled + words.map(\.text)).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { indicator.liveText(text) }
        }
    }

    private func deliver(_ outcome: Result<String, ToolError>) {
        switch outcome {
        case .failure(let error):
            indicator.finished(outcome, manualPaste: false)
            log("Dictation failed: \(error.message)")
        case .success(let text):
            let manualPaste = !Output.deliverAndPaste(text, paste: paste)
            if paste && manualPaste {
                log("Automatic paste skipped: Accessibility access is missing. The text is in the clipboard.")
            }
            indicator.finished(outcome, manualPaste: manualPaste, pasteFailed: paste && manualPaste)
        }
    }

    private static func transcribe(recorder: Recorder, model: Task<Voz, Error>) async -> Result<String, ToolError> {
        let samples: [Float]
        do {
            samples = try recorder.stopAndTakeSamples()
        } catch let error as ToolError {
            return .failure(error)
        } catch {
            return .failure(ToolError(.failure, error.localizedDescription))
        }

        guard !samples.isEmpty else {
            return .failure(ToolError(.transcription, "No audio was recorded. Is the microphone muted?"))
        }

        do {
            let voz = try await model.value
            let result = try await voz.transcribe(samples: samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return .failure(ToolError(.transcription, "No speech was recognized."))
            }
            return .success(text)
        } catch let error as ToolError {
            return .failure(error)
        } catch {
            return .failure(ToolError(.transcription, "Transcription failed: \(String(describing: type(of: error)))"))
        }
    }
}
