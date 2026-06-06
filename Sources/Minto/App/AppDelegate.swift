import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    public let viewModel: TranscriptionViewModel
    public let floatingWindowManager: FloatingWindowManager
    public let meetingSetupManager: MeetingSetupWindowManager
    public let reportService = ReportService()
    /// 회의 목록·상세 메인 윈도우. "새 회의 시작"은 기존 시작 흐름을 탄다.
    @MainActor public lazy var mainWindowManager = MainWindowManager(
        viewModel: viewModel,
        onNewMeeting: { [weak self] in self?.requestStartSession() },
        onShowOverlay: { [weak self] in self?.floatingWindowManager.show() }
    )

    override init() {
        let (vm, floatManager, setupManager) = MainActor.assumeIsolated {
            let vm = TranscriptionViewModel()
            return (vm, FloatingWindowManager(viewModel: vm), MeetingSetupWindowManager())
        }
        viewModel = vm
        floatingWindowManager = floatManager
        meetingSetupManager = setupManager
        super.init()
    }

    /// "녹음 시작" → 회의 시작 시트를 띄우고, "시작" 시 회의 맥락 설정 후 실제 녹음을 시작한다.
    @MainActor
    public func requestStartSession() {
        meetingSetupManager.show(
            onStart: { [weak self] topic, glossary, document in
                guard let self else { return }
                MeetingContext.shared.start(topic: topic, glossary: glossary, document: document)
                self.reportService.startNewReport(startedAt: Date())
                self.viewModel.startRecording()
                self.mainWindowManager.show()
            },
            onCancel: {}
        )
    }

    /// "녹음 종료" → 녹음 정지 → (마지막 교정 완료 후) 최종 요약 생성
    /// → 보고서에 tail·요약 기록 후 마감 → 회의 목록 갱신 → 회의 맥락 초기화.
    @MainActor
    public func handleStopRecording() {
        floatingWindowManager.hide()
        mainWindowManager.show()
        viewModel.isFinalizingMeeting = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.viewModel.isFinalizingMeeting = false }
            await self.viewModel.stopRecordingAndDrain()
            let summary = await self.viewModel.finalizeMeeting()
            let segments = self.viewModel.committedSegments

            // 회의 기록을 영속화(요약이 없어도 전사가 있으면 저장 → 나중에 열람). 빈 회의는 store가 skip.
            let record = Self.makeRecord(
                summary: summary ?? MeetingSummary(),
                segments: segments,
                topic: MeetingContext.shared.topic,
                duration: self.viewModel.recordingDuration
            )

            // 메모리에 남은 tail 세그먼트를 보고서에 기록. evict된 배치는 이미 .transcriptionNeedsFlush로
            // 기록됐으므로 중복되지 않는다(짧은 회의는 미evict라 전량이 여기서 기록됨).
            // 저장 record와 같은 normalized transcript를 써서 보고서도 chunk 단위로 보이지 않게 한다.
            for segment in record.transcript {
                self.reportService.appendSegment(segment)
            }
            self.reportService.appendSummarySection(summary?.markdown() ?? "")
            self.reportService.finalizeReport()

            let saved = MeetingStore.shared.save(record)

            if record.isEmpty || !saved {
                self.viewModel.errorMessage = "저장할 회의 내용이 없습니다."
            }
            self.mainWindowManager.show()
            MeetingContext.shared.clear()
        }
    }

    /// 전사 세그먼트 + 구조화 요약 → 저장용 MeetingRecord. 제목·길이를 해소한다.
    @MainActor
    static func makeRecord(summary: MeetingSummary, segments: [Segment], topic: String, duration: TimeInterval) -> MeetingRecord {
        let transcript = TranscriptNormalizer.normalize(segments)
        let title: String = {
            let t = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let topicTrimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            return topicTrimmed.isEmpty ? "회의 결과" : topicTrimmed
        }()
        let start = transcript.first?.timestamp ?? Date()
        // 회의 길이는 segment 타임스탬프로 계산(recordingDuration은 종료 시점에 0으로 들어올 수 있음).
        let meetingSeconds: TimeInterval
        if let first = transcript.first, let last = transcript.last {
            meetingSeconds = max(duration, last.timestamp.timeIntervalSince(first.timestamp) + last.duration)
        } else {
            meetingSeconds = duration
        }
        return MeetingRecord(
            title: title,
            startedAt: start,
            durationSeconds: meetingSeconds,
            topic: topic,
            summary: summary,
            transcript: transcript
        )
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // UserDefaults에서 저장된 모델 선택 읽기 (구버전/임시 기본 모델 → turbo 마이그레이션)
        let defaultModel = "openai_whisper-large-v3-v20240930_turbo"
        var savedVariant = UserDefaults.standard.string(forKey: "selectedModel") ?? defaultModel
        if [
            "openai_whisper-tiny",
            "openai_whisper-base",
            "openai_whisper-large-v3-v20240930_626MB",
            "openai_whisper-large-v3-v20240930_turbo_632MB",
        ].contains(savedVariant) {
            savedVariant = defaultModel
            UserDefaults.standard.set(defaultModel, forKey: "selectedModel")
        }
        Task {
            await viewModel.loadModel(variant: savedVariant)
        }
        // 런치 시 회의 목록 메인 윈도우를 띄워 저장된 회의를 바로 볼 수 있게 한다.
        mainWindowManager.show()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
