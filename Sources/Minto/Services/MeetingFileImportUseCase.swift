import Foundation
import UniformTypeIdentifiers
import os

public enum MeetingFileImportStage: String, Sendable, Equatable {
    case idle
    case analyzing
    case transcribing
    case correcting
    case summarizing
    case saving
    case completed
    case failed
    case cancelled

    public var title: String {
        switch self {
        case .idle:
            return "대기 중"
        case .analyzing:
            return "파일 분석 중"
        case .transcribing:
            return "전사 중"
        case .correcting:
            return "전사 다듬는 중"
        case .summarizing:
            return "회의록 정리 중"
        case .saving:
            return "저장 중"
        case .completed:
            return "가져오기 완료"
        case .failed:
            return "파일 가져오기 실패"
        case .cancelled:
            return "파일 가져오기 취소됨"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .analyzing, .transcribing, .correcting, .summarizing, .saving:
            return false
        }
    }
}

public struct MeetingFileImportState: Sendable, Equatable {
    public var stage: MeetingFileImportStage
    public var progress: Double
    public var fileName: String
    public var detailText: String
    public var errorMessage: String?
    public var record: MeetingRecord?

    public init(
        stage: MeetingFileImportStage = .idle,
        progress: Double = 0,
        fileName: String = "",
        detailText: String = "",
        errorMessage: String? = nil,
        record: MeetingRecord? = nil
    ) {
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
        self.fileName = fileName
        self.detailText = detailText
        self.errorMessage = errorMessage
        self.record = record
    }

    public var isRunning: Bool {
        switch stage {
        case .analyzing, .transcribing, .correcting, .summarizing, .saving:
            return true
        case .idle, .completed, .failed, .cancelled:
            return false
        }
    }

    public static let idle = MeetingFileImportState()
}

public enum MeetingFileImportError: LocalizedError, Sendable, Equatable {
    case sttNotReady(String)
    case emptyTranscript
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .sttNotReady(let message):
            return "음성 인식 엔진을 준비하지 못했어요: \(message)"
        case .emptyTranscript:
            return "전사된 내용이 없어요. 다른 파일을 선택하거나 음성이 포함되어 있는지 확인하세요."
        case .saveFailed:
            return "회의록을 저장하지 못했어요."
        }
    }
}

@MainActor
protocol MeetingFileImportSTTServicing: AnyObject {
    var modelState: ModelState { get }

    func loadEngine(_ engineID: SpeechEngineID) async
    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult
}

extension STTService: MeetingFileImportSTTServicing {}

@MainActor
protocol MeetingFileImportCorrecting: AnyObject {
    func correct(text: String, context: LLMCorrectionContext) async -> String?
    func correctBatch(texts: [String], context: LLMCorrectionContext) async -> [String?]?
}

extension LLMCorrectionService: MeetingFileImportCorrecting {}

@MainActor
protocol MeetingFileImportSummaryGenerating: AnyObject {
    func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary?
}

extension SummaryService: MeetingFileImportSummaryGenerating {}

@MainActor
protocol MeetingFileImportStoring: AnyObject {
    @discardableResult
    func save(_ record: MeetingRecord) -> MeetingSaveResult
}

extension MeetingStore: MeetingFileImportStoring {}

@MainActor
public final class MeetingFileImportUseCase: ObservableObject {
    public static let supportedContentTypes: [UTType] = FileAudioExtractor.supportedContentTypes
    public static let pendingImportFileNameKey = "pendingImportFileName"
    private static var activeImportCount = 0

    public static var isAnyImportRunning: Bool {
        activeImportCount > 0
    }

    internal static func resetImportStateForTesting(in defaults: UserDefaults = .standard) {
        activeImportCount = 0
        clearPendingImportMarker(in: defaults)
    }

    public static func pendingImportFileName(in defaults: UserDefaults = .standard) -> String? {
        normalizedImportMarkerFileName(defaults.string(forKey: pendingImportFileNameKey))
    }

    public static func clearPendingImportMarker(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingImportFileNameKey)
    }

    private static func normalizedImportMarkerFileName(_ fileName: String?) -> String? {
        let trimmedFileName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedFileName.isEmpty else { return nil }
        let lastPathComponent = (trimmedFileName as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? nil : lastPathComponent
    }

    @Published public private(set) var state: MeetingFileImportState = .idle

    private let extractor: any MeetingFileAudioExtracting
    private let sttService: any MeetingFileImportSTTServicing
    private let correctionService: any MeetingFileImportCorrecting
    private let summaryService: any MeetingFileImportSummaryGenerating
    private let store: any MeetingFileImportStoring
    private let chunkSeconds: TimeInterval
    private let maxConcurrentCorrections: Int
    private let now: () -> Date
    private let defaults: UserDefaults

    init(
        extractor: any MeetingFileAudioExtracting = FileAudioExtractor(),
        sttService: any MeetingFileImportSTTServicing = STTService(),
        correctionService: any MeetingFileImportCorrecting = LLMCorrectionService.shared,
        summaryService: any MeetingFileImportSummaryGenerating = SummaryService.shared,
        store: any MeetingFileImportStoring = MeetingStore.shared,
        chunkSeconds: TimeInterval = 30,
        maxConcurrentCorrections: Int = 3,
        now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = .standard
    ) {
        self.extractor = extractor
        self.sttService = sttService
        self.correctionService = correctionService
        self.summaryService = summaryService
        self.store = store
        self.chunkSeconds = max(1, chunkSeconds)
        self.maxConcurrentCorrections = max(1, maxConcurrentCorrections)
        self.now = now
        self.defaults = defaults
    }

    public func reset() {
        guard !state.isRunning else { return }
        setState(.idle)
    }

    @discardableResult
    public func importFile(
        _ url: URL,
        preferredTitle: String? = nil,
        topic: String? = nil,
        glossary: String = "",
        document: String = "",
        expectedSpeakerCount: Int? = nil,
        diarizeSpeakers: Bool = false,
        engineID: SpeechEngineID = SpeechEnginePreferences.selectedEngine(),
        shouldCorrect: Bool = LLMCorrectionService.shared.selectedProvider != .none
    ) async throws -> MeetingRecord {
        let fileName = url.lastPathComponent
        let title = resolvedTitle(url: url, preferredTitle: preferredTitle)
        let topicText = (topic ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        let startedAt = now()
        let summaryContext = SummaryGenerationContext(
            topic: topicText,
            glossary: glossary,
            runningSummary: "",
            document: document
        )
        var extractionDuration: TimeInterval = 0
        let correctionPipeline = ImportCorrectionPipeline(maxConcurrent: maxConcurrentCorrections)

        Log.importer.info("import start file=\(fileName, privacy: .public) engine=\(engineID.rawValue, privacy: .public)")
        do {
            update(.analyzing, progress: 0.05, fileName: fileName, detail: "음성 인식 엔진을 준비하고 있어요.")
            try await ensureSTTLoaded(engineID)
            try Task.checkCancellation()

            update(.analyzing, progress: 0.12, fileName: fileName, detail: "음성 트랙을 확인하고 있어요.")
            Log.importer.info("import extract start file=\(fileName, privacy: .public)")
            let extraction = try await extractor.extractChunks(
                from: url,
                chunkSeconds: chunkSeconds,
                onChunk: { [weak self] chunk in
                    guard let self else { throw CancellationError() }
                    try await self.importChunk(
                        chunk,
                        fileName: fileName,
                        startedAt: startedAt,
                        topic: topicText,
                        glossary: glossary,
                        document: document,
                        shouldCorrect: shouldCorrect,
                        pipeline: correctionPipeline
                    )
                }
            )
            extractionDuration = extraction.durationSeconds
            // 배치 버퍼에 남은 청크를 마지막 배치로 flush한다.
            if shouldCorrect {
                correctionPipeline.flushBatchBuffer(using: correctionService)
            }
            Log.importer.info("import extract done file=\(fileName, privacy: .public) segments=\(correctionPipeline.segments.count, privacy: .public)")
            try Task.checkCancellation()

            guard !correctionPipeline.segments.isEmpty else { throw MeetingFileImportError.emptyTranscript }

            if correctionPipeline.totalCorrectionCount > 0 {
                let pendingCount = correctionPipeline.totalCorrectionCount
                update(
                    .correcting,
                    progress: 0.82,
                    fileName: fileName,
                    detail: "전사 다듬는 중 0/\(pendingCount)"
                )
                Log.importer.info("import correction drain start file=\(fileName, privacy: .public) pending=\(pendingCount, privacy: .public)")
                await withTaskCancellationHandler {
                    await correctionPipeline.drain { [weak self] done, total in
                        self?.update(
                            .correcting,
                            progress: 0.82 + 0.03 * Double(done) / Double(max(1, total)),
                            fileName: fileName,
                            detail: "전사 다듬는 중 \(done)/\(total)"
                        )
                    }
                } onCancel: {
                    Task { @MainActor in correctionPipeline.cancelPendingCorrections() }
                }
                Log.importer.info("import corrections done file=\(fileName, privacy: .public) corrected=\(correctionPipeline.correctedCount, privacy: .public) fallback=\(correctionPipeline.fallbackCount, privacy: .public)")
                try Task.checkCancellation()
            }

            let segments = correctionPipeline.segments
            update(.summarizing, progress: 0.86, fileName: fileName, detail: "회의 내용을 정리하고 있어요.")
            Log.importer.info("import summarize start file=\(fileName, privacy: .public)")
            let summary = await summaryService.generateFinal(
                transcript: Self.transcriptText(from: segments, startedAt: startedAt),
                context: summaryContext
            ) ?? MeetingSummary()
            try Task.checkCancellation()

            update(.saving, progress: 0.96, fileName: fileName, detail: "회의 목록에 저장하고 있어요.")
            Log.importer.info("import save start file=\(fileName, privacy: .public)")
            var record = MeetingRecordFactory.makeRecord(
                summary: summary,
                segments: segments,
                topic: topicText,
                preferredTitle: title,
                fallbackTitle: "파일 회의록",
                duration: extractionDuration,
                startedAt: startedAt
            )
            if diarizeSpeakers {
                try Task.checkCancellation()
                update(.saving, progress: 0.97, fileName: fileName, detail: "화자를 구분하고 있어요.")
                record.transcript = try await assignSpeakersIfNeeded(
                    transcript: record.transcript,
                    audioFileURL: url,
                    meetingStart: record.startedAt,
                    expectedSpeakerCount: expectedSpeakerCount,
                    fileName: fileName
                )
                try Task.checkCancellation()
            }
            guard store.save(record) == .success else { throw MeetingFileImportError.saveFailed }

            Log.importer.info("import success file=\(fileName, privacy: .public)")
            setState(MeetingFileImportState(
                stage: .completed,
                progress: 1,
                fileName: fileName,
                detailText: "'\(record.title)'이 목록에 추가됐어요.",
                record: record
            ))
            return record
        } catch is CancellationError {
            correctionPipeline.cancelPendingCorrections()
            Log.importer.info("import cancelled file=\(fileName, privacy: .public)")
            setState(MeetingFileImportState(
                stage: .cancelled,
                progress: state.progress,
                fileName: fileName,
                detailText: "파일 가져오기를 취소했어요."
            ))
            throw CancellationError()
        } catch {
            correctionPipeline.cancelPendingCorrections()
            let errorCase = String(describing: error).components(separatedBy: "(").first ?? String(describing: error)
            let nsError = error as NSError
            Log.importer.error("import failed file=\(fileName, privacy: .public) error=\(errorCase, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            setState(MeetingFileImportState(
                stage: .failed,
                progress: state.progress,
                fileName: fileName,
                detailText: "파일을 회의록으로 만들지 못했어요.",
                errorMessage: error.localizedDescription
            ))
            throw error
        }
    }

    private func assignSpeakersIfNeeded(
        transcript: [Segment],
        audioFileURL: URL,
        meetingStart: Date,
        expectedSpeakerCount: Int?,
        fileName: String
    ) async throws -> [Segment] {
        let provider: FluidAudioOfflineDiarizationProvider
        let expectedSpeakers = if let expectedSpeakerCount, expectedSpeakerCount > 0 {
            String(expectedSpeakerCount)
        } else {
            "auto"
        }
        if let expectedSpeakerCount, expectedSpeakerCount > 0 {
            provider = FluidAudioOfflineDiarizationProvider(exactSpeakerCount: expectedSpeakerCount)
        } else {
            provider = FluidAudioOfflineDiarizationProvider()
        }
        Log.diarization.info(
            "import diarization assign start file=\(fileName, privacy: .public) expectedSpeakers=\(expectedSpeakers, privacy: .public)"
        )
        do {
            let diarizedSegments = try await provider.diarize(audioFileURL: audioFileURL)
            let labeledTranscript = TranscriptSpeakerMatcher().assignSpeakers(
                diarizedSegments: diarizedSegments,
                transcript: transcript,
                meetingStart: meetingStart
            )
            let labeledCount = labeledTranscript.filter { $0.speaker != nil }.count
            Log.diarization.info(
                "import diarization assign complete file=\(fileName, privacy: .public) transcriptSegments=\(labeledTranscript.count, privacy: .public) labeledSegments=\(labeledCount, privacy: .public)"
            )
            return labeledTranscript
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let errorCase = String(describing: error).components(separatedBy: "(").first ?? String(describing: error)
            let nsError = error as NSError
            Log.diarization.error(
                "import diarization failed file=\(fileName, privacy: .public) expectedSpeakers=\(expectedSpeakers, privacy: .public) error=\(errorCase, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            return transcript
        }
    }

    private func importChunk(
        _ chunk: FileAudioChunk,
        fileName: String,
        startedAt: Date,
        topic: String,
        glossary: String,
        document: String,
        shouldCorrect: Bool,
        pipeline: ImportCorrectionPipeline
    ) async throws {
        try Task.checkCancellation()
        let progress = importProgress(for: chunk)
        update(
            .transcribing,
            progress: progress,
            fileName: fileName,
            detail: "전사 중 \(chunkLabel(chunk))"
        )

        let rawResult = try await sttService.transcribe(pcmSamples: chunk.samples)
        try Task.checkCancellation()
        let rawText = rawResult.segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }

        // 문맥 스냅샷은 현재 청크를 추가하기 전에 떠야 "직전" 원문들만 담긴다.
        let correctionContext = LLMCorrectionContext(
            topic: topic,
            glossary: glossary,
            previousText: pipeline.contextSnapshot(),
            runningSummary: "",
            document: document
        )
        let segment = Segment(
            id: rawResult.segment.id,
            text: rawText,
            timestamp: startedAt.addingTimeInterval(chunk.startSeconds),
            duration: chunk.durationSeconds,
            speaker: rawResult.segment.speaker,
            words: rawResult.segment.words
        )
        if shouldCorrect {
            pipeline.appendRawAndEnqueue(
                segment,
                context: correctionContext,
                using: correctionService
            )
        } else {
            pipeline.appendRaw(segment)
        }
    }

    private func ensureSTTLoaded(_ engineID: SpeechEngineID) async throws {
        if case .loaded = sttService.modelState { return }

        await sttService.loadEngine(engineID)
        guard case .loaded = sttService.modelState else {
            let message: String
            if case .failed(let reason) = sttService.modelState {
                message = reason
            } else {
                message = "\(sttService.modelState)"
            }
            throw MeetingFileImportError.sttNotReady(message)
        }
    }

    private func update(
        _ stage: MeetingFileImportStage,
        progress: Double,
        fileName: String,
        detail: String
    ) {
        setState(MeetingFileImportState(
            stage: stage,
            progress: progress,
            fileName: fileName,
            detailText: detail
        ))
    }

    private func setState(_ nextState: MeetingFileImportState) {
        let wasRunning = state.isRunning
        state = nextState
        Self.updateActiveImportCount(wasRunning: wasRunning, isRunning: nextState.isRunning)
        updatePendingImportMarker(for: nextState)
    }

    private static func updateActiveImportCount(wasRunning: Bool, isRunning: Bool) {
        switch (wasRunning, isRunning) {
        case (false, true):
            activeImportCount += 1
        case (true, false):
            activeImportCount = max(0, activeImportCount - 1)
        case (false, false), (true, true):
            break
        }
    }

    internal func updatePendingImportMarker(for nextState: MeetingFileImportState) {
        if nextState.isRunning {
            if let fileName = Self.normalizedImportMarkerFileName(nextState.fileName) {
                defaults.set(fileName, forKey: Self.pendingImportFileNameKey)
            }
        } else if !nextState.isRunning {
            Self.clearPendingImportMarker(in: defaults)
        }
    }

    private func resolvedTitle(url: URL, preferredTitle: String?) -> String {
        let preferred = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty { return preferred }
        let fileTitle = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileTitle.isEmpty ? "파일 회의록" : fileTitle
    }

    private func importProgress(for chunk: FileAudioChunk) -> Double {
        if let total = chunk.estimatedTotalChunks, total > 0 {
            return 0.12 + (0.68 * Double(chunk.index) / Double(total))
        }
        return min(0.12 + (Double(chunk.index) * 0.02), 0.80)
    }

    private func chunkLabel(_ chunk: FileAudioChunk) -> String {
        if let total = chunk.estimatedTotalChunks, total > 0 {
            return "\(chunk.index + 1)/\(total)"
        }
        return "\(chunk.index + 1)번째 구간"
    }

    static func makeChunks(samples: [Float], chunkSeconds: TimeInterval, sampleRate: Double) -> [FileAudioChunk] {
        FileAudioExtractor.makeChunks(samples: samples, chunkSeconds: chunkSeconds, sampleRate: sampleRate)
    }

    static func transcriptText(from segments: [Segment], startedAt: Date) -> String {
        segments.map { segment in
            let seconds = max(0, Int(segment.timestamp.timeIntervalSince(startedAt).rounded()))
            return String(format: "[%02d:%02d] %@", seconds / 60, seconds % 60, segment.text)
        }
        .joined(separator: "\n")
    }
}

/// 파일 임포트 전사 교정 파이프라인.
///
/// STT는 ANE-bound라 직렬을 유지하고, 네트워크 대기인 LLM 교정만 동시 상한 안에서
/// 백그라운드로 겹친다. segment 순서는 추가 시점 index로 고정되므로 교정 완료 순서와
/// 무관하게 transcript 순서가 보존된다. 교정 실패/취소는 원문 유지(fail-soft).
///
/// 배치 모드: appendRawAndEnqueue로 청크를 누적하고, batchSize개가 차면 자동으로
/// correctBatch를 호출한다. 추출 완료 후 flushBatchBuffer()로 잔여 청크를 처리한다.
@MainActor
final class ImportCorrectionPipeline {
    private(set) var segments: [Segment] = []
    private var rawTexts: [String] = []
    private var correctionTasks: [Task<Void, Never>] = []
    private let maxConcurrent: Int
    private var runningCount = 0
    private var slotWaiters: [CheckedContinuation<Bool, Never>] = []
    private(set) var correctedCount = 0
    private(set) var fallbackCount = 0

    // 배치 버퍼: (segmentIndex, rawText, context)
    private struct BatchEntry {
        let segmentIndex: Int
        let rawText: String
        let context: LLMCorrectionContext
    }
    private var batchBuffer: [BatchEntry] = []
    static let defaultBatchSize = 3

    var totalCorrectionCount: Int { correctionTasks.count }

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 직전 원문들로 교정 문맥을 만든다. 교정문 대기 없이 즉시 사용할 수 있어
    /// 교정 호출 간 직렬 의존성이 생기지 않는다.
    func contextSnapshot(limit: Int = 5) -> String {
        rawTexts.suffix(limit).joined(separator: "\n")
    }

    func appendRaw(_ segment: Segment) -> Int {
        segments.append(segment)
        rawTexts.append(segment.text)
        return segments.count - 1
    }

    /// 원문을 배치 버퍼에 추가하고, batchSize에 도달하면 즉시 배치를 디스패치한다.
    func appendRawAndEnqueue(
        _ segment: Segment,
        context: LLMCorrectionContext,
        batchSize: Int = defaultBatchSize,
        using service: any MeetingFileImportCorrecting
    ) {
        let index = appendRaw(segment)
        batchBuffer.append(BatchEntry(segmentIndex: index, rawText: segment.text, context: context))
        if batchBuffer.count >= batchSize {
            dispatchBatch(entries: batchBuffer, using: service)
            batchBuffer.removeAll()
        }
    }

    /// 추출 완료 후 버퍼에 남은 청크를 마지막 배치로 디스패치한다.
    func flushBatchBuffer(using service: any MeetingFileImportCorrecting) {
        guard !batchBuffer.isEmpty else { return }
        dispatchBatch(entries: batchBuffer, using: service)
        batchBuffer.removeAll()
    }

    /// 단건 교정 디스패치. 제품 임포트 경로는 배치(appendRawAndEnqueue)만 쓰고,
    /// 이 경로는 limiter 계약을 단건 단위로 검증하는 테스트가 사용한다.
    func dispatchCorrection(
        at index: Int,
        rawText: String,
        context: LLMCorrectionContext,
        using service: any MeetingFileImportCorrecting
    ) {
        // [weak self]는 순환참조 방지용이고 격리는 @MainActor 상속이다. guard let 이후의
        // 강참조 덕에 task가 하나라도 살아 있는 동안 pipeline은 해제되지 않는다.
        let task = Task { [weak self] in
            guard let self else { return }
            guard await self.acquireSlot() else {
                // 취소로 slot을 받지 못한 경우 — slot을 쥔 적이 없으므로 release 없이 끝낸다.
                self.fallbackCount += 1
                return
            }
            defer { self.releaseSlot() }
            guard !Task.isCancelled else {
                self.fallbackCount += 1
                return
            }
            let corrected = await service.correct(text: rawText, context: context)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty
            if let corrected {
                self.replaceText(at: index, with: corrected)
                self.correctedCount += 1
            } else {
                self.fallbackCount += 1
            }
        }
        correctionTasks.append(task)
    }

    /// 배치 단위로 교정을 디스패치한다. slot 1개를 점유(배치 = 호출 1회).
    private func dispatchBatch(
        entries: [BatchEntry],
        using service: any MeetingFileImportCorrecting
    ) {
        guard !entries.isEmpty else { return }
        // 배치의 문맥은 첫 청크의 context를 사용한다(직전 원문 5개 스냅샷).
        let batchContext = entries[0].context
        let texts = entries.map(\.rawText)
        let indices = entries.map(\.segmentIndex)

        let task = Task { [weak self] in
            guard let self else { return }
            guard await self.acquireSlot() else {
                self.fallbackCount += entries.count
                return
            }
            defer { self.releaseSlot() }
            guard !Task.isCancelled else {
                self.fallbackCount += entries.count
                return
            }
            let results = await service.correctBatch(texts: texts, context: batchContext)
            // 배치 파싱 실패 시 그 배치 전체 원문 유지
            guard let results else {
                self.fallbackCount += entries.count
                return
            }
            for (offset, correctedItem) in results.enumerated() {
                guard offset < indices.count else { break }
                let segIndex = indices[offset]
                if let corrected = correctedItem?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty {
                    self.replaceText(at: segIndex, with: corrected)
                    self.correctedCount += 1
                } else {
                    self.fallbackCount += 1
                }
            }
        }
        correctionTasks.append(task)
    }

    func drain(onProgress: @MainActor (Int, Int) -> Void) async {
        let total = correctionTasks.count
        for (completed, task) in correctionTasks.enumerated() {
            // 취소 시 남은 교정을 기다리지 않는다. 진행 중 task는 fail-soft로 알아서 끝나고,
            // 호출부의 checkCancellation이 cancelled 경로로 빠지므로 결과는 버려진다.
            if Task.isCancelled { break }
            await task.value
            onProgress(completed + 1, total)
        }
    }

    func cancelPendingCorrections() {
        for task in correctionTasks {
            task.cancel()
        }
        // slot 대기자는 실행 중 task가 해제해 줄 때까지 잠들어 있으므로 직접 깨워야
        // 취소가 즉시 전파된다. false로 재개된 task는 slot 없이 fallback으로 끝난다.
        let waiters = slotWaiters
        slotWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: false)
        }
    }

    private func replaceText(at index: Int, with text: String) {
        guard segments.indices.contains(index) else { return }
        let original = segments[index]
        segments[index] = Segment(
            id: original.id,
            text: text,
            timestamp: original.timestamp,
            duration: original.duration,
            speaker: original.speaker,
            words: original.words
        )
    }

    /// slot을 얻으면 true, 취소로 깨워졌으면 false를 반환한다.
    private func acquireSlot() async -> Bool {
        guard !Task.isCancelled else { return false }
        if runningCount < maxConcurrent {
            runningCount += 1
            return true
        }
        // true로 재개되면 releaseSlot()이 slot을 양도한 상태이므로 runningCount를 늘리지 않는다.
        return await withCheckedContinuation { slotWaiters.append($0) }
    }

    private func releaseSlot() {
        if slotWaiters.isEmpty {
            runningCount -= 1
        } else {
            // decrement 후 resume 사이에 새 acquire가 끼어들어 상한을 넘는 것을 막기 위해
            // count를 유지한 채 대기자에게 slot을 양도한다.
            slotWaiters.removeFirst().resume(returning: true)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
