import Foundation

#if compiler(>=6.3) && canImport(Speech)
@preconcurrency import AVFoundation
import CoreMedia
@preconcurrency import Speech
#endif

@MainActor
final class SpeechAnalyzerStreamingEngine: StreamingTranscriptionEngine {
    let engineID: SpeechEngineID = .speechAnalyzer

    func startSession(
        configuration: StreamingTranscriptionConfiguration
    ) async throws -> any StreamingTranscriptionSession {
        #if compiler(>=6.3) && canImport(Speech)
        guard #available(macOS 26.0, *) else {
            throw STTError.engineUnavailable("SpeechAnalyzer streaming은 macOS 26 이상에서 사용할 수 있습니다.")
        }

        let availability = await SpeechAnalyzerSTTEngine.availability()
        guard availability.isSelectable else {
            throw STTError.engineUnavailable(availability.detailText ?? "SpeechAnalyzer streaming을 사용할 수 없습니다.")
        }

        return try await SpeechAnalyzerStreamingSession(configuration: configuration)
        #else
        throw STTError.engineUnavailable("현재 SDK에서 SpeechAnalyzer streaming API를 사용할 수 없습니다.")
        #endif
    }
}

#if compiler(>=6.3) && canImport(Speech)
@available(macOS 26.0, *)
@MainActor
private final class SpeechAnalyzerStreamingSession: StreamingTranscriptionSession {
    var onEvent: (@MainActor @Sendable (StreamingTranscriptionEvent) -> Void)?

    private let configuration: StreamingTranscriptionConfiguration
    private let audioFormat: AVAudioFormat
    private let analyzer: SpeechAnalyzer
    private var inputContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
    private var analyzerTask: Task<CMTime?, Error>?
    private var resultTask: Task<Void, Error>?
    private var acceptedSampleCount = 0
    private var revision = 0
    private var isFinished = false

    init(configuration: StreamingTranscriptionConfiguration) async throws {
        guard let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: configuration.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw STTError.transcriptionFailed("SpeechAnalyzer streaming 오디오 포맷을 만들 수 없습니다.")
        }

        self.configuration = configuration
        self.audioFormat = audioFormat

        let transcriber = SpeechTranscriber(
            locale: configuration.locale,
            preset: .progressiveTranscription
        )
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        self.analyzer = SpeechAnalyzer(modules: [transcriber], options: options)

        var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
        let inputStream = AsyncThrowingStream<AnalyzerInput, Error> { streamContinuation in
            continuation = streamContinuation
        }
        self.inputContinuation = continuation

        resultTask = Task { @MainActor [weak self] in
            for try await result in transcriber.results {
                self?.emit(result)
            }
        }
        analyzerTask = Task { [analyzer] in
            try await analyzer.analyzeSequence(inputStream)
        }
    }

    func accept(pcmSamples: [Float]) async throws {
        guard !isFinished else {
            throw STTError.transcriptionFailed("이미 종료된 SpeechAnalyzer streaming session입니다.")
        }
        guard !pcmSamples.isEmpty else { return }
        guard let inputContinuation else {
            throw STTError.transcriptionFailed("SpeechAnalyzer streaming 입력 스트림이 준비되지 않았습니다.")
        }

        let bufferStartTime = CMTime(
            value: CMTimeValue(acceptedSampleCount),
            timescale: CMTimeScale(configuration.sampleRate)
        )
        let input = try makeAnalyzerInput(samples: pcmSamples, bufferStartTime: bufferStartTime)
        acceptedSampleCount += pcmSamples.count
        inputContinuation.yield(input)
    }

    func finish() async throws {
        guard !isFinished else { return }
        isFinished = true
        inputContinuation?.finish()
        inputContinuation = nil

        do {
            let lastSampleTime = try await analyzerTask?.value
            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            try await resultTask?.value
        } catch {
            resultTask?.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func reset() async {
        isFinished = true
        inputContinuation?.finish()
        inputContinuation = nil
        analyzerTask?.cancel()
        resultTask?.cancel()
        await analyzer.cancelAndFinishNow()
        acceptedSampleCount = 0
        revision = 0
    }

    private func makeAnalyzerInput(samples: [Float], bufferStartTime: CMTime) throws -> AnalyzerInput {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw STTError.transcriptionFailed("SpeechAnalyzer streaming 오디오 버퍼를 만들 수 없습니다.")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?.pointee {
            samples.withUnsafeBufferPointer { pointer in
                if let baseAddress = pointer.baseAddress {
                    channel.update(from: baseAddress, count: samples.count)
                }
            }
        }
        return AnalyzerInput(buffer: buffer, bufferStartTime: bufferStartTime)
    }

    private func emit(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        revision += 1
        let duration = max(0, CMTimeGetSeconds(result.range.duration))
        let event = result.isFinal
            ? StreamingTranscriptionEvent.final(text: text, revision: revision, duration: duration)
            : StreamingTranscriptionEvent.partial(text: text, revision: revision, duration: duration)
        onEvent?(event)
    }
}
#endif
