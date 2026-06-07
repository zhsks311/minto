import Foundation
import SwiftUI

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

    // MARK: - Private

    private let sttService = STTService()
    private let llmService = LLMCorrectionService.shared
    private var transcriptionTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private let audioSource: AudioSourceProtocol = MicrophoneSource()
    private let vadProcessor = VADProcessor()
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

    // MARK: - Init

    public init() {
        // STTService 상태 변화 → ViewModel @Published 전파
        sttService.onModelStateChange = { [weak self] state in
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

    public func startRecording() {
        guard !isRecording else { return }
        errorMessage = nil
        isFinalizingMeeting = false
        vadProcessor.reset()
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
                        self.pendingSegment = result.segment.text.isEmpty ? nil : result.segment
                    } catch { /* preview 실패는 무시 */ }
                }
            }
        }

        // AudioSource → VADProcessor + 레벨 미터
        audioSource.onBuffer = { [weak self] samples in
            self?.vadProcessor.process(samples: samples)
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
                fputs("[VM] final chunk arrived samples=\(chunk.samples.count)\n", stderr)
                previewTask?.cancel()
                previewTask = nil
                do {
                    let result = try await sttService.transcribe(pcmSamples: chunk.samples)
                    fputs("[VM] STT final result: '\(result.segment.text)'\n", stderr)
                    guard !result.segment.text.isEmpty else {
                        if pendingSegment != nil {
                            fputs("[VM] STT final empty; keeping pending preview until next update\n", stderr)
                        }
                        continue
                    }
                    // final 결과가 확정된 뒤에만 pending을 지운다. final이 빈 출력이면
                    // preview가 즉시 사라지는 대신 다음 preview/final/clear까지 미확정 상태로 둔다.
                    pendingSegment = nil
                    state.advanceWindow(newResult: result)
                    committedSegments = state.committedSegments

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
                    fputs("[VM] transcription error: \(error)\n", stderr)
                    errorMessage = "전사 오류: \(error.localizedDescription)"
                }
            }
        }

        do {
            try audioSource.start()
            isRecording = true
            startTimer()
        } catch {
            chunkContinuation?.finish()
            transcriptionTask?.cancel()
            errorMessage = "오디오 엔진 시작 실패: \(error.localizedDescription)"
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
        audioLevel = 0
        stopTimer()
        recordingDuration = finalRecordingDuration

        previewTask?.cancel()
        previewTask = nil

        // MicrophoneSource는 audio tap에서 DispatchQueue.main.async로 buffer를 넘긴다.
        // stop 직전에 이미 main queue에 올라온 마지막 buffer가 VAD queue에 들어간 뒤 drain한다.
        await waitForMainQueueTurn()
        if let finalChunk = await vadProcessor.flushPending() {
            enqueueChunk(finalChunk)
        }

        chunkContinuation?.finish()
        await transcriptionTask?.value

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
        // 이전 세션의 교정·요약 Task가 새 세션 상태에 새지 않도록 취소.
        correctionTask?.cancel()
        correctionTask = nil
        summaryTask?.cancel()
        summaryTask = nil
        isFinalizingMeeting = false
    }

    /// 누적된 미교정 구간을 한 번에 교정해 하나의 문단으로 병합한다.
    /// 원본은 이미 표시돼 있으므로 fail-soft: 실패하면 병합하지 않고 원본을 유지한다.
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
            guard let corrected = await self.llmService.correct(text: original, context: context),
                  !corrected.isEmpty else { return }
            self.state.replaceRange(ids: ids, correctedText: corrected)
            self.committedSegments = self.state.committedSegments

            // 교정본으로 증분 요약 갱신. drop-if-running: 진행 중이면 이번 배치는 건너뛴다
            // (요약 호출 누적·종료 지연 방지). 누락분은 runningSummary 누적본 + 종료 시 최종 요약이 보완.
            if self.summaryTask == nil {
                self.summaryTask = Task { @MainActor [weak self] in
                    defer { self?.summaryTask = nil }
                    await SummaryService.shared.generateIncremental(correctedBatch: corrected)
                }
            }
        }
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
        return await SummaryService.shared.generateFinal(transcript: transcript)
    }

    public func enqueueChunk(_ chunk: AudioChunk) {
        chunkContinuation?.yield(chunk)
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
        switch error {
        case .permissionDenied:
            isPermissionDenied = true
            isRecording = false
        case .configChangeFailed(let underlying):
            errorMessage = "오디오 설정 변경 실패: \(underlying.localizedDescription)"
        case .deviceNotFound(let device):
            errorMessage = "오디오 장치를 찾을 수 없습니다: \(device.name)"
            isRecording = false
        case .engineStartFailed(let underlying):
            errorMessage = "오디오 엔진 시작 실패: \(underlying.localizedDescription)"
            isRecording = false
        }
    }
}
