import Foundation
import CoreML
import Testing
@testable import MintoCore
@preconcurrency import WhisperKit

@Suite("Whisper Empty Clip Diagnostics (Manual Only)", .serialized)
struct WhisperEmptyClipDiagnosticsTests {

    private struct Clip {
        let label: String
        let audioFile: String
        let start: Double
        let end: Double
        let referenceLength: Int?
        let source: String
    }

    private static let model = "openai_whisper-large-v3-v20240930_turbo"
    private static let sampleRate = 16_000
    private static let sileroFullDurationClips = [
        Clip(
            label: "silero-empty-jaegyeong-20260430-063",
            audioFile: "재정경제기획위원회_20260430_full.wav",
            start: 703.368,
            end: 717.176,
            referenceLength: 125,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
        Clip(
            label: "silero-empty-jaegyeong-20260429-097",
            audioFile: "재정경제기획위원회_20260429_full.wav",
            start: 1192.072,
            end: 1205.880,
            referenceLength: 124,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
        Clip(
            label: "silero-empty-plenary-20260423-411",
            audioFile: "본회의_20260423_full.wav",
            start: 6891.144,
            end: 6904.952,
            referenceLength: 104,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
        Clip(
            label: "silero-empty-haengan-20260526-154",
            audioFile: "haengan_20260526_full.wav",
            start: 1760.136,
            end: 1773.944,
            referenceLength: 100,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
        Clip(
            label: "silero-empty-diplomacy-20260520-299",
            audioFile: "외교통일위원회_20260520_full.wav",
            start: 3251.080,
            end: 3264.888,
            referenceLength: 92,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
        Clip(
            label: "silero-empty-plenary-20260428-041",
            audioFile: "본회의_20260428_full.wav",
            start: 501.896,
            end: 515.7039375,
            referenceLength: 82,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
        Clip(
            label: "silero-empty-plenary-20260508-037",
            audioFile: "본회의_20260508_full.wav",
            start: 442.504,
            end: 451.448,
            referenceLength: 52,
            source: "minto2-vad-full-silero-060-gap11-all7"
        ),
    ]
    private static let legacyHaenganClips = [
        Clip(label: "good-009.7-025.6", audioFile: "haengan_20260526_full.wav", start: 9.7, end: 25.6, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "nonspeech-recess-120-180", audioFile: "haengan_20260526_full.wav", start: 120, end: 180, referenceLength: nil, source: "legacy-haengan"),   // 정회(-45dB), "감사합니다" 날조
        Clip(label: "nonspeech-crowd-180-187", audioFile: "haengan_20260526_full.wav", start: 180, end: 187, referenceLength: nil, source: "legacy-haengan"),    // 군중소음(-24.8dB) 날조
        Clip(label: "empty-096.8-104.4", audioFile: "haengan_20260526_full.wav", start: 96.8, end: 104.4, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "empty-366.3-385.2", audioFile: "haengan_20260526_full.wav", start: 366.3, end: 385.2, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "empty-399.7-422.7", audioFile: "haengan_20260526_full.wav", start: 399.7, end: 422.7, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "empty-912.1-932.8", audioFile: "haengan_20260526_full.wav", start: 912.1, end: 932.8, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "empty-330.2-333.2", audioFile: "haengan_20260526_full.wav", start: 330.2, end: 333.2, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "empty-524.7-527.7", audioFile: "haengan_20260526_full.wav", start: 524.7, end: 527.7, referenceLength: nil, source: "legacy-haengan"),
        Clip(label: "empty-581.4-584.4", audioFile: "haengan_20260526_full.wav", start: 581.4, end: 584.4, referenceLength: nil, source: "legacy-haengan"),
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
        let probeSet = ProcessInfo.processInfo.environment["WHISPER_DIAG_PROBE_SET"] ?? "sileroFullDuration"
        let diagnosticPath = ProcessInfo.processInfo.environment["WHISPER_DIAG_PATH"] ?? "direct"
        let padSeconds = Self.padSeconds()
        let clips = Self.limitedClips(Self.filteredClips(Self.clips(for: probeSet)))
        guard !clips.isEmpty else {
            print("[DIAG] no clips selected for probeSet=\(probeSet)")
            return
        }
        let runDirect = diagnosticPath != "service"
        let runService = diagnosticPath == "service" || diagnosticPath == "both"
        let pipe = runDirect ? try await Self.loadDirectWhisperKit() : nil
        let service = runService ? try await Self.loadSTTService() : nil

        print("\n=== Whisper empty clip diagnostics variant=\(variant) probeSet=\(probeSet) path=\(diagnosticPath) clips=\(clips.count) pad=\(padSeconds)s ===")
        for audioFile in Self.audioFiles(in: clips) {
            let audioURL = Self.rawDir.appendingPathComponent(audioFile)
            for clip in clips where clip.audioFile == audioFile {
                let effectiveStart = max(0, clip.start - padSeconds)
                let effectiveEnd = clip.end + padSeconds
                let audio = try Self.readWAVClipSamples(from: audioURL, start: effectiveStart, end: effectiveEnd)
                guard !audio.isEmpty else { continue }

                let rms = sqrt(audio.reduce(0.0 as Float) { $0 + $1 * $1 } / Float(audio.count))
                let db = 20 * log10(max(rms, 1e-7))
                nonisolated(unsafe) var progressEvents: [TranscriptionProgress] = []

                if let pipe {
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
                    print(String(format: "[DIAG][direct] %@ file=%@ source=%@ pad=%.3f refLen=%@ %.3f-%.3fs dur=%.3fs rms=%.1fdB results=%d segments=%d progress=%d text=%@",
                                 clip.label,
                                 clip.audioFile,
                                 clip.source,
                                 padSeconds,
                                 Self.format(clip.referenceLength),
                                 effectiveStart,
                                 effectiveEnd,
                                 Double(audio.count) / Double(Self.sampleRate),
                                 db,
                                 results.count,
                                 segments.count,
                                 progressEvents.count,
                                 resultText))
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

                if let service {
                    let result = try await service.transcribe(pcmSamples: audio)
                    let text = result.segment.text
                    print(String(format: "[DIAG][service] %@ file=%@ source=%@ pad=%.3f refLen=%@ %.3f-%.3fs dur=%.3fs rms=%.1fdB empty=%@ text=%@",
                                 clip.label,
                                 clip.audioFile,
                                 clip.source,
                                 padSeconds,
                                 Self.format(clip.referenceLength),
                                 effectiveStart,
                                 effectiveEnd,
                                 Double(audio.count) / Double(Self.sampleRate),
                                 db,
                                 "\(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)",
                                 text))
                }
            }
        }
    }

    private static func loadDirectWhisperKit() async throws -> WhisperKit {
        let folder: URL
        if let modelFolder = ProcessInfo.processInfo.environment["WHISPER_MODEL_FOLDER"] {
            folder = URL(fileURLWithPath: modelFolder)
        } else {
            folder = try await WhisperKit.download(variant: Self.model)
        }
        return try await WhisperKit(WhisperKitConfig(
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
    }

    @MainActor
    private static func loadSTTService() async throws -> STTService {
        let service = STTService()
        await service.loadModel(variant: Self.model)
        guard case .loaded = service.modelState else {
            throw NSError(domain: "WhisperDiag", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "STTService model load failed: \(service.modelState)"
            ])
        }
        return service
    }

    private static func clips(for probeSet: String) -> [Clip] {
        switch probeSet {
        case "legacy", "legacyHaengan":
            Self.legacyHaenganClips
        case "sileroFullDuration", "fullSilero", "silero":
            Self.sileroFullDurationClips
        default:
            Self.sileroFullDurationClips
        }
    }

    private static func limitedClips(_ clips: [Clip]) -> [Clip] {
        guard let rawValue = ProcessInfo.processInfo.environment["WHISPER_DIAG_MAX_CLIPS"],
              let maxClips = Int(rawValue),
              maxClips >= 0 else {
            return clips
        }
        return Array(clips.prefix(maxClips))
    }

    private static func filteredClips(_ clips: [Clip]) -> [Clip] {
        guard let rawValue = ProcessInfo.processInfo.environment["WHISPER_DIAG_LABELS"],
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return clips
        }
        let labels = Set(rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return clips.filter { labels.contains($0.label) }
    }

    private static func audioFiles(in clips: [Clip]) -> [String] {
        clips.reduce(into: []) { files, clip in
            if !files.contains(clip.audioFile) {
                files.append(clip.audioFile)
            }
        }
    }

    private static func padSeconds() -> Double {
        guard let rawValue = ProcessInfo.processInfo.environment["WHISPER_DIAG_PAD_SECONDS"],
              let value = Double(rawValue),
              value > 0 else {
            return 0
        }
        return value
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

    private static func format(_ value: Int?) -> String {
        guard let value else { return "nil" }
        return "\(value)"
    }

    private static func readWAVClipSamples(from url: URL, start: Double, end: Double) throws -> [Float] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
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
            let clipRange = Self.clipByteRange(
                dataRange: dataRange,
                bytesPerSample: 2,
                start: start,
                end: end
            )
            return stride(from: clipRange.lowerBound, to: clipRange.upperBound - 1, by: 2).map { index in
                let sample = Int16(bitPattern: Self.readUInt16LE(data, index))
                return max(-1.0, Float(sample) / 32768.0)
            }
        case (3, 32):
            let clipRange = Self.clipByteRange(
                dataRange: dataRange,
                bytesPerSample: 4,
                start: start,
                end: end
            )
            return stride(from: clipRange.lowerBound, to: clipRange.upperBound - 3, by: 4).map { index in
                Float(bitPattern: Self.readUInt32LE(data, index))
            }
        default:
            throw NSError(domain: "WhisperDiag", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported WAV format=\(audioFormat), bits=\(bitsPerSample)"
            ])
        }
    }

    private static func clipByteRange(
        dataRange: Range<Int>,
        bytesPerSample: Int,
        start: Double,
        end: Double
    ) -> Range<Int> {
        let startFrame = max(0, Int(start * Double(Self.sampleRate)))
        let endFrame = max(startFrame, Int(end * Double(Self.sampleRate)))
        let lowerBound = min(dataRange.upperBound, dataRange.lowerBound + startFrame * bytesPerSample)
        let upperBound = min(dataRange.upperBound, dataRange.lowerBound + endFrame * bytesPerSample)
        return lowerBound..<upperBound
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
