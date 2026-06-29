import AppKit
import SwiftUI
import os

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
            onStart: { [weak self] topic, glossary, document, inputMode, calendarEventIdentifier in
                guard let self else { return }
                MeetingContext.shared.start(
                    topic: topic,
                    glossary: glossary,
                    document: document,
                    calendarEventIdentifier: calendarEventIdentifier
                )
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
            // 방법 A: 저장 시 아카이브 오디오에 offline VBx를 재실행해 화자를 확정한다(라이브 카운트에 묶지 않음).
            // 라이브 diar 성공 여부와 무관하게 아카이브 오디오가 있으면 실행(VBx가 authoritative). 편집 라벨은 보존.
            let reconciled: (segments: [Segment], speakerEmbeddings: [MeetingRecord.MeetingSpeakerEmbedding])?
            if let audioFileName = self.viewModel.lastArchivedAudioFileName {
                Log.diarization.info(
                    "live finalize reconcile start transcriptSegments=\(segments.count, privacy: .public)"
                )
                let audioURL = RecordingAudioArchiver.recordingsDirectory
                    .appendingPathComponent(audioFileName)
                let finalizeUseCase = LiveDiarizationFinalizeUseCase(
                    diarizer: FluidAudioOfflineDiarizationProvider()
                )
                let enrolled = VoiceprintStore.shared.usablePrints(
                    forModelID: FluidAudioOfflineDiarizationProvider.embeddingModelID
                )
                let meetingStart = self.viewModel.transcriptTimelineStartDate
                    ?? segments.first?.timestamp
                    ?? Date()
                let result = try? await finalizeUseCase.finalize(
                    audioFileURL: audioURL,
                    liveTranscript: segments,
                    editedSegmentIds: self.viewModel.editedSpeakerSegmentIds,
                    enrolledVoiceprints: enrolled,
                    meetingStart: meetingStart,
                    expectedSpeakerCount: nil
                )
                Log.diarization.info(
                    "live finalize reconcile complete segments=\(result?.segments.count ?? segments.count, privacy: .public) speakerEmbeddings=\(result?.speakerEmbeddings.count ?? 0, privacy: .public)"
                )
                reconciled = result
            } else {
                Log.diarization.info(
                    "live finalize skipped(no archived audio) transcriptSegments=\(segments.count, privacy: .public)"
                )
                reconciled = nil
            }
            let recordSegments = reconciled?.segments ?? segments
            let summaryGlossary = summary == nil ? nil : MeetingContext.shared.glossary

            // 회의 기록을 영속화(요약이 없어도 전사가 있으면 저장 → 나중에 열람). 빈 회의는 store가 skip.
            var record = Self.makeRecord(
                summary: summary ?? MeetingSummary(),
                segments: recordSegments,
                topic: MeetingContext.shared.topic,
                duration: self.viewModel.recordingDuration,
                summaryGlossary: summaryGlossary,
                document: MeetingContext.shared.document,
                calendarEventIdentifier: MeetingContext.shared.calendarEventIdentifier,
                audioFileName: self.viewModel.lastArchivedAudioFileName
            )
            if let speakerEmbeddings = reconciled?.speakerEmbeddings,
               !speakerEmbeddings.isEmpty {
                record.speakerEmbeddings = speakerEmbeddings
            }

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
                // 참조하는 record가 없으므로 보존된 오디오도 같이 정리한다.
                if let audioFileName = record.audioFileName {
                    RecordingAudioArchiver.removeArchivedFile(named: audioFileName)
                }
                self.viewModel.errorMessage = "저장할 회의 내용이 없어요."
                MeetingContext.shared.clear()
            case .success:
                // 정상 저장: 맥락 초기화.
                MeetingContext.shared.clear()
            case .failed:
                // (b) 내용은 있지만 디스크/인코딩 실패: 복구 파일을 남기고 맥락을 초기화하지 않는다.
                MeetingSaveRecovery.writeRecoveryFile(for: record)
                self.viewModel.errorMessage = "회의 저장에 실패했어요. 전사 복구 사본을 보관해 두었어요."
                // MeetingContext는 clear하지 않는다 — 다음 녹음 시작 시 덮어써질 때까지 데이터를 유지해 소실을 막는다.
            }
            self.mainWindowManager.show()
        }
    }

    /// 전사 세그먼트 + 구조화 요약 → 저장용 MeetingRecord. 제목·길이를 해소한다.
    @MainActor
    static func makeRecord(
        summary: MeetingSummary,
        segments: [Segment],
        topic: String,
        duration: TimeInterval,
        summaryGlossary: String? = nil,
        document: String? = nil,
        calendarEventIdentifier: String? = nil,
        audioFileName: String? = nil
    ) -> MeetingRecord {
        MeetingRecordFactory.makeRecord(
            summary: summary,
            segments: segments,
            topic: topic,
            duration: duration,
            summaryGlossary: summaryGlossary,
            document: document,
            calendarEventIdentifier: calendarEventIdentifier,
            audioFileName: audioFileName
        )
    }

    @MainActor
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        Log.app.info("app launched version=\(version, privacy: .public) build=\(build, privacy: .public)")

        NSApp.setActivationPolicy(.regular)
        // migrateIfNeeded(교정 → 요약 초기 복사)를 먼저 실행한 뒤,
        // follow 시맨틱 마이그레이션을 수행해야 한다.
        // 순서 중요: migrateIfNeeded가 override를 먼저 채워야 follow 판단이 올바르다.
        LLMSummarySettingsService.shared.migrateIfNeeded(from: LLMCorrectionService.shared.selectedProvider)
        LLMSummarySettingsService.shared.migrateToFollowSemanticIfNeeded()
        MeetingSearchAnswerSettingsService.shared.migrateToFollowSemanticIfNeeded()
        SpeechEnginePreferences.normalizeLegacyValues()
        // Silero VAD가 선택돼 있고 모델(~1MB)이 없으면 백그라운드로 받아 둔다.
        // 준비 전 녹음은 factory가 Energy VAD로 fail-soft 한다.
        if VADEnginePreferences.selectedEngine() == .silero {
            SileroVADModelStore.shared.prepareIfNeeded()
        }
        // 보관 기간이 지난 녹음 오디오 정리(파일 IO라 백그라운드).
        Task.detached(priority: .utility) {
            let removedCount = RecordingAudioArchiver.cleanupExpired()
            if removedCount > 0 {
                Log.audio.info("recording audio cleanup removed=\(removedCount, privacy: .public)")
            }
        }
        Task {
            let savedEngine = SpeechEnginePreferences.selectedEngine()
            let availability = await STTService.engineAvailability(for: savedEngine)
            if availability.isSelectable {
                Log.app.info("stt engine selected=\(savedEngine.rawValue, privacy: .public)")
                await viewModel.loadSpeechEngine(savedEngine)
            } else {
                let fallback = SpeechEngineID.defaultEngine
                Log.app.info("stt engine unavailable=\(savedEngine.rawValue, privacy: .public) fallback=\(fallback.rawValue, privacy: .public)")
                UserDefaults.standard.set(
                    fallback.rawValue,
                    forKey: SpeechEnginePreferences.selectedEngineKey
                )
                await viewModel.loadSpeechEngine(fallback)
            }
        }
        // 복원 전에 GlossaryStore를 초기화해 회의 변경 구독을 먼저 배선한다 —
        // 늦으면 복원된 회의가 "기존 회의"로 취급돼 용어 후보 추출을 놓친다.
        _ = GlossaryStore.shared
        // 이전 저장 실패 복구본이 있으면 자동 복원한다.
        // MeetingStore.shared는 @MainActor static let이라 이 첫 접근에서
        // sync 초기화(reload 포함)가 완료된 뒤 복원이 진행된다.
        Task {
            let (restored, failed) = MeetingSaveRecovery.restorePendingRecords(into: MeetingStore.shared)
            if restored > 0 {
                Log.store.info("복구 완료: \(restored, privacy: .public)건")
            }
            if failed > 0 {
                Log.store.error("복원 실패 \(failed, privacy: .public)건, 파일 유지")
            }
        }

        // 런치 시 회의 목록 메인 윈도우를 띄워 저장된 회의를 바로 볼 수 있게 한다.
        mainWindowManager.show()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    public func applicationWillTerminate(_ notification: Notification) {
        ClaudeCodeCLIProvider.terminateRunningProcesses()
    }

    @MainActor
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MeetingFileImportUseCase.isAnyImportRunning else {
            ClaudeCodeCLIProvider.terminateRunningProcesses()
            return .terminateNow
        }

        Log.importer.info("terminate requested during active import")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "파일 가져오기가 진행 중이에요. 지금 종료하면 가져오기가 사라져요."
        alert.addButton(withTitle: "계속 가져오기")
        alert.addButton(withTitle: "종료")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            Log.importer.info("terminate accepted during active import")
            // 종료를 확정하면 pending marker를 남겨 다음 실행 때 안내 카드로 알려준다.
            ClaudeCodeCLIProvider.terminateRunningProcesses()
            return .terminateNow
        }
        Log.importer.info("terminate cancelled during active import")
        return .terminateCancel
    }
}
