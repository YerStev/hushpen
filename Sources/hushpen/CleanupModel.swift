import CryptoKit
import Foundation

// The cleanup model file: a pinned Gemma 4 E4B GGUF from huggingface.co,
// checked by SHA-256 when it is registered. Its size and modification date
// are recorded, and a changed file is hashed again before it is loaded.
struct CleanupModelConfig: Codable, Sendable {
    var path: String
    var sha256: String
    var size: Int64
    var modified: Date
}

enum CleanupModel {
    static let fileName = "gemma-4-E4B_q4_0-it.gguf"
    static let revision = "4b4a2c1d584be7264f87aac328a1bc739ce81b6c"
    static let sha256 = "676c35070db6dbe52f93e9c864ee0fba4eddea94b9c875d9cb10daff453fbaee"
    static let size: Int64 = 5_154_941_280
    static let url = URL(string:
        "https://huggingface.co/google/gemma-4-E4B-it-qat-q4_0-gguf/resolve/\(revision)/\(fileName)")!

    static var defaultLocation: URL {
        Paths.stateDirectory.appendingPathComponent("models/\(fileName)")
    }

    private static var configURL: URL { Paths.stateDirectory.appendingPathComponent("cleanup-model.json") }

    static func load() -> CleanupModelConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CleanupModelConfig.self, from: data)
    }

    // Checks a file you already have and registers it where it is.
    static func register(_ file: URL) throws -> CleanupModelConfig {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value,
              let modified = attributes?[.modificationDate] as? Date else {
            throw ToolError(.modelMissing, "Cannot read the cleanup model: \(file.path)")
        }
        guard size == Self.size, try digest(of: file) == sha256 else {
            throw ToolError(.modelDigestMismatch, """
                This is not the expected cleanup model (\(fileName), revision \(revision.prefix(8))).
                Download it with: hushpen --cleanup-model download
                """)
        }
        let config = CleanupModelConfig(path: file.path, sha256: sha256, size: size, modified: modified)
        try save(config)
        return config
    }

    // The registered file, hashed again if it changed since registration.
    static func verifiedPath() throws -> String {
        guard let config = load() else {
            throw ToolError(.modelMissing, "No cleanup model is registered. Run: hushpen --cleanup-model download")
        }
        let file = URL(fileURLWithPath: config.path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: config.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value,
              let modified = attributes?[.modificationDate] as? Date else {
            throw ToolError(.modelMissing, "The cleanup model file is missing: \(config.path)")
        }
        // Dates are stored to the second.
        if size != config.size || abs(modified.timeIntervalSince(config.modified)) >= 1 {
            _ = try register(file)
        }
        return config.path
    }

    static func download(progress: @escaping @Sendable (Double) -> Void) async throws -> CleanupModelConfig {
        try Paths.ensureStateDirectory()
        let destination = defaultLocation
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let delegate = DownloadProgress(total: size, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (temporary, response) = try await session.download(from: url, delegate: delegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ToolError(.modelMissing, "The cleanup model could not be downloaded (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        do {
            return try register(destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func save(_ config: CleanupModelConfig) throws {
        try Paths.ensureStateDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }

    private static func digest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let total: Int64
    private let progress: @Sendable (Double) -> Void

    init(total: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.total = total
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress(Double(totalBytesWritten) / Double(total))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
