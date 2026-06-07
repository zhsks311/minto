import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech
@preconcurrency import WhisperKit

/// WhisperKit 기반 STT 서비스.
/// @MainActor 격리: WhisperKit 자체가 내부 비동기를 처리하므로 메인 스레드를 블록하지 않음.
@MainActor
public final class STTService {

    // MARK: - Public state

    public private(set) var modelState: ModelState = .unloaded
    public private(set) var modelVariant: String = "openai_whisper-large-v3-v20240930_turbo"
    public private(set) var speechEngineID: SpeechEngineID = .defaultEngine

    // ViewModel이 modelState 변화를 @Published 없이 수신하는 콜백
    var onModelStateChange: ((ModelState) -> Void)?

    // MARK: - Private

    nonisolated(unsafe) private var pipe: WhisperKit?
    private static let sampleRate: Double = 16_000
    private static let koreanLocale = Locale(identifier: "ko-KR")

    public init() {}

    public static func engineAvailability(for engineID: SpeechEngineID) async -> SpeechEngineAvailability {
        if engineID.whisperVariant != nil {
            return .available
        }

        switch engineID {
        case .speechAnalyzer:
            return await speechAnalyzerAvailability()
        case .sfSpeechOnDevice:
            return sfSpeechOnDeviceAvailability()
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return .available
        }
    }

    public static func requestSFSpeechAuthorization() async -> SpeechEngineAvailability {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in
                    continuation.resume(returning: sfSpeechOnDeviceAvailability())
                }
            }
        }
    }

    private static func speechAnalyzerAvailability() async -> SpeechEngineAvailability {
        guard #available(macOS 26.0, *) else {
            return .unavailable("macOS 26 이상에서 사용할 수 있습니다.")
        }

        guard SpeechTranscriber.isAvailable else {
            return .unavailable("현재 기기에서 SpeechAnalyzer를 사용할 수 없습니다.")
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: koreanLocale) else {
            return .unavailable("한국어 SpeechAnalyzer 지원을 찾을 수 없습니다.")
        }

        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedLocales.contains(where: { $0.identifier == locale.identifier }) else {
            return .unavailable("한국어 SpeechAnalyzer asset이 설치되어 있지 않습니다.")
        }

        return .available
    }

    private static func sfSpeechOnDeviceAvailability() -> SpeechEngineAvailability {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .requiresPermission("Apple 음성 인식 권한을 허용해야 사용할 수 있습니다.")
        case .denied:
            return .unavailable("시스템 설정에서 Apple 음성 인식 권한이 거부되어 있습니다.")
        case .restricted:
            return .unavailable("이 기기 정책상 Apple 음성 인식을 사용할 수 없습니다.")
        case .authorized:
            break
        @unknown default:
            return .unavailable("Apple 음성 인식 권한 상태를 확인할 수 없습니다.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: koreanLocale) else {
            return .unavailable("한국어 SFSpeechRecognizer를 만들 수 없습니다.")
        }

        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable("한국어 온디바이스 음성 인식 asset이 없습니다.")
        }

        guard recognizer.isAvailable else {
            return .unavailable("현재 Apple 음성 인식 서비스를 사용할 수 없습니다.")
        }

        return .available
    }

    // MARK: - Model loading

    public var supportsPreviewTranscription: Bool {
        speechEngineID.supportsPreviewTranscription
    }

    public func loadEngine(_ engineID: SpeechEngineID = .defaultEngine) async {
        let availability = await Self.engineAvailability(for: engineID)
        guard availability.isSelectable else {
            pipe = nil
            speechEngineID = engineID
            updateState(.failed(availability.detailText ?? "\(engineID.title)을 사용할 수 없습니다."))
            return
        }

        if let variant = engineID.whisperVariant {
            speechEngineID = engineID
            await loadWhisperModel(variant: variant)
            return
        }

        pipe = nil
        speechEngineID = engineID
        modelVariant = engineID.rawValue
        updateState(.loaded)
        fputs("[STT] Apple speech engine ready: \(engineID.rawValue)\n", stderr)
    }

    public func loadModel(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        speechEngineID = SpeechEngineID.fromWhisperVariant(variant)
        await loadWhisperModel(variant: variant)
    }

    private func loadWhisperModel(variant: String) async {
        modelVariant = variant
        fputs("[STT] downloading \(variant)...\n", stderr)
        updateState(.downloading(0))

        do {
            let folder = try await WhisperKit.download(
                variant: variant,
                progressCallback: { @Sendable [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateState(.downloading(progress.fractionCompleted))
                    }
                }
            )
            fputs("[STT] initializing WhisperKit...\n", stderr)
            updateState(.loading)
            pipe = try await WhisperKit(WhisperKitConfig(
                model: variant,
                modelFolder: folder.path(percentEncoded: false)
            ))
            updateState(.loaded)
            fputs("[STT] WhisperKit ready: \(variant)\n", stderr)
        } catch {
            updateState(.failed(error.localizedDescription))
            fputs("[STT] load error: \(error)\n", stderr)
        }
    }

    /// User-triggered recovery path for corrupted Hugging Face/WhisperKit cache metadata.
    /// It removes only the selected model's cached folder and per-file download metadata,
    /// then runs the normal download/load flow again.
    public func recoverModelCacheAndReload(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        modelVariant = variant
        pipe = nil
        updateState(.loading)

        do {
            let removed = try await Self.removeCachedModelFiles(for: variant)
            if removed.isEmpty {
                fputs("[STT] recovery: no cached model files found for \(variant)\n", stderr)
            } else {
                fputs("[STT] recovery: removed \(removed.count) cached path(s) for \(variant)\n", stderr)
            }
            await loadModel(variant: variant)
        } catch {
            let message = "모델 캐시 정리에 실패했습니다: \(error.localizedDescription)"
            updateState(.failed(message))
            fputs("[STT] recovery error: \(error)\n", stderr)
        }
    }

    nonisolated static func modelCacheCandidateURLs(for variant: String, repoRoot: URL? = nil) -> [URL] {
        let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let root: URL
        if let repoRoot {
            root = repoRoot
        } else {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return []
            }
            root = documents
                .appendingPathComponent("huggingface", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        }

        let downloadRoot = root
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)

        let candidates = matchingChildren(in: root, variant: trimmed)
            + matchingChildren(in: downloadRoot, variant: trimmed)

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    nonisolated private static func removeCachedModelFiles(for variant: String) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let candidates = modelCacheCandidateURLs(for: variant)
            let fileManager = FileManager.default
            var removed: [String] = []

            for url in candidates {
                guard fileManager.fileExists(atPath: url.path) else { continue }
                try fileManager.removeItem(at: url)
                removed.append(url.path)
            }

            return removed
        }.value
    }

    nonisolated private static func matchingChildren(in root: URL, variant: String) -> [URL] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let name = url.lastPathComponent
            return name == variant || name.contains(variant)
        }
    }

    // MARK: - Transcription

    public func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        switch speechEngineID {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return try await transcribeWithWhisper(pcmSamples: pcmSamples)
        case .speechAnalyzer:
            return try await transcribeWithSpeechAnalyzer(pcmSamples: pcmSamples)
        case .sfSpeechOnDevice:
            return try await transcribeWithSFSpeechOnDevice(pcmSamples: pcmSamples)
        }
    }

    private func transcribeWithWhisper(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard let pipe else { throw STTError.modelNotLoaded }

        // whisper 최소 입력 ~0.5s @16kHz
        let minSamples = 8000
        let samples = pcmSamples.count < minSamples
            ? pcmSamples + [Float](repeating: 0, count: minSamples - pcmSamples.count)
            : pcmSamples

        // 에너지 사전 필터: RMS < -30dB 이면 배경 소음으로 간주해 Whisper 호출 생략
        let rms = sqrt(samples.reduce(0.0 as Float) { $0 + $1 * $1 } / Float(samples.count))
        let dbLevel = 20 * log10(max(rms, 1e-7))
        if dbLevel < -50 {
            fputs("[STT] skip (energy=\(String(format: "%.1f", dbLevel))dB)\n", stderr)
            let seg = Segment(text: "", timestamp: Date(), duration: Double(samples.count) / 16000.0)
            return TranscriptionResult(segment: seg, isFinal: true)
        }

        let options = DecodingOptions(
            language: "ko",
            wordTimestamps: false,
            // 윈도우 첫 토큰 위치에서 공백·EOT를 억제(OpenAI Whisper 기본값과 일치).
            // 발화가 있는 청크가 빈 출력으로 끝나는 경우를 줄인다. 첫 위치에만 적용되므로
            // 부작용은 최대 토큰 1개이며, 순수 무음 청크는 위 에너지 사전필터(-50dB)가
            // 이미 걸러 할루시네이션 위험이 낮다.
            suppressBlank: true,
            // supressTokens(비발화 토큰 억제)·windowClipTime은 기본값을 의도적으로 유지한다.
            // WhisperKit가 nonSpeechTokens 기본 구현을 하지 않아(TODO) 올바른 토큰 ID를 직접
            // 넣는 것은 모델/토크나이저 의존적이라 위험 > 이득. windowClipTime은 청크 내 seek
            // 동작이라 VAD로 청크를 직접 끊는 이 파이프라인엔 영향이 적다.
            noSpeechThreshold: 0.80   // g2 350샘플 실험: 0.80 최적 (CER 5.7%)
        )

        let wkResults = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        var fullText = ""
        for result in wkResults {
            for seg in result.segments {
                // noSpeechProb 사후필터는 두지 않는다(의도). WhisperKit가 디코딩 시
                // noSpeechThreshold(0.80)로 무음 세그먼트를 이미 skip하며, avgLogProb가
                // logProbThreshold(-1.0)보다 높으면 "확신"이 무음 판정을 덮어쓴다
                // (SegmentSeeker). 여기서 0.6으로 재검하면 그 튜닝을 무효화하고, WhisperKit가
                // 살린 확신 있는 발화(noSpeechProb 0.6~0.8 구간)까지 버린다.
                //
                // 반면 avgLogprob/compressionRatio는 의도적 할루시네이션 가드로 유지한다.
                // WhisperKit는 이 둘을 "버리는" 게 아니라 temperature fallback 트리거로만 쓰고
                // (DecodingFallback), 5회 fallback 후에도 저품질이면 best-effort로 반환한다.
                // 그 반복/환각 잔재를 앱이 최종 차단한다. g2 350샘플에서 0회 발동(깨끗한 발화는
                // 안 버림) — 단 실제 발화를 드물게 버릴 잔여 위험은 있다.
                guard seg.avgLogprob > -1.0 else {
                    fputs("[STT] skip: avgLogprob=\(String(format:"%.2f", seg.avgLogprob))\n", stderr)
                    continue
                }
                guard seg.compressionRatio < 2.4 else {
                    fputs("[STT] skip: compressionRatio=\(String(format:"%.2f", seg.compressionRatio))\n", stderr)
                    continue
                }
                let text = Self.stripWhisperTokens(seg.text).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                // [MUSIC], [BLANK_AUDIO], (웃음) 등 Whisper 메타 태그
                guard !text.hasPrefix("["), !text.hasPrefix("(") else { continue }
                guard !Self.isKnownHallucination(text) else { continue }
                fullText += text
            }
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 저에너지(-40dB 미만) + 짧은 출력(≤10자)은 비발화 phantom("감사합니다" 등) 가능성이 높아
        // 버린다. 진단: 정회 웅성거림(-45dB)이 noSpeechProb=0·avgLogprob≈0의 "고신뢰" phantom으로
        // 새는데, 메트릭 가드(noSpeech/avgLogprob/compressionRatio)로는 못 잡고 이 에너지+길이
        // 휴리스틱만 잡는다. 실제 발화는 대개 -40dB 이상이라 손실이 적다(아주 조용한 짧은 발화는
        // 드물게 누락될 수 있으나, 회의록에 "안 한 말"이 적히는 것보다 낫다). 시끄러운 구간의 잡음
        // 섞인 실제 발화는 -40dB 이상이라 이 필터에 걸리지 않는다.
        if dbLevel < -40, !trimmed.isEmpty, trimmed.count <= 10 {
            fputs("[STT] skip (low-energy short phantom \(String(format:"%.1f", dbLevel))dB '\(trimmed)')\n", stderr)
            let seg = Segment(text: "", timestamp: Date(), duration: Double(samples.count) / 16000.0)
            return TranscriptionResult(segment: seg, isFinal: true)
        }

        let segment = Segment(
            text: trimmed,
            timestamp: Date(),
            duration: Double(samples.count) / 16000.0
        )
        return TranscriptionResult(segment: segment, isFinal: true)
    }

    private func transcribeWithSpeechAnalyzer(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard #available(macOS 26.0, *) else {
            throw STTError.engineUnavailable("SpeechAnalyzer는 macOS 26 이상에서 사용할 수 있습니다.")
        }

        let availability = await Self.engineAvailability(for: .speechAnalyzer)
        guard availability.isSelectable else {
            throw STTError.engineUnavailable(availability.detailText ?? "SpeechAnalyzer를 사용할 수 없습니다.")
        }

        let samples = paddedSamples(pcmSamples)
        if let silent = silentResultIfNeeded(samples) {
            return silent
        }

        let url = try writeTemporaryAudioFile(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }

        let audioFile = try AVAudioFile(forReading: url)
        let transcriber = SpeechTranscriber(locale: Self.koreanLocale, preset: .transcription)
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            options: options,
            finishAfterFile: true
        )

        let resultTask = Task<String, Error> {
            var fullText = ""
            var latestText = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if result.isFinal {
                    fullText += text
                } else {
                    latestText = text
                }
            }
            return fullText.isEmpty ? latestText : fullText
        }

        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        let text = try await resultTask.value
        return transcriptionResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            sampleCount: samples.count
        )
    }

    private func transcribeWithSFSpeechOnDevice(pcmSamples: [Float]) async throws -> TranscriptionResult {
        let availability = Self.sfSpeechOnDeviceAvailability()
        guard availability.isSelectable else {
            if case .requiresPermission(let reason) = availability {
                throw STTError.speechAuthorizationRequired(reason)
            }
            throw STTError.engineUnavailable(availability.detailText ?? "SFSpeechRecognizer를 사용할 수 없습니다.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: Self.koreanLocale) else {
            throw STTError.engineUnavailable("한국어 SFSpeechRecognizer를 만들 수 없습니다.")
        }

        let samples = paddedSamples(pcmSamples)
        if let silent = silentResultIfNeeded(samples) {
            return silent
        }

        let url = try writeTemporaryAudioFile(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        let text = try await withCheckedThrowingContinuation { continuation in
            let completion = SFSpeechRecognitionCompletion(continuation: continuation)
            _ = recognizer.recognitionTask(with: request) { result, error in
                completion.handle(result: result, error: error)
            }
        }
        return transcriptionResult(text: text, sampleCount: samples.count)
    }

    // MARK: - Private helpers

    private func updateState(_ state: ModelState) {
        modelState = state
        onModelStateChange?(state)
    }

    private func paddedSamples(_ pcmSamples: [Float]) -> [Float] {
        let minSamples = 8000
        return pcmSamples.count < minSamples
            ? pcmSamples + [Float](repeating: 0, count: minSamples - pcmSamples.count)
            : pcmSamples
    }

    private func silentResultIfNeeded(_ samples: [Float]) -> TranscriptionResult? {
        let dbLevel = Self.dbLevel(samples)
        guard dbLevel < -50 else { return nil }
        fputs("[STT] skip (energy=\(String(format: "%.1f", dbLevel))dB)\n", stderr)
        return transcriptionResult(text: "", sampleCount: samples.count)
    }

    private func transcriptionResult(text: String, sampleCount: Int) -> TranscriptionResult {
        let segment = Segment(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(),
            duration: Double(sampleCount) / Self.sampleRate
        )
        return TranscriptionResult(segment: segment, isFinal: true)
    }

    private static func dbLevel(_ samples: [Float]) -> Float {
        let rms = sqrt(samples.reduce(0.0 as Float) { $0 + $1 * $1 } / Float(samples.count))
        return 20 * log10(max(rms, 1e-7))
    }

    private func writeTemporaryAudioFile(samples: [Float]) throws -> URL {
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

    /// meeting-transcriber에서 채용: WhisperKit 특수 토큰 제거
    private static func stripWhisperTokens(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
    }

    /// 모델 메트릭으로 잡히지 않는 확정 할루시네이션
    private static func isKnownHallucination(_ text: String) -> Bool {
        // 현재는 모델 메트릭(noSpeechProb, avgLogprob, compressionRatio)에 위임
        // 텍스트 기반 필터는 실제 발화를 오필터링할 수 있어 사용하지 않음
        return false
    }

}

private final class SFSpeechRecognitionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<String, Error>

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error {
            resume(with: .failure(error))
            return
        }

        guard let result, result.isFinal else { return }
        resume(with: .success(result.bestTranscription.formattedString))
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
