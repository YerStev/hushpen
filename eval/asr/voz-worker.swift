import Foundation
import Voz
import DesertAnt

func emit(_ fields: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}

@main struct Bench {
    static func main() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let voz = try Voz(modelDirectory: URL(fileURLWithPath: CommandLine.arguments[1]))
        try emit(["ready": true, "load_ms": milliseconds(start.duration(to: clock.now))])
        while let line = readLine() {
            do {
                let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: String]
                let bytes = try Data(contentsOf: URL(fileURLWithPath: request["pcm"]!))
                let samples: [Float] = bytes.withUnsafeBytes { buffer in
                    stride(from: 0, to: bytes.count, by: 4).map {
                        Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: $0, as: UInt32.self)))
                    }
                }
                let start = clock.now
                let result = try await voz.transcribe(samples: samples)
                try emit(["text": result.text, "stt_ms": milliseconds(start.duration(to: clock.now))])
            } catch { try emit(["error": "transcription failed"]) }
        }
        await TelemetryDebug.shared.flushAndWait()
        withExtendedLifetime(voz) {}
    }
    static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}
