import Foundation

struct ModelConfig: Codable, Sendable {
    var directory: String
    var digest: String
    var revision: String
}

enum Config {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func loadModel() throws -> ModelConfig {
        guard let data = try? Data(contentsOf: Paths.modelConfig) else {
            throw ToolError(.modelMissing, """
                No model installed. Download it (about 470 MB):

                  hushpen --download-model
                """)
        }
        do {
            return try decoder.decode(ModelConfig.self, from: data)
        } catch {
            throw ToolError(.modelMissing, "Cannot read model.json: \(error.localizedDescription)")
        }
    }

    static func saveModel(_ config: ModelConfig) throws {
        try Paths.ensureStateDirectory()
        try encoder.encode(config).write(to: Paths.modelConfig, options: .atomic)
    }

    static func verifiedModelDirectory() throws -> URL {
        try verify(try loadModel())
    }

    static func verify(_ config: ModelConfig) throws -> URL {
        let directory = URL(fileURLWithPath: config.directory)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ToolError(.modelMissing, "The registered model folder is missing: \(config.directory)")
        }
        let actual = try ModelDigest.compute(directory: directory)
        guard actual == config.digest else {
            throw ToolError(.modelDigestMismatch, """
                Model checksum mismatch — transcription cancelled.

                  Folder: \(config.directory)
                  expected:    \(config.digest)
                  actual:    \(actual)

                The model has changed since it was registered. If that was
                intentional, register the folder again:

                  hushpen --set-model \(config.directory)
                """)
        }
        return directory
    }
}
