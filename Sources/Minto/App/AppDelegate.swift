import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    public let viewModel: TranscriptionViewModel
    public let floatingWindowManager: FloatingWindowManager
    public let meetingSetupManager: MeetingSetupWindowManager
    public let summaryWindowManager: MeetingSummaryWindowManager
    public let reportService = ReportService()

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
            onStart: { [weak self] topic, glossary in
                guard let self else { return }
                MeetingContext.shared.start(topic: topic, glossary: glossary)
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

            if let summary {
                let result = Self.buildResult(
                    summary: summary,
                    segments: segments,
                    topic: MeetingContext.shared.topic,
                    duration: self.viewModel.recordingDuration
                )
                self.summaryWindowManager.showResult(result)
            } else {
                self.summaryWindowManager.showFailed()
            }
            MeetingContext.shared.clear()
        }
    }

    /// 전사 세그먼트 + 구조화 요약 → 결과 화면 데이터. 타임스탬프는 첫 발화 기준 상대 MM:SS.
    @MainActor
    private static func buildResult(summary: MeetingSummary, segments: [Segment], topic: String, duration: TimeInterval) -> MeetingResult {
        let title: String = {
            let t = summary.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let topicTrimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            return topicTrimmed.isEmpty ? "회의 결과" : topicTrimmed
        }()

        let start = segments.first?.timestamp ?? Date()
        let lines = segments.map { seg in
            MeetingResult.TranscriptLine(
                time: Self.mmss(seg.timestamp.timeIntervalSince(start)),
                text: seg.text
            )
        }
        // 회의 길이는 segment 타임스탬프로 계산(recordingDuration은 종료 시점에 0으로 들어올 수 있음).
        let meetingSeconds: TimeInterval
        if let first = segments.first, let last = segments.last {
            meetingSeconds = max(duration, last.timestamp.timeIntervalSince(first.timestamp) + last.duration)
        } else {
            meetingSeconds = duration
        }
        let meta = "저장됨 · \(Self.durationText(meetingSeconds)) · 구간 \(segments.count)개"
        return MeetingResult(title: title, metaText: meta, summary: summary, transcript: lines)
    }

    private static func mmss(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60, s = total % 60
        return m > 0 ? "\(m)분 \(s)초" : "\(s)초"
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
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
