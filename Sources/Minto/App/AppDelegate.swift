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

            // 메모리에 남은 tail 세그먼트를 보고서에 기록. evict된 배치는 이미 .transcriptionNeedsFlush로
            // 기록됐으므로 중복되지 않는다(짧은 회의는 미evict라 전량이 여기서 기록됨).
            for segment in self.viewModel.committedSegments {
                self.reportService.appendSegment(segment)
            }
            // 보고서 끝에 요약 섹션 추가.
            if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let summarySegment = Segment(
                    text: "\n\n---\n## 회의 요약\n\n\(summary)",
                    timestamp: Date(),
                    duration: 0
                )
                self.reportService.appendSegment(summarySegment)
            }
            self.reportService.finalizeReport()

            self.summaryWindowManager.showResult(summary: summary)
            MeetingContext.shared.clear()
        }
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
