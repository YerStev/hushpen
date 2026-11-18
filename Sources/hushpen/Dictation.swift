import Foundation
import Voz

// One recording at a time inside the service. Audio stays in memory; the
// model is verified while the user speaks and then reused across dictations.
@MainActor
final class Dictation {
    static let maximumRecordingSeconds: Double = 300
    static let holdSeconds: Double = 300
    private enum Phase {
        case idle
        case starting
        case recording(Recorder, model: Task<Voz, Error>, startedAt: Date)
        case transcribing
        case holding(Result<String, ToolError>)
    }

    private var phase: Phase = .idle
    private var timeout: Task<Void, Never>?
    private let models: ModelHost
    private let paste: Bool
    private let cleanup: CleanupService?
    private let log: (String) -> Void
    private lazy var indicator = SessionIndicator(
        onStop: { [weak self] in Task { await self?.stop() } },
        onCancel: { [weak self] in self?.cancel() },
        log: { [weak self] in self?.log($0) }
    )

    // The final text remains in the clipboard whether automatic paste succeeds or not.
    // How long the cleanup may take before the transcript is used as it is.
    static let cleanupTimeout: Duration = .seconds(20)

    init(models: ModelHost, paste: Bool, cleanup: CleanupService?, log: @escaping (String) -> Void) {
        self.models = models
        self.paste = paste
        self.cleanup = cleanup
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
            phase = .transcribing
            indicator.transcribing()
            let outcome = await polished(await Self.transcribe(recorder: recorder, model: model, log: log))
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
        // The cleanup model loads and reads its instructions while the user
        // speaks.
        if let cleanup { Task { await cleanup.prepare() } }
        let models = self.models
        let model = Task { try await models.verifiedModel() }
        phase = .recording(recorder, model: model, startedAt: startedAt)
        indicator.recordingStarted(recorder, at: startedAt)
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
        phase = .transcribing
        indicator.transcribing()
        let outcome = await polished(await Self.transcribe(recorder: recorder, model: model, log: log))
        phase = .holding(outcome)
        indicator.finished(outcome, manualPaste: false, keepStatus: true)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.holdSeconds))
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }

    // The cleaned transcript, or the transcript itself if cleanup is off,
    // fails or takes too long.
    private func polished(_ outcome: Result<String, ToolError>) async -> Result<String, ToolError> {
        guard let cleanup, case .success(let text) = outcome else { return outcome }
        let cleaned = await Self.result(within: Self.cleanupTimeout) { await cleanup.clean(text) }
        if cleaned == nil { log("Cleanup took too long; the transcript is used as it is.") }
        return .success(cleaned ?? text)
    }

    // The work's result, or nil once the time is up. The work itself keeps
    // running (llama.cpp cannot be interrupted), but nobody waits for it. A
    // task group would not do: it waits for all its tasks before returning.
    nonisolated static func result<T: Sendable>(within limit: Duration,
                                    _ work: @escaping @Sendable () async -> T) async -> T? {
        let first = FirstResult<T>()
        return await withCheckedContinuation { continuation in
            first.continuation = continuation
            // Detached, so neither waits for the main actor.
            Task.detached { first.finish(await work()) }
            Task.detached {
                try? await Task.sleep(for: limit)
                first.finish(nil)
            }
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
                log("Automatic paste skipped (Accessibility: \(Paste.isTrusted), \(Paste.Target.current().description)). The text is in the clipboard.")
            }
            indicator.finished(outcome, manualPaste: manualPaste, pasteFailed: paste && manualPaste)
        }
    }

    private static func transcribe(recorder: Recorder, model: Task<Voz, Error>,
                                   log: (String) -> Void) async -> Result<String, ToolError> {
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
            let result = try await voz.transcribe(samples: Recorder.withTrailingSilence(samples))
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                // Length and loudness tell an accidental tap from a muted
                // microphone; no text is logged.
                let seconds = Double(samples.count) / Recorder.targetSampleRate
                let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
                log(String(format: "No speech in %.1f s of audio (peak level %.3f).", seconds, peak))
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

// Resumes a continuation with whichever value arrives first.
private final class FirstResult<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    var continuation: CheckedContinuation<T?, Never>?

    func finish(_ value: T?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let continuation else { return }
        finished = true
        continuation.resume(returning: value)
    }
}
