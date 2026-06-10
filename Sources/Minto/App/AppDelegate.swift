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
        onShowOverlay: { [weak self] in self?.floatingWindowManager.show() },
        onStopRecording: { [weak self] in self?.handleStopRecording() }
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
            onStart: { [weak self] topic, glossary, document, inputMode in
                guard let self else { return }
                MeetingContext.shared.start(topic: topic, glossary: glossary, document: document)
                self.reportService.startNewReport(startedAt: Date())
                self.viewModel.startNewRecordingSession(inputMode: inputMode)
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

            let saveResult = MeetingStore.shared.save(record)

            switch saveResult {
            case .skippedEmpty:
                // (a) 빈 회의: 데이터가 없으므로 맥락 초기화는 정상 진행.
                self.viewModel.errorMessage = "저장할 회의 내용이 없습니다."
                MeetingContext.shared.clear()
            case .success:
                // 정상 저장: 맥락 초기화.
                MeetingContext.shared.clear()
            case .failed:
                // (b) 내용은 있지만 디스크/인코딩 실패: 복구 파일을 남기고 맥락을 초기화하지 않는다.
                MeetingSaveRecovery.writeRecoveryFile(for: record)
                self.viewModel.errorMessage = "회의 저장에 실패했어요. 전사 복구 사본을 보관해 두었습니다."
                // MeetingContext는 clear하지 않는다 — 다음 녹음 시작 시 덮어써질 때까지 데이터를 유지해 소실을 막는다.
            }
            self.mainWindowManager.show()
        }
    }

    /// 전사 세그먼트 + 구조화 요약 → 저장용 MeetingRecord. 제목·길이를 해소한다.
    @MainActor
    static func makeRecord(summary: MeetingSummary, segments: [Segment], topic: String, duration: TimeInterval) -> MeetingRecord {
        MeetingRecordFactory.makeRecord(
            summary: summary,
            segments: segments,
            topic: topic,
            duration: duration
        )
    }

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        LLMSummarySettingsService.shared.migrateIfNeeded(from: LLMCorrectionService.shared.selectedProvider)
        SpeechEnginePreferences.normalizeLegacyValues()
        Task {
            let savedEngine = SpeechEnginePreferences.selectedEngine()
            let availability = await STTService.engineAvailability(for: savedEngine)
            if availability.isSelectable {
                await viewModel.loadSpeechEngine(savedEngine)
            } else {
                UserDefaults.standard.set(
                    SpeechEngineID.defaultEngine.rawValue,
                    forKey: SpeechEnginePreferences.selectedEngineKey
                )
                await viewModel.loadSpeechEngine(.defaultEngine)
            }
        }
        // 런치 시 회의 목록 메인 윈도우를 띄워 저장된 회의를 바로 볼 수 있게 한다.
        mainWindowManager.show()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
