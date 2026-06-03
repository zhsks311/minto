import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    public let viewModel: TranscriptionViewModel
    public let floatingWindowManager: FloatingWindowManager
    public let meetingSetupManager: MeetingSetupWindowManager
    public let summaryWindowManager: MeetingSummaryWindowManager
    public let reportService = ReportService()
    /// 회의 목록·상세 메인 윈도우. "새 회의 시작"은 기존 시작 흐름을 탄다.
    @MainActor public lazy var mainWindowManager = MainWindowManager(
        onNewMeeting: { [weak self] in self?.requestStartSession() }
    )

    override init() {
        let (vm, floatManager, setupManager, summaryManager) = MainActor.assumeIsolated {
            let vm = TranscriptionViewModel()
            return (vm, FloatingWindowManager(viewModel: vm), MeetingSetupWindowManager(), MeetingSummaryWindowManager())
        }
        viewModel = vm
        floatingWindowManager = floatManager
        meetingSetupManager = setupManager
        summaryWindowManager = summaryManager
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
                self.floatingWindowManager.show()
            },
            onCancel: {}
        )
    }

    /// "녹음 종료" → 녹음 정지 → 요약 창을 로딩으로 띄움 → (마지막 교정 완료 후) 최종 요약 생성
    /// → 보고서에 tail·요약 기록 후 마감 → 요약 표시 → 회의 맥락 초기화.
    @MainActor
    public func handleStopRecording() {
        viewModel.stopRecording()
        floatingWindowManager.hide()
        summaryWindowManager.showLoading()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let summary = await self.viewModel.finalizeMeeting()
            let segments = self.viewModel.committedSegments

            // 메모리에 남은 tail 세그먼트를 보고서에 기록. evict된 배치는 이미 .transcriptionNeedsFlush로
            // 기록됐으므로 중복되지 않는다(짧은 회의는 미evict라 전량이 여기서 기록됨).
            for segment in segments {
                self.reportService.appendSegment(segment)
            }
            self.reportService.appendSummarySection(summary?.markdown() ?? "")
            self.reportService.finalizeReport()

            // 회의 기록을 영속화(요약이 없어도 전사가 있으면 저장 → 나중에 열람). 빈 회의는 store가 skip.
            let record = Self.makeRecord(
                summary: summary ?? MeetingSummary(),
                segments: segments,
                topic: MeetingContext.shared.topic,
                duration: self.viewModel.recordingDuration
            )
            MeetingStore.shared.save(record)

            if record.isEmpty {
                self.summaryWindowManager.showFailed()
            } else {
                self.summaryWindowManager.showResult(MeetingResult.from(record))
            }
            MeetingContext.shared.clear()
        }
    }

    /// 전사 세그먼트 + 구조화 요약 → 저장용 MeetingRecord. 제목·길이를 해소한다.
    @MainActor
    static func makeRecord(summary: MeetingSummary, segments: [Segment], topic: String, duration: TimeInterval) -> MeetingRecord {
        let title: String = {
            let t = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let topicTrimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            return topicTrimmed.isEmpty ? "회의 결과" : topicTrimmed
        }()
        let start = segments.first?.timestamp ?? Date()
        // 회의 길이는 segment 타임스탬프로 계산(recordingDuration은 종료 시점에 0으로 들어올 수 있음).
        let meetingSeconds: TimeInterval
        if let first = segments.first, let last = segments.last {
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
            transcript: segments
        )
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // UserDefaults에서 저장된 모델 선택 읽기 (구버전 small → turbo 마이그레이션)
        let defaultModel = "openai_whisper-large-v3-v20240930_turbo"
        var savedVariant = UserDefaults.standard.string(forKey: "selectedModel") ?? defaultModel
        if savedVariant == "openai_whisper-small" {
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
