import Foundation

// Runs the cleanup model for the service. It is loaded when a dictation
// starts, so loading overlaps with speaking, and unloaded after a while
// without dictation to give its memory (about 4 GB) back.
actor CleanupService {
    static let idleUnload: Duration = .seconds(600)

    private var runner: LlamaRunner?
    private var unload: Task<Void, Never>?
    private let log: @Sendable (String) -> Void

    init(log: @escaping @Sendable (String) -> Void) {
        self.log = log
    }

    // Loads the model if needed and processes the instructions.
    func prepare() {
        unload?.cancel()
        do {
            if runner == nil {
                let started = ContinuousClock.now
                runner = try LlamaRunner(modelPath: try CleanupModel.verifiedPath())
                log("Cleanup model loaded in \(Self.seconds(since: started)).")
            }
            if let runner { try TextCleanup.warm(runner) }
        } catch let error as ToolError {
            log("Cleanup model not loaded: \(error.message)")
        } catch {
            log("Cleanup model not loaded: \(error.localizedDescription)")
        }
    }

    // The cleaned text, or the transcript itself when cleanup is not possible.
    // Only the outcome and the time are logged, never text.
    func clean(_ text: String) -> String {
        prepare()
        defer { scheduleUnload() }
        guard let runner else { return text }
        let started = ContinuousClock.now
        do {
            let outcome = try TextCleanup.clean(text) { system, user, maxTokens in
                try runner.generate(system: system, user: user, maxTokens: maxTokens)
            }
            switch outcome {
            case .changed(let cleaned):
                log("Cleanup: changed in \(Self.seconds(since: started)).")
                return cleaned
            case .unchanged:
                log("Cleanup: unchanged in \(Self.seconds(since: started)).")
            case .rejected(let reason):
                log("Cleanup: result not used (\(reason)) after \(Self.seconds(since: started)).")
            }
        } catch let error as ToolError {
            log("Cleanup failed: \(error.message)")
        } catch {
            log("Cleanup failed: \(error.localizedDescription)")
        }
        return text
    }

    func shutDown() {
        unload?.cancel()
        runner = nil
    }

    private func scheduleUnload() {
        unload?.cancel()
        unload = Task { [weak self] in
            try? await Task.sleep(for: Self.idleUnload)
            guard !Task.isCancelled else { return }
            await self?.release()
        }
    }

    private func release() {
        guard runner != nil else { return }
        runner = nil
        log("Cleanup model unloaded after inactivity.")
    }

    private static func seconds(since start: ContinuousClock.Instant) -> String {
        let duration = ContinuousClock.now - start
        return String(format: "%.2f s", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }
}
