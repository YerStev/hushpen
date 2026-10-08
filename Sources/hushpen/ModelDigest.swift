import CryptoKit
import Foundation

enum ModelDigest {
    private static let ignoredNames: Set<String> = [".DS_Store"]

    static func compute(directory: URL) throws -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ToolError(.modelMissing, "Cannot read model folder: \(directory.path)")
        }

        var relativePaths: [String] = []
        let prefix = directory.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if ignoredNames.contains(url.lastPathComponent) { continue }
            var path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            path.removeFirst(prefix.count)
            relativePaths.append(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        }

        guard !relativePaths.isEmpty else {
            throw ToolError(.modelMissing, "The model folder is empty: \(directory.path)")
        }

        var hasher = SHA256()
        for relative in relativePaths.sorted() {
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            let handle = try FileHandle(forReadingFrom: directory.appendingPathComponent(relative))
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
