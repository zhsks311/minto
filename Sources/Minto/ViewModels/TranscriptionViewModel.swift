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

    // MARK: - Init

    public init() {
        // STTService 상태 변화 → ViewModel @Published 전파
        sttService.onModelStateChange = { [weak self] state in
            self?.modelState = state
        }
    }

    // MARK: - Computed

    public var modelVariantName: String {
        sttService.modelVariant.replacingOccurrences(of: "openai_whisper-", with: "")
    }

    public var allText: String {
        committedSegments.map(\.text).joined(separator: "\n")
    }

    // MARK: - Model loading

    public func loadModel(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        await sttService.loadModel(variant: variant)
        // onModelStateChange가 .failed로 설정했을 수 있으므로 에러 메시지 동기화
        if case .failed(let msg) = sttService.modelState {
            errorMessage = "모델 로드 실패: \(msg)"
        }
    }

    // MARK: - Recording control

    public func startRecording() {
        guard !isRecording else { return }
        errorMessage = nil
        vadProcessor.reset()

        // VADProcessor → 최종 청크만 스트림으로, 프리뷰는 별도 cancel-and-replace Task
        vadProcessor.onChunk = { [weak self] chunk in
            Task { @MainActor [weak self] in
                self?.enqueueChunk(chunk)
            }
        }
        vadProcessor.onPreviewChunk = { [weak self] chunk in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
                    // transcribe 완료 후에 pending 초기화 → 깜박임 없음
                    pendingSegment = nil
                    guard !result.segment.text.isEmpty else { continue }
                    state.advanceWindow(newResult: result)
                    committedSegments = state.committedSegments

                    // LLM 비동기 교정: 원본 즉시 표시 후 교정본으로 조용히 교체
                    if let lastSeg = state.committedSegments.last {
                        let segId = lastSeg.id
                        let original = lastSeg.text
                        let context = state.recentCommittedText
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            guard let corrected = await llmService.correct(text: original, context: context),
                                  corrected != original else { return }
                            self.state.updateSegmentText(id: segId, newText: corrected)
                            self.committedSegments = self.state.committedSegments
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
        audioSource.stop()
        chunkContinuation?.finish()
        transcriptionTask?.cancel()
        previewTask?.cancel()
        chunkContinuation = nil
        transcriptionTask = nil
        previewTask = nil
        isRecording = false
        audioLevel = 0
        stopTimer()
    }

    public func clearTranscript() {
        committedSegments = []
        pendingSegment = nil
        state = TranscriptionState()
    }

    public func enqueueChunk(_ chunk: AudioChunk) {
        chunkContinuation?.yield(chunk)
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
