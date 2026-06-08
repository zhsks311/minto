import Foundation
@preconcurrency import AVFoundation

enum STTAudioUtilities {
    static let sampleRate: Double = 16_000
    static let koreanLocale = Locale(identifier: "ko-KR")

    static func paddedSamples(_ pcmSamples: [Float]) -> [Float] {
        let minSamples = 8000
        return pcmSamples.count < minSamples
            ? pcmSamples + [Float](repeating: 0, count: minSamples - pcmSamples.count)
            : pcmSamples
    }

    static func silentResultIfNeeded(_ samples: [Float]) -> TranscriptionResult? {
        let dbLevel = Self.dbLevel(samples)
        guard dbLevel < -50 else { return nil }
        fputs("[STT] skip (energy=\(String(format: "%.1f", dbLevel))dB)\n", stderr)
        return transcriptionResult(text: "", sampleCount: samples.count)
    }

    static func transcriptionResult(text: String, sampleCount: Int) -> TranscriptionResult {
        let segment = Segment(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            duration: Double(sampleCount) / Self.sampleRate
        )
        return TranscriptionResult(segment: segment, isFinal: true)
    }

    static func dbLevel(_ samples: [Float]) -> Float {
        let rms = sqrt(samples.reduce(0.0 as Float) { $0 + $1 * $1 } / Float(samples.count))
        return 20 * log10(max(rms, 1e-7))
    }

    static func writeTemporaryAudioFile(samples: [Float]) throws -> URL {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw STTError.transcriptionFailed("임시 오디오 포맷을 만들 수 없습니다.")
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw STTError.transcriptionFailed("임시 오디오 버퍼를 만들 수 없습니다.")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?.pointee {
            samples.withUnsafeBufferPointer { pointer in
                if let baseAddress = pointer.baseAddress {
                    channel.update(from: baseAddress, count: samples.count)
                }
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-stt-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
