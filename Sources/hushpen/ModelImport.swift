import Foundation
import Voz

enum ModelImport {
    static var defaultDirectory: URL {
        Paths.stateDirectory.appendingPathComponent("models/voz-v0.1.0", isDirectory: true)
    }

    // Fetches the pinned revision from huggingface.co through the SDK, which
    // checks each file's size and SHA-256, then validates and registers it.
    static func download(progress: @escaping @Sendable (Double) -> Void) async throws -> ModelConfig {
        let directory = defaultDirectory
        do {
            try Paths.ensureStateDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = try await Voz.download(directory: directory.path) { progress($0.fraction) }
            return try prepare(directory: URL(fileURLWithPath: path))
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError(.modelMissing, "The model could not be downloaded: \(error.localizedDescription)\nCheck your internet connection and try again.")
        }
    }

    static func prepare(directory: URL) throws -> ModelConfig {
        let fm = FileManager.default
        for name in ["meta.json", "vocab.json", "embedding.f16"] {
            let url = directory.appendingPathComponent(name)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 else {
                throw ToolError(.modelMissing, "A complete file is missing from the model folder: \(name). Run hushpen --download-model, or choose a complete Voz folder.")
            }
        }
        for name in ["mel.mlmodelc", "encoder.mlmodelc", "decoder.mlmodelc"] {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: directory.appendingPathComponent(name).path,
                                isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ToolError(.modelMissing, "The model folder is missing \(name). Please choose the complete Voz folder.")
            }
        }
        let model = try Voz(modelDirectory: directory)
        guard model.sampleRate == Recorder.targetSampleRate else {
            throw ToolError(.modelMissing, "This model uses an unsupported sample rate.")
        }
        return ModelConfig(directory: directory.path,
                           digest: try ModelDigest.compute(directory: directory),
                           revision: Attribution.modelRevision)
    }
}
