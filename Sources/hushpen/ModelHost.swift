import Foundation
import Voz

// Keeps one verified Voz instance alive. The SDK manages licensing on load.
actor ModelHost {
    private var loaded: (config: ModelConfig, voz: Voz)?

    var isLoaded: Bool { loaded != nil }

    // Re-hashes the registered folder before every use. Reuses the loaded model
    // while the registration and contents are unchanged; otherwise loads anew.
    func verifiedModel() async throws -> Voz {
        let config: ModelConfig
        let directory: URL
        do {
            config = try Config.loadModel()
            directory = try Config.verify(config)
        } catch {
            await unload()
            throw error
        }
        if let loaded, loaded.config.directory == config.directory,
           loaded.config.digest == config.digest {
            return loaded.voz
        }
        let voz = try Voz(modelDirectory: directory)
        guard voz.sampleRate == Recorder.targetSampleRate else {
            throw ToolError(.failure, "The model expects \(Int(voz.sampleRate)) Hz; hushpen supplies \(Int(Recorder.targetSampleRate)) Hz.")
        }
        await flushLicense()
        loaded = (config, voz)
        return voz
    }

    // Drop a model whose folder failed verification, after in-flight license requests finish.
    func unload() async {
        await flushLicense()
        loaded = nil
    }

    // Before replacing the model or stopping the service.
    func flushLicense() async {
        if let voz = loaded?.voz {
            await Telemetry.flushPendingLicense(keeping: voz)
        }
    }
}
