import Foundation
import SwiftUI
import os

@MainActor
protocol TranscriptionSTTServicing: AnyObject {
    var modelState: ModelState { get }
    var modelVariant: String { get }
    var speechEngineID: SpeechEngineID { get }
    var supportsPreviewTranscription: Bool { get }
    var onModelStateChange: ((ModelState) -> Void)? { get set }

    func loadEngine(_ engineID: SpeechEngineID) async
    func loadModel(variant: String) async
    func recoverModelCacheAndReload(variant: String) async
    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult
}

extension STTService: TranscriptionSTTServicing {}

@MainActor
protocol TranscriptionSummaryGenerating: AnyObject {
    func generateIncremental(correctedBatch: String) async -> String?
    func generateFinal(transcript: String) async -> MeetingSummary?
}

extension SummaryService: TranscriptionSummaryGenerating {}

@MainActor
public final class TranscriptionViewModel: ObservableObject {

    // MARK: - Published

    @Published public var committedSegments: [Segment] = []
    @Published public var pendingSegment: Segment?
    @Published public var isRecording: Bool = false
    @Published public var isPermissionDenied: Bool = false
    @Published public var errorMessage: String?
    @Published public var modelState: ModelState = .unloaded
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var audioLevel: Float = 0
    @Published public var isFinalizingMeeting: Bool = false
    @Published public private(set) var audioInputMode: AudioInputMode = .microphone

    // MARK: - Private

    private let sttService: any TranscriptionSTTServicing
    private let llmService = LLMCorrectionService.shared
    private let summaryService: any TranscriptionSummaryGenerating
    private var transcriptionTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var audioSource: any AudioSourceProtocol
    private let audioSourceFactory: @MainActor (AudioInputMode) -> any AudioSourceProtocol
    private var vadProcessor: any VoiceActivityDetector
    /// nil이면 주입된 VAD를 그대로 쓴다. 있으면 녹음 시작마다 현재 인스턴스를 넘겨
    /// 다음 인스턴스를 결정한다 — 같은 엔진이면 재사용해 모델 워밍업을 유지하고,
    /// 설정이 바뀌었으면 교체한다. (설정 변경은 다음 녹음부터 적용)
    private let vadProcessorFactory: (@MainActor (any VoiceActivityDetector) -> any VoiceActivityDetector)?
    /// nil이면 사용 시점에 설정/환경변수에서 해석한다. (회의 중 토글이 현재 녹음에도 즉시 반영)
    private let injectedEmptyFinalRepairPolicy: EmptyFinalRepairPolicy?
    private let audioSampleBuffer: TranscriptionAudioSampleBuffer
    private let channelSpeakerLabeler = ChannelSpeakerLabeler()
    private var channelActivityProvider: (any RecordingChannelActivityProviding)?
    private var recordingInputMode: AudioInputMode = .microphone
    private let liveSpeakerAssignment: LiveSpeakerAssignmentUseCase?
    /// LS-EEND/VBx timeline은 speech-only이고 STT chunk는 침묵을 포함할 수 있어,
    /// 라이브 표시는 positive overlap만 있으면 라벨 후보로 인정한다.
    private let transcriptSpeakerMatcher = TranscriptSpeakerMatcher(minimumOverlapRatio: 0)
    private var liveSpeakerStartTask: Task<Void, Never>?
    private var liveSpeakerAssignmentStarted = false
    private var liveSpeakerAssignmentActive = false
    private(set) var liveDiarizedSegments: [DiarizedSpeakerSegment] = []
    private var liveSpeakerSessionGeneration = 0
    private(set) var editedSpeakerSegmentIds: Set<Segment.ID> = []
    /// nil이면 오디오 보존 안 함(테스트 기본). 프로덕션 convenience init이 factory를 공급한다.
    private let audioArchiverFactory: (@MainActor () -> RecordingAudioArchiver)?
    private var audioArchiver: RecordingAudioArchiver?
    /// 직전 녹음에서 보존된 오디오 파일명. 저장 record에 연결하기 위해 노출한다.
    public private(set) var lastArchivedAudioFileName: String?

    private var emptyFinalRepairPolicy: EmptyFinalRepairPolicy {
        injectedEmptyFinalRepairPolicy ?? .resolve()
    }
    private var state = TranscriptionState()
    private var recordingStartDate: Date?

    // 창 단위 배치 교정: 미교정 구간을 모았다가 누적 길이가 window에 도달하면
    // 한 번에 교정 후 하나의 문단으로 병합한다. (구간간 일관성·교정 품질·호출 수 개선)
    // 30초: 배치당 문맥을 넓혀 교정 품질↑, LLM 호출·요약 cadence↓. 원본은 즉시 표시되므로
    // 교정본이 덮이는 지연만 늘 뿐 체감 영향은 작다(#3).
    private static let correctionWindowSeconds: TimeInterval = 30
    // committedSegments가 이 개수에 이르면 듀레이션 미달이라도 교정을 flush한다.
    // TranscriptionState가 100개 초과 시 committedSegments를 evict(.transcriptionNeedsFlush 후 비움)하는데,
    // 그 전에 교정을 끝내지 않으면 미교정 원본이 그대로 보고서에 남는다(SMELL-2). 캡(100)보다 충분히 낮게.
    private static let correctionSafetyFlushCount = 80
    // 교정 프롬프트에 넘길 직전 verbatim 청크 수(#2). 전역 맥락은 회의 요약이 담당하므로 5개면 충분.
    private static let correctionContextSegments = 5
    private var pendingCorrectionIds: [UUID] = []
    private var pendingCorrectionDuration: TimeInterval = 0
    // 교정 Task 체인: 직전 교정 완료를 기다린 뒤 다음 교정을 반영해 replaceRange 순서를 보장하고
    // (동시 완료 시 역순 병합 방지), 마지막 배치 교정이 레이스로 누락되지 않게 한다(SMELL-3).
    private var correctionTask: Task<Void, Never>?
    // 진행 중 증분 요약 Task. drop-if-running(진행 중이면 이번 배치 skip)으로 호출·종료지연을 바운드한다.
    private var summaryTask: Task<Void, Never>?
    private(set) var transcriptTimelineStartDate: Date?

    // MARK: - Init

    public convenience init() {
        self.init(
            sttService: STTService(),
            audioSource: MicrophoneSource(),
            vadProcessor: VoiceActivityDetectorFactory.makeDefault(),
            audioSourceFactory: AudioSourceFactory.makeSource(for:),
            vadProcessorFactory: { VoiceActivityDetectorFactory.makeNext(current: $0) },
            liveSpeakerAssignment: LiveSpeakerAssignmentUseCase(provider: FluidAudioLSEENDStreamingProvider()),
            audioArchiverFactory: { RecordingAudioArchiver() }
        )
    }

    init(
        sttService: any TranscriptionSTTServicing,
        audioSource: any AudioSourceProtocol,
        vadProcessor: any VoiceActivityDetector,
        summaryService: any TranscriptionSummaryGenerating = SummaryService.shared,
        emptyFinalRepairPolicy: EmptyFinalRepairPolicy? = nil,
        audioSourceFactory: (@MainActor (AudioInputMode) -> any AudioSourceProtocol)? = nil,
        vadProcessorFactory: (@MainActor (any VoiceActivityDetector) -> any VoiceActivityDetector)? = nil,
        liveSpeakerAssignment: LiveSpeakerAssignmentUseCase? = nil,
        audioArchiverFactory: (@MainActor () -> RecordingAudioArchiver)? = nil
    ) {
        let initialAudioSource = audioSource
        self.sttService = sttService
        self.summaryService = summaryService
        self.audioSource = audioSource
        self.audioSourceFactory = audioSourceFactory ?? { _ in initialAudioSource }
        self.vadProcessor = vadProcessor
        self.vadProcessorFactory = vadProcessorFactory
        self.liveSpeakerAssignment = liveSpeakerAssignment
        self.audioArchiverFactory = audioArchiverFactory
        self.injectedEmptyFinalRepairPolicy = emptyFinalRepairPolicy
        self.audioSampleBuffer = TranscriptionAudioSampleBuffer(
            maxBufferedSeconds: emptyFinalRepairPolicy?.maxBufferedSeconds
                ?? EmptyFinalRepairPolicy.defaultMaxBufferedSeconds
        )

        // STTService 상태 변화 → ViewModel @Published 전파
        self.sttService.onModelStateChange = { [weak self] state in
            self?.modelState = state
        }
    }

    // MARK: - Computed

    public var modelVariantName: String {
        if sttService.speechEngineID.whisperVariant != nil {
            return sttService.modelVariant.replacingOccurrences(of: "openai_whisper-", with: "")
        }
        return sttService.speechEngineID.engineName
    }

    public var modelDisplayName: String {
        sttService.speechEngineID.title
    }

    public var speechEngineID: SpeechEngineID {
        sttService.speechEngineID
    }

    public var cacheRecoveryVariant: String? {
        guard sttService.speechEngineID.supportsCacheRecovery else { return nil }

        if let variant = sttService.speechEngineID.whisperVariant {
            return variant
        }

        let variant = sttService.modelVariant.trimmingCharacters(in: .whitespacesAndNewlines)
        return variant.isEmpty ? nil : variant
    }

    public static func displayName(for variant: String) -> String {
        switch variant {
        case "openai_whisper-large-v3-v20240930_turbo":
            return "회의 정확도 우선"
        case "openai_whisper-medium":
            return "균형"
        case "openai_whisper-small":
            return "빠른 기록"
        default:
            return variant.replacingOccurrences(of: "openai_whisper-", with: "")
        }
    }

    public var allText: String {
        committedSegments.map(\.text).joined(separator: "\n")
    }

    // MARK: - Model loading

    public func loadSpeechEngine(_ engineID: SpeechEngineID = .defaultEngine) async {
        errorMessage = nil
        await sttService.loadEngine(engineID)
        if case .failed(let msg) = sttService.modelState {
            errorMessage = "음성 인식 엔진 전환 실패: \(msg)"
        }
    }

    public func loadModel(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        await sttService.loadModel(variant: variant)
        // onModelStateChange가 .failed로 설정했을 수 있으므로 에러 메시지 동기화
        if case .failed(let msg) = sttService.modelState {
            errorMessage = "모델 로드 실패: \(msg)"
        }
    }

    public func recoverModelCacheAndReload(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        errorMessage = nil
        await sttService.recoverModelCacheAndReload(variant: variant)
        if case .failed(let msg) = sttService.modelState {
            errorMessage = "모델 복구 실패: \(msg)"
        }
    }

    // MARK: - Recording control

    public func startNewRecordingSession(inputMode: AudioInputMode = .microphone) {
        guard !isRecording else { return }
        setAudioInputMode(inputMode)
        clearTranscript()
        startRecording()
    }

    public func setAudioInputMode(_ mode: AudioInputMode) {
        guard !isRecording else { return }
        audioSource.stop()
        audioSource = audioSourceFactory(mode)
        audioInputMode = mode
    }

    public func startRecording() {
        guard !isRecording else { return }
        errorMessage = nil
        isFinalizingMeeting = false
        audioSampleBuffer.reset()
        recordingInputMode = audioInputMode
        prepareLiveSpeakerAssignmentForRecording()
        channelActivityProvider = audioSource as? RecordingChannelActivityProviding
        // 녹음 생명주기 소유자인 VM이 직전 녹음의 stale 타임라인을 명시적으로 비운다.
        // (MixedAudioSource.start()도 방어적으로 초기화하지만, 여기서 먼저 끊는다.)
        channelActivityProvider?.resetChannelActivity()
        // VAD 엔진 설정 변경은 다음 녹음부터 적용 — 녹음 시작 시점에 설정을 다시 읽는다.
        if let vadProcessorFactory {
            vadProcessor = vadProcessorFactory(vadProcessor)
        }
        vadProcessor.reset()
        let appliedVADEngine = vadProcessor is SileroVADProcessor ? "silero" : "energy"
        Log.vad.notice("recording vad engine=\(appliedVADEngine, privacy: .public) emptyFinalRepair=\(self.emptyFinalRepairPolicy.isEnabled, privacy: .public)")

        // 녹음 오디오 보존(설정 기반) — 실패해도 전사에 영향 없음(fail-soft).
        lastArchivedAudioFileName = nil
        if let audioArchiverFactory, RecordingAudioArchiver.isEnabled() {
            let archiver = audioArchiverFactory()
            archiver.start()
            audioArchiver = archiver
        } else {
            audioArchiver = nil
        }
        // 이전 회의의 관련 문서 조회 결과가 새 회의에 남지 않도록 초기화.
        RelatedInfoService.shared.clear()

        // VADProcessor → 최종 청크만 스트림으로, 프리뷰는 별도 cancel-and-replace Task
        vadProcessor.onChunk = { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.enqueueChunk(chunk)
            }
        }
        vadProcessor.onPreviewChunk = { [weak self] chunk in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.sttService.supportsPreviewTranscription else {
                    self.pendingSegment = nil
                    return
                }
                self.previewTask?.cancel()
                self.previewTask = Task { @MainActor [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    do {
                        let result = try await self.sttService.transcribe(pcmSamples: chunk.samples)
                        guard !Task.isCancelled else { return }
                        let positioned = self.positionedResult(result, for: chunk)
                        self.pendingSegment = positioned.segment.text.isEmpty ? nil : positioned.segment
                        self.applyCurrentLiveSpeakerLabels()
                    } catch { /* preview 실패는 무시 */ }
                }
            }
        }

        // AudioSource → VADProcessor + 레벨 미터
        audioSource.onBuffer = { [weak self] samples in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioSampleBuffer.append(samples)
                self.audioArchiver?.append(samples: samples)
                self.vadProcessor.process(samples: samples)
                await self.ingestLiveSpeakerBuffer(samples)
            }
        }
        audioSource.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }
        audioSource.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleAudioError(error)
            }
        }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream()
        chunkContinuation = continuation

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in stream {
                // 스트림에는 최종 청크만 들어옴 (preview는 별도 previewTask로 처리)
                Log.stt.debug("final chunk arrived samples=\(chunk.samples.count, privacy: .public)")
                previewTask?.cancel()
                previewTask = nil
                do {
                    let result = try await transcribeFinalChunk(chunk)
                    Log.stt.debug("STT final result chars=\(result.segment.text.count, privacy: .public)")
                    guard !result.segment.text.isEmpty else {
                        if pendingSegment != nil {
                            Log.stt.debug("STT final empty; keeping pending preview until next update")
                        }
                        continue
                    }
                    // final 결과가 확정된 뒤에만 pending을 지운다. final이 빈 출력이면
                    // preview가 즉시 사라지는 대신 다음 preview/final/clear까지 미확정 상태로 둔다.
                    pendingSegment = nil
                    state.advanceWindow(newResult: result)
                    committedSegments = state.committedSegments
                    applyCurrentLiveSpeakerLabels()

                    // 창 단위 배치 교정: 원본은 즉시 표시하고, 누적 길이가 window에
                    // 도달하면 그 구간들을 한 번에 교정해 하나의 문단으로 병합한다.
                    // (advanceWindow가 dedup으로 skip하면 마지막 id가 바뀌지 않으므로 추가하지 않음)
                    if state.committedSegments.last?.id == result.segment.id {
                        pendingCorrectionIds.append(result.segment.id)
                        pendingCorrectionDuration += result.segment.duration
                        // 듀레이션 도달, 또는 evict 캡에 근접하면(미교정 원본이 보고서에 남는 것 방지) flush.
                        if pendingCorrectionDuration >= Self.correctionWindowSeconds
                            || state.committedSegments.count >= Self.correctionSafetyFlushCount {
                            flushCorrectionBatch()
                        }
                    }
                } catch {
                    Log.stt.error("transcription error: \(error.localizedDescription, privacy: .public)")
                    errorMessage = "전사 오류: \(error.localizedDescription)"
                }
            }
        }

        do {
            try audioSource.start()
            isRecording = true
            startLiveSpeakerAssignmentIfNeeded()
            let engineID = sttService.speechEngineID.rawValue
            Log.app.notice("recording started engine=\(engineID, privacy: .public)")
            startTimer()
        } catch {
            // 시작 실패 — 열린 아카이브 파일을 정리한다(0프레임이라 빈 파일은 남지 않는다).
            discardAudioArchiver()
            chunkContinuation?.finish()
            transcriptionTask?.cancel()
            errorMessage = "오디오 엔진 시작 실패: \(error.localizedDescription)"
        }
    }

    /// 정상 종료(stopRecordingAndDrain)가 아닌 경로에서 아카이버를 닫는다.
    /// 기록된 프레임이 없으면 finish()가 빈 파일을 지우고, 일부 기록됐다면
    /// 파일은 record에 연결되지 않은 채 남아 보관 기간 정리가 수거한다.
    private func discardAudioArchiver() {
        guard let archiver = audioArchiver else { return }
        audioArchiver = nil
        Task {
            _ = await archiver.finish()
        }
    }

    public func stopRecording() {
        Task { @MainActor [weak self] in
            await self?.stopRecordingAndDrain()
        }
    }

    /// 녹음 종료 시 VAD 잔여 버퍼를 최종 청크로 흘려보낸 뒤 전사 Task가 끝날 때까지 기다린다.
    public func stopRecordingAndDrain() async {
        let finalRecordingDuration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? recordingDuration

        audioSource.stop()
        isRecording = false
        let segmentCount = committedSegments.count
        Log.app.info("recording stopped duration=\(finalRecordingDuration, privacy: .public)s segments=\(segmentCount, privacy: .public)")
        audioLevel = 0
        stopTimer()
        recordingDuration = finalRecordingDuration

        previewTask?.cancel()
        previewTask = nil

        // MicrophoneSource는 audio tap에서 DispatchQueue.main.async로 buffer를 넘긴다.
        // stop 직전에 이미 main queue에 올라온 마지막 buffer가 VAD queue에 들어간 뒤 drain한다.
        await waitForMainQueueTurn()
        if let audioArchiver {
            lastArchivedAudioFileName = await audioArchiver.finish()
            self.audioArchiver = nil
            Log.audio.info("recording audio archived file=\(self.lastArchivedAudioFileName ?? "none", privacy: .public)")
        }
        if let finalChunk = await vadProcessor.flushPending() {
            enqueueChunk(finalChunk)
        }

        chunkContinuation?.finish()
        await transcriptionTask?.value
        await finishLiveSpeakerAssignmentIfNeeded()

        // 마지막 창(window 미달분)도 교정·병합되도록 flush
        flushCorrectionBatch()
        chunkContinuation = nil
        transcriptionTask = nil
    }

    public func clearTranscript() {
        committedSegments = []
        pendingSegment = nil
        state = TranscriptionState()
        pendingCorrectionIds = []
        pendingCorrectionDuration = 0
        editedSpeakerSegmentIds = []
        resetLiveSpeakerAssignmentState()
        // 이전 세션의 교정·요약 Task가 새 세션 상태에 새지 않도록 취소.
        correctionTask?.cancel()
        correctionTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        transcriptTimelineStartDate = nil
        isFinalizingMeeting = false
    }

    /// 누적된 배치를 교정/요약한다.
    /// 교정 실패나 교정 off 상태에서는 원본을 유지하되, 요약이 켜져 있으면 원본으로 증분 요약을 갱신한다.
    private func flushCorrectionBatch() {
        guard !pendingCorrectionIds.isEmpty else { return }
        let ids = pendingCorrectionIds
        pendingCorrectionIds = []
        pendingCorrectionDuration = 0

        let segmentsToCorrect = state.committedSegments.filter { ids.contains($0.id) }
        guard !segmentsToCorrect.isEmpty else { return }
        let original = segmentsToCorrect.map(\.text).joined(separator: " ")
        // 교정 대상 배치 "이전" 텍스트만 맥락으로 넘긴다(배치와 겹치면 LLM이 그 문장을 출력에 에코함, BUG-1).
        // 청크 수는 #2에 따라 상향(전역 맥락은 회의 요약이 담당).
        let context = state.precedingText(beforeIds: ids, maxSegments: Self.correctionContextSegments)

        // 직전 교정 완료를 기다린 뒤 반영 → replaceRange 순서 보장 + 마지막 배치 누락 방지(SMELL-3).
        let previous = correctionTask
        correctionTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }

            let summaryBatch: String
            if let corrected = await self.llmService.correct(text: original, context: context),
               !corrected.isEmpty {
                self.state.replaceRange(ids: ids, correctedText: corrected)
                self.committedSegments = self.state.committedSegments
                self.applyCurrentLiveSpeakerLabels()
                summaryBatch = corrected
            } else {
                summaryBatch = original
            }

            self.enqueueIncrementalSummary(summaryBatch)
        }
    }

    private func enqueueIncrementalSummary(_ batch: String) {
        let trimmed = batch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, summaryTask == nil else { return }

        // drop-if-running: 진행 중이면 이번 배치는 건너뛴다.
        // 누락분은 runningSummary 누적본 + 종료 시 최종 요약이 보완.
        summaryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.summaryTask = nil }
            _ = await self.summaryService.generateIncremental(correctedBatch: trimmed)
        }
    }

    private func transcribeFinalChunk(_ chunk: AudioChunk) async throws -> TranscriptionResult {
        let result = try await sttService.transcribe(pcmSamples: chunk.samples)
        guard result.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let repairSamples = emptyFinalRepairSamples(for: chunk) else {
            return positionedResult(result, for: chunk)
        }

        let repaired = try await sttService.transcribe(pcmSamples: repairSamples)
        guard !repaired.segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return positionedResult(result, for: chunk)
        }

        Log.stt.debug("STT empty final repaired samples=\(repairSamples.count, privacy: .public)")
        return positionedResult(repaired, for: chunk)
    }

    private func positionedResult(_ result: TranscriptionResult, for chunk: AudioChunk) -> TranscriptionResult {
        let segment = result.segment
        let timestamp: Date
        if let startSeconds = chunk.startSeconds,
           let timelineStart = transcriptTimelineStartDate {
            timestamp = timelineStart.addingTimeInterval(startSeconds)
        } else {
            timestamp = segment.timestamp
        }

        let duration: TimeInterval
        if let startSeconds = chunk.startSeconds,
           let endSeconds = chunk.endSeconds,
           endSeconds > startSeconds {
            duration = endSeconds - startSeconds
        } else if chunk.durationSeconds > 0 {
            duration = chunk.durationSeconds
        } else {
            duration = segment.duration
        }
        // preview는 발화가 끝나지 않은 부분 데이터라 채널 우세 판정이 불완전하다.
        // 라벨을 붙이면 final에서 다른 채널로 확정될 때 "나"↔"상대"가 깜빡인다.
        // result.isFinal은 STT 결과 자체 속성이라 preview 전사도 true로 오므로,
        // preview/final을 가르는 chunk.isPreview로 게이트한다(final 청크에만 라벨).
        let speaker = chunk.isPreview
            ? nil
            : channelSpeakerLabeler.speaker(
                inputMode: recordingInputMode,
                activityProvider: channelActivityProvider,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds
            )

        return TranscriptionResult(
            segment: Segment(
                id: segment.id,
                text: segment.text,
                timestamp: timestamp,
                duration: duration,
                speaker: speaker,
                words: segment.words
            ),
            isFinal: result.isFinal
        )
    }

    private func emptyFinalRepairSamples(for chunk: AudioChunk) -> [Float]? {
        let audioDB = STTAudioUtilities.dbLevel(chunk.samples)
        guard emptyFinalRepairPolicy.allowsRetry(for: chunk, audioDB: audioDB) else { return nil }
        return audioSampleBuffer.paddedSamples(
            startSeconds: chunk.startSeconds,
            endSeconds: chunk.endSeconds,
            padSeconds: emptyFinalRepairPolicy.padSeconds
        )
    }

    /// 회의 종료 시 호출. 마지막 교정 완료를 기다린 뒤(SMELL-3) 남은 전사로 최종 요약을 생성해 반환한다.
    /// fail-soft: 요약 생성 실패 시 nil(또는 마지막 누적 요약 폴백은 SummaryService가 처리).
    public func finalizeMeeting() async -> MeetingSummary? {
        await correctionTask?.value
        // 시점 포함 전사(첫 발화 기준 상대 [MM:SS])를 만들어 넘긴다 → LLM이 섹션 time을 실제 시점에서 고른다.
        let start = committedSegments.first?.timestamp ?? Date()
        let transcript = committedSegments.map { seg -> String in
            let s = max(0, Int(seg.timestamp.timeIntervalSince(start).rounded()))
            return String(format: "[%02d:%02d] %@", s / 60, s % 60, seg.text)
        }.joined(separator: "\n")
        return await summaryService.generateFinal(transcript: transcript)
    }

    public func enqueueChunk(_ chunk: AudioChunk) {
        chunkContinuation?.yield(chunk)
    }

    public func reassignLiveSpeaker(segmentId: Segment.ID, to label: String) {
        let updatedSegments = SpeakerLabelEditing.reassignSegment(
            id: segmentId,
            to: label,
            in: committedSegments
        )
        guard updatedSegments != committedSegments else { return }

        replaceCommittedSegments(updatedSegments)
        editedSpeakerSegmentIds.insert(segmentId)
    }

    public func renameLiveSpeaker(from source: String, to target: String) {
        guard let sourceLabel = SpeakerLabel.normalized(source),
              SpeakerLabel.normalized(target) != nil else {
            return
        }

        let editedIds = committedSegments
            .filter { SpeakerLabel.normalized($0.speaker) == sourceLabel }
            .map(\.id)
        guard !editedIds.isEmpty else { return }

        let updatedSegments = SpeakerLabelEditing.replacingSpeaker(
            source,
            with: target,
            in: committedSegments
        )
        guard updatedSegments != committedSegments else { return }

        replaceCommittedSegments(updatedSegments)
        editedSpeakerSegmentIds.formUnion(editedIds)
    }

    private func prepareLiveSpeakerAssignmentForRecording() {
        guard liveSpeakerAssignment != nil else { return }

        liveSpeakerStartTask?.cancel()
        liveSpeakerStartTask = nil
        liveSpeakerAssignmentStarted = false
        liveSpeakerAssignmentActive = false
        liveDiarizedSegments = []
        liveSpeakerSessionGeneration += 1
    }

    private func resetLiveSpeakerAssignmentState() {
        liveSpeakerStartTask?.cancel()
        liveSpeakerStartTask = nil
        liveSpeakerAssignmentStarted = false
        liveSpeakerAssignmentActive = false
        liveDiarizedSegments = []
        liveSpeakerSessionGeneration += 1
    }

    private func startLiveSpeakerAssignmentIfNeeded() {
        guard let liveSpeakerAssignment,
              liveSpeakerStartTask == nil,
              !liveSpeakerAssignmentStarted else {
            return
        }

        let generation = liveSpeakerSessionGeneration
        Log.diarization.info(
            "live speaker assignment vm start preEnrolled=\(0, privacy: .public) segments=\(self.committedSegments.count, privacy: .public)"
        )
        liveSpeakerStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await liveSpeakerAssignment.start(preEnrolled: [])
                guard !Task.isCancelled, self.liveSpeakerSessionGeneration == generation else {
                    return
                }
                self.liveSpeakerAssignmentStarted = true
                self.liveSpeakerAssignmentActive = true
            } catch {
                guard !Task.isCancelled, self.liveSpeakerSessionGeneration == generation else {
                    return
                }
                self.liveSpeakerAssignmentStarted = false
                self.liveSpeakerAssignmentActive = false
                Log.diarization.error(
                    "live speaker assignment vm failed operation=start preEnrolled=\(0, privacy: .public) segments=\(self.committedSegments.count, privacy: .public)"
                )
            }
        }
    }

    private func ingestLiveSpeakerBuffer(_ samples: [Float]) async {
        guard let liveSpeakerAssignment else { return }

        startLiveSpeakerAssignmentIfNeeded()
        await liveSpeakerStartTask?.value
        guard liveSpeakerAssignmentStarted, liveSpeakerAssignmentActive else {
            return
        }

        do {
            let diarizedSegments = try await liveSpeakerAssignment.ingest(
                samples: samples,
                sourceSampleRate: STTAudioUtilities.sampleRate
            )
            let previousSpeakerIds = Set(liveDiarizedSegments.map(\.speakerId))
            let nextSpeakerIds = Set(diarizedSegments.map(\.speakerId))
            // 라벨을 오디오 버퍼마다 다시 칠하면 committedSegments 재할당이 초당 여러 번 일어나
            // 전사 리스트가 깜빡인다. diar는 계속 누적만 하고, 실제 라벨 적용은 전사가 바뀌는 시점
            // (청크 확정/프리뷰/교정)에 한다. 단, 새 화자가 등장하거나 사라진 순간은 기존 줄의
            // 라벨이 실제로 달라질 수 있으므로 그때만 즉시 갱신한다.
            liveDiarizedSegments = diarizedSegments
            if previousSpeakerIds != nextSpeakerIds {
                applyCurrentLiveSpeakerLabels()
            }
        } catch {
            liveSpeakerAssignmentActive = false
            liveDiarizedSegments = []
            restoreChannelLabelsAfterDiarizationFailure()
            Log.diarization.error(
                "live speaker assignment vm failed operation=ingest samples=\(samples.count, privacy: .public) segments=\(self.committedSegments.count, privacy: .public)"
            )
        }
    }

    private func finishLiveSpeakerAssignmentIfNeeded() async {
        guard let liveSpeakerAssignment else { return }

        await liveSpeakerStartTask?.value
        liveSpeakerStartTask = nil
        guard liveSpeakerAssignmentStarted else {
            return
        }
        guard liveSpeakerAssignmentActive else {
            liveSpeakerAssignmentStarted = false
            liveDiarizedSegments = []
            return
        }

        defer {
            liveSpeakerAssignmentStarted = false
            liveSpeakerAssignmentActive = false
        }

        do {
            let diarizedSegments = try await liveSpeakerAssignment.finish()
            liveDiarizedSegments = diarizedSegments
            applyLiveSpeakerLabels(diarizedSegments)
        } catch {
            liveDiarizedSegments = []
            applyLiveSpeakerLabels([])
            Log.diarization.error(
                "live speaker assignment vm failed operation=finish segments=\(self.committedSegments.count, privacy: .public)"
            )
        }
    }

    private func applyCurrentLiveSpeakerLabels() {
        guard liveSpeakerAssignment != nil, liveSpeakerAssignmentActive else { return }
        applyLiveSpeakerLabels(liveDiarizedSegments)
    }

    private func restoreChannelLabelsAfterDiarizationFailure() {
        let timelineStart = transcriptTimelineStartDate
        let relabeledSegments = committedSegments.map { segment in
            guard !editedSpeakerSegmentIds.contains(segment.id) else {
                return segment
            }

            let startSeconds: Double?
            let endSeconds: Double?
            if let timelineStart {
                let start = segment.timestamp.timeIntervalSince(timelineStart)
                startSeconds = start
                endSeconds = start + segment.duration
            } else {
                startSeconds = nil
                endSeconds = nil
            }

            var updated = segment
            updated.speaker = SpeakerLabel.normalized(
                channelSpeakerLabeler.speaker(
                    inputMode: recordingInputMode,
                    activityProvider: channelActivityProvider,
                    startSeconds: startSeconds,
                    endSeconds: endSeconds
                )
            )
            return updated
        }

        replaceCommittedSegments(relabeledSegments)
        Log.diarization.info(
            "live diarization degraded to channel labels segments=\(self.committedSegments.count, privacy: .public)"
        )
    }

    private func applyLiveSpeakerLabels(_ diarizedSegments: [DiarizedSpeakerSegment]) {
        guard liveSpeakerAssignment != nil else { return }
        guard !committedSegments.isEmpty || pendingSegment != nil else { return }
        guard let meetingStart = transcriptTimelineStartDate
            ?? committedSegments.first?.timestamp
            ?? pendingSegment?.timestamp else {
            return
        }

        var transcript = committedSegments
        let pendingId = pendingSegment?.id
        if let pendingSegment {
            transcript.append(pendingSegment)
        }

        let matchedSegments = transcriptSpeakerMatcher.assignSpeakers(
            diarizedSegments: diarizedSegments,
            transcript: transcript,
            meetingStart: meetingStart
        )
        var matchedById: [Segment.ID: Segment] = [:]
        for matched in matchedSegments {
            matchedById[matched.id] = matched
        }

        let labeledCommitted = committedSegments.map { segment in
            guard !editedSpeakerSegmentIds.contains(segment.id),
                  let matched = matchedById[segment.id],
                  let newSpeaker = SpeakerLabel.normalized(matched.speaker) else {
                return segment
            }

            var updated = segment
            updated.speaker = newSpeaker
            return updated
        }
        // 라벨이 실제로 바뀐 경우에만 재할당(불필요한 @Published 발화·재렌더 방지).
        if labeledCommitted != committedSegments {
            replaceCommittedSegments(labeledCommitted)
        }

        if let pendingId,
           let pending = pendingSegment,
           let matched = matchedById[pendingId],
           let newSpeaker = SpeakerLabel.normalized(matched.speaker) {
            if pending.speaker != newSpeaker {
                var updated = pending
                updated.speaker = newSpeaker
                pendingSegment = updated
            }
        }
    }

    private func replaceCommittedSegments(_ segments: [Segment]) {
        state.replaceCommittedSegments(segments)
        committedSegments = segments
    }

    private func waitForMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    // MARK: - Timer

    private func startTimer() {
        recordingStartDate = Date()
        transcriptTimelineStartDate = recordingStartDate
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
                guard let self, let start = self.recordingStartDate else { break }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        recordingStartDate = nil
        recordingDuration = 0
    }

    // MARK: - Error handling

    private func handleAudioError(_ error: AudioSourceError) {
        defer {
            // 에러로 녹음이 중단된 경우 아카이버를 닫는다(정상 종료는 drain에서 finish).
            if !isRecording {
                discardAudioArchiver()
            }
        }
        switch error {
        case .permissionDenied:
            isPermissionDenied = true
            isRecording = false
        case .screenCapturePermissionDenied:
            isPermissionDenied = true
            isRecording = false
            errorMessage = "시스템 사운드 입력을 사용하려면 화면 기록 권한이 필요해요."
        case .systemAudioUnavailable(let reason):
            errorMessage = "시스템 사운드 입력을 사용할 수 없어요: \(reason)"
            isRecording = false
        case .configChangeFailed(let underlying):
            errorMessage = "오디오 설정 변경 실패: \(underlying.localizedDescription)"
        case .deviceNotFound(let device):
            errorMessage = "오디오 장치를 찾을 수 없어요: \(device.name)"
            isRecording = false
        case .engineStartFailed(let underlying):
            errorMessage = "오디오 엔진 시작 실패: \(underlying.localizedDescription)"
            isRecording = false
        }
    }
}
