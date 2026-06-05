import Foundation
import CoreML
import Testing
@preconcurrency import WhisperKit

@Suite("Whisper Empty Clip Diagnostics (Manual Only)", .serialized)
struct WhisperEmptyClipDiagnosticsTests {

    private struct Clip {
        let label: String
        let start: Double
        let end: Double
    }

    private static let model = "openai_whisper-large-v3-v20240930_626MB"
    private static let sampleRate = 16_000
    private static let clips = [
        Clip(label: "good-009.7-025.6", start: 9.7, end: 25.6),
        Clip(label: "nonspeech-recess-120-180", start: 120, end: 180),   // 정회(-45dB), "감사합니다" 날조
        Clip(label: "nonspeech-crowd-180-187", start: 180, end: 187),    // 군중소음(-24.8dB) 날조
        Clip(label: "empty-096.8-104.4", start: 96.8, end: 104.4),
        Clip(label: "empty-366.3-385.2", start: 366.3, end: 385.2),
        Clip(label: "empty-399.7-422.7", start: 399.7, end: 422.7),
        Clip(label: "empty-912.1-932.8", start: 912.1, end: 932.8),
        Clip(label: "empty-330.2-333.2", start: 330.2, end: 333.2),
        Clip(label: "empty-524.7-527.7", start: 524.7, end: 527.7),
        Clip(label: "empty-581.4-584.4", start: 581.4, end: 584.4),
    ]

    private static let rawDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/meeting/raw")
    }()

    @Test("raw WhisperKit output for measured empty clips")
    func rawWhisperKitOutput() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STT_TESTS"] == "1" else { return }

        let variant = ProcessInfo.processInfo.environment["WHISPER_DIAG_VARIANT"] ?? "baseline"
        let audioURL = Self.rawDir.appendingPathComponent("haengan_20260526_full.wav")
        let samples = try Self.readWAVSamples(from: audioURL)

        let folder: URL
        if let modelFolder = ProcessInfo.processInfo.environment["WHISPER_MODEL_FOLDER"] {
            folder = URL(fileURLWithPath: modelFolder)
        } else {
            folder = try await WhisperKit.download(variant: Self.model)
        }
        let pipe = try await WhisperKit(WhisperKitConfig(
            model: Self.model,
            modelFolder: folder.path(percentEncoded: false),
            computeOptions: ModelComputeOptions(
                melCompute: .cpuOnly,
                audioEncoderCompute: .cpuOnly,
                textDecoderCompute: .cpuOnly,
                prefillCompute: .cpuOnly
            ),
            verbose: true
        ))

        print("\n=== Whisper empty clip diagnostics variant=\(variant) ===")
        for clip in Self.clips {
            let startSample = max(0, Int(clip.start * Double(Self.sampleRate)))
            let endSample = min(samples.count, Int(clip.end * Double(Self.sampleRate)))
            guard endSample > startSample else { continue }

            let audio = Array(samples[startSample..<endSample])
            let rms = sqrt(audio.reduce(0.0 as Float) { $0 + $1 * $1 } / Float(audio.count))
            let db = 20 * log10(max(rms, 1e-7))
            nonisolated(unsafe) var progressEvents: [TranscriptionProgress] = []

            let results = try await pipe.transcribe(
                audioArray: audio,
                decodeOptions: Self.options(for: variant),
                callback: { progress in
                    progressEvents.append(progress)
                    return nil
                },
                segmentCallback: { segments in
                    print("[DIAG][segmentCallback] \(clip.label) count=\(segments.count)")
                    for segment in segments {
                        Self.printSegment(segment)
                    }
                }
            )

            let resultText = results.map(\.text).joined(separator: " ")
            let segments = results.flatMap(\.segments)
            print(String(format: "[DIAG][clip] %@ %.1f-%.1fs dur=%.1fs rms=%.1fdB results=%d segments=%d progress=%d text=%@",
                         clip.label, clip.start, clip.end, clip.end - clip.start, db, results.count, segments.count, progressEvents.count, resultText))
            if let last = progressEvents.last {
                print(String(format: "[DIAG][progress-last] %@ temp=%@ avg=%@ comp=%@ tokens=%d text=%@",
                             clip.label,
                             Self.format(last.temperature),
                             Self.format(last.avgLogprob),
                             Self.format(last.compressionRatio),
                             last.tokens.count,
                             last.text))
            }
            for segment in segments {
                Self.printSegment(segment)
            }
        }
    }

    private static func options(for variant: String) -> DecodingOptions {
        switch variant {
        case "noSpeechNil":
            DecodingOptions(language: "ko", wordTimestamps: false, suppressBlank: true, noSpeechThreshold: nil)
        case "noSpeech090":
            DecodingOptions(language: "ko", wordTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.90)
        case "withoutTimestamps":
            DecodingOptions(language: "ko", withoutTimestamps: true, wordTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.80)
        case "suppressBlankFalse":
            DecodingOptions(language: "ko", wordTimestamps: false, suppressBlank: false, noSpeechThreshold: 0.80)
        case "prefillFalse":
            DecodingOptions(language: "ko", usePrefillPrompt: false, wordTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.80)
        case "tempFallback0":
            DecodingOptions(language: "ko", temperatureFallbackCount: 0, wordTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.80)
        case "temp020":
            DecodingOptions(language: "ko", temperature: 0.2, wordTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.80)
        case "logProbNil":
            DecodingOptions(language: "ko", wordTimestamps: false, suppressBlank: true, logProbThreshold: nil, noSpeechThreshold: 0.80)
        case "compressionNil":
            DecodingOptions(language: "ko", wordTimestamps: false, suppressBlank: true, compressionRatioThreshold: nil, noSpeechThreshold: 0.80)
        case "windowClip0":
            DecodingOptions(language: "ko", wordTimestamps: false, windowClipTime: 0.0, suppressBlank: true, noSpeechThreshold: 0.80)
        default:
            DecodingOptions(language: "ko", wordTimestamps: false, suppressBlank: true, noSpeechThreshold: 0.80)
        }
    }

    private static func printSegment(_ segment: TranscriptionSegment) {
        print(String(format: "[DIAG][segment] id=%d seek=%d %.2f-%.2f temp=%.2f noSpeech=%.3f avg=%.3f comp=%.3f tokens=%d text=%@",
                     segment.id,
                     segment.seek,
                     segment.start,
                     segment.end,
                     segment.temperature,
                     segment.noSpeechProb,
                     segment.avgLogprob,
                     segment.compressionRatio,
                     segment.tokens.count,
                     segment.text))
    }

    private static func format(_ value: Float?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.3f", value)
    }

    private static func readWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE"
        else {
            throw NSError(domain: "WhisperDiag", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "WAV RIFF header not found: \(url.path)"
            ])
        }

        var audioFormat: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var dataRange: Range<Int>?

        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let chunkSize = Int(Self.readUInt32LE(data, offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, data.count)

            if chunkID == "fmt ", chunkStart + 16 <= chunkEnd {
                audioFormat = Self.readUInt16LE(data, chunkStart)
                channelCount = Self.readUInt16LE(data, chunkStart + 2)
                sampleRate = Self.readUInt32LE(data, chunkStart + 4)
                bitsPerSample = Self.readUInt16LE(data, chunkStart + 14)
            } else if chunkID == "data" {
                dataRange = chunkStart..<chunkEnd
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard channelCount == 1, sampleRate == 16_000 else {
            throw NSError(domain: "WhisperDiag", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Expected 16kHz mono WAV: \(url.path)"
            ])
        }

        guard let audioFormat, let bitsPerSample, let dataRange else {
            throw NSError(domain: "WhisperDiag", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Missing WAV fmt/data chunk: \(url.path)"
            ])
        }

        switch (audioFormat, bitsPerSample) {
        case (1, 16):
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 1, by: 2).map { index in
                let sample = Int16(bitPattern: Self.readUInt16LE(data, index))
                return max(-1.0, Float(sample) / 32768.0)
            }
        case (3, 32):
            return stride(from: dataRange.lowerBound, to: dataRange.upperBound - 3, by: 4).map { index in
                Float(bitPattern: Self.readUInt32LE(data, index))
            }
        default:
            throw NSError(domain: "WhisperDiag", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported WAV format=\(audioFormat), bits=\(bitsPerSample)"
            ])
        }
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
