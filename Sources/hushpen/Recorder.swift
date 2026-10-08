import AVFoundation
import Foundation

final class Recorder: @unchecked Sendable {
    static let targetSampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var monoSamples: [Float] = []
    private var hardwareSampleRate: Double = 0
    private var running = false
    private var smoothedLevel: Float = 0

    static func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw Self.microphoneDenied }
        case .denied, .restricted:
            throw Self.microphoneDenied
        @unknown default:
            throw Self.microphoneDenied
        }
    }

    private static var microphoneDenied: ToolError {
        ToolError(.microphone, """
            Microphone access is not allowed.

            macOS assigns permission to the responsible launcher.
            With the login service, allow hushpen. When launched through a
            terminal or another app, allow that application:

              System Settings → Privacy & Security → Microphone
            """)
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ToolError(.microphone, "No usable audio input device was found.")
        }

        lock.lock()
        hardwareSampleRate = format.sampleRate
        monoSamples.removeAll(keepingCapacity: false)
        smoothedLevel = 0
        monoSamples.reserveCapacity(Int(format.sampleRate * 60))
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw ToolError(.microphone, "Could not start the audio engine: \(error.localizedDescription)")
        }
        running = true
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)

        var mixed = [Float](repeating: 0, count: frames)
        if channelCount == 1 {
            mixed.withUnsafeMutableBufferPointer { out in
                out.baseAddress!.update(from: channels[0], count: frames)
            }
        } else {
            let scale = 1 / Float(channelCount)
            for channel in 0..<channelCount {
                let source = channels[channel]
                for frame in 0..<frames {
                    mixed[frame] += source[frame] * scale
                }
            }
        }

        var sumOfSquares: Float = 0
        for value in mixed { sumOfSquares += value * value }
        let rms = (sumOfSquares / Float(frames)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        let normalized = max(0, min(1, (decibels + 50) / 45))

        lock.lock()
        monoSamples.append(contentsOf: mixed)
        smoothedLevel = normalized > smoothedLevel
            ? normalized
            : smoothedLevel * 0.82 + normalized * 0.18
        lock.unlock()
    }

    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return running ? smoothedLevel : 0
    }

    func stopAndTakeSamples() throws -> [Float] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }

        lock.lock()
        let raw = monoSamples
        let rate = hardwareSampleRate
        monoSamples.removeAll(keepingCapacity: false)
        lock.unlock()

        guard !raw.isEmpty else { return [] }
        guard rate != Self.targetSampleRate else { return raw }
        return try Self.resample(raw, from: rate, to: Self.targetSampleRate)
    }

    // A 16 kHz copy of the audio from a captured-sample position onward, for
    // the live preview. Recording continues undisturbed.
    func snapshot(from start: Int) throws -> (samples: [Float], total: Int, rate: Double) {
        lock.lock()
        let rate = hardwareSampleRate
        let total = monoSamples.count
        let raw = start < total ? Array(monoSamples[max(0, start)...]) : []
        lock.unlock()

        guard !raw.isEmpty, rate > 0 else { return ([], total, rate) }
        let samples = rate == Self.targetSampleRate ? raw : try Self.resample(raw, from: rate, to: Self.targetSampleRate)
        return (samples, total, rate)
    }

    func cancel() {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
        }
        lock.lock()
        monoSamples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    var recordedSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        guard hardwareSampleRate > 0 else { return 0 }
        return Double(monoSamples.count) / hardwareSampleRate
    }

    static func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) throws -> [Float] {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                              sampleRate: inputRate, channels: 1, interleaved: false),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: outputRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw ToolError(.failure, "Could not create the resampler (\(inputRate) → \(outputRate) Hz).")
        }

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                 frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw ToolError(.failure, "Could not allocate the input buffer.")
        }
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            inputBuffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }

        let ratio = outputRate / inputRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 4096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw ToolError(.failure, "Could not allocate the output buffer.")
        }

        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if delivered {
                outStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw ToolError(.failure, "Resampling failed: \(conversionError.localizedDescription)")
        }
        guard status != .error else {
            throw ToolError(.failure, "Resampling failed.")
        }

        let produced = Int(outputBuffer.frameLength)
        guard produced > 0, let data = outputBuffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: produced))
    }
}
