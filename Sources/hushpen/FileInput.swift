import AVFoundation
import Foundation

enum FileInput {
    static func samples(at url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw ToolError(.usage, "Cannot read audio file: \(url.path)")
        }

        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else {
            throw ToolError(.usage, "Audio file is empty: \(url.path)")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw ToolError(.failure, "Could not allocate the audio file buffer.")
        }
        try file.read(into: buffer)

        guard let channels = buffer.floatChannelData else {
            throw ToolError(.usage, "The audio file is not in Float-PCM format.")
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)

        var mono = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            mono.withUnsafeMutableBufferPointer { out in
                out.baseAddress!.update(from: channels[0], count: frameCount)
            }
        } else {
            let scale = 1 / Float(channelCount)
            for channel in 0..<channelCount {
                let source = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += source[frame] * scale
                }
            }
        }

        guard format.sampleRate != Recorder.targetSampleRate else { return mono }
        return try Recorder.resample(mono, from: format.sampleRate, to: Recorder.targetSampleRate)
    }
}
