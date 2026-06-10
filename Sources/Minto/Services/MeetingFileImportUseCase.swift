import Foundation
import UniformTypeIdentifiers

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
            return "회의록 생성 완료"
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
            return "음성 인식 엔진을 준비하지 못했습니다: \(message)"
        case .emptyTranscript:
            return "전사된 내용이 없습니다. 다른 파일을 선택하거나 음성이 포함되어 있는지 확인하세요."
        case .saveFailed:
            return "회의록을 저장하지 못했습니다."
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

    @Published public private(set) var state: MeetingFileImportState = .idle

    private let extractor: any MeetingFileAudioExtracting
    private let sttService: any MeetingFileImportSTTServicing
    private let correctionService: any MeetingFileImportCorrecting
    private let summaryService: any MeetingFileImportSummaryGenerating
    private let store: any MeetingFileImportStoring
    private let chunkSeconds: TimeInterval
    private let now: () -> Date

    init(
        extractor: any MeetingFileAudioExtracting = FileAudioExtractor(),
        sttService: any MeetingFileImportSTTServicing = STTService(),
        correctionService: any MeetingFileImportCorrecting = LLMCorrectionService.shared,
        summaryService: any MeetingFileImportSummaryGenerating = SummaryService.shared,
        store: any MeetingFileImportStoring = MeetingStore.shared,
        chunkSeconds: TimeInterval = 30,
        now: @escaping () -> Date = Date.init
    ) {
        self.extractor = extractor
        self.sttService = sttService
        self.correctionService = correctionService
        self.summaryService = summaryService
        self.store = store
        self.chunkSeconds = max(1, chunkSeconds)
        self.now = now
    }

    public func reset() {
        guard !state.isRunning else { return }
        state = .idle
    }

    @discardableResult
    public func importFile(
        _ url: URL,
        preferredTitle: String? = nil,
        topic: String? = nil,
        glossary: String = "",
        document: String = "",
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
        var segments: [Segment] = []
        var previousContext: [String] = []

        do {
            update(.analyzing, progress: 0.05, fileName: fileName, detail: "음성 인식 엔진을 준비하고 있습니다.")
            try await ensureSTTLoaded(engineID)
            try Task.checkCancellation()

            update(.analyzing, progress: 0.12, fileName: fileName, detail: "음성 트랙을 확인하고 있습니다.")
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
                        segments: &segments,
                        previousContext: &previousContext
                    )
                }
            )
            extractionDuration = extraction.durationSeconds
            try Task.checkCancellation()

            guard !segments.isEmpty else { throw MeetingFileImportError.emptyTranscript }

            update(.summarizing, progress: 0.86, fileName: fileName, detail: "회의 내용을 정리하고 있습니다.")
            let summary = await summaryService.generateFinal(
                transcript: Self.transcriptText(from: segments, startedAt: startedAt),
                context: summaryContext
            ) ?? MeetingSummary()
            try Task.checkCancellation()

            update(.saving, progress: 0.96, fileName: fileName, detail: "회의 목록에 저장하고 있습니다.")
            let record = MeetingRecordFactory.makeRecord(
                summary: summary,
                segments: segments,
                topic: topicText,
                preferredTitle: title,
                fallbackTitle: "파일 회의록",
                duration: extractionDuration,
                startedAt: startedAt
            )
            guard store.save(record) == .success else { throw MeetingFileImportError.saveFailed }

            state = MeetingFileImportState(
                stage: .completed,
                progress: 1,
                fileName: fileName,
                detailText: "\(record.title) 회의록을 만들었습니다.",
                record: record
            )
            return record
        } catch is CancellationError {
            state = MeetingFileImportState(
                stage: .cancelled,
                progress: state.progress,
                fileName: fileName,
                detailText: "파일 가져오기를 취소했습니다."
            )
            throw CancellationError()
        } catch {
            state = MeetingFileImportState(
                stage: .failed,
                progress: state.progress,
                fileName: fileName,
                detailText: "파일을 회의록으로 만들지 못했습니다.",
                errorMessage: error.localizedDescription
            )
            throw error
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
        segments: inout [Segment],
        previousContext: inout [String]
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

        let finalText: String
        if shouldCorrect {
            update(
                .correcting,
                progress: min(progress + 0.02, 0.82),
                fileName: fileName,
                detail: "전사 다듬는 중 \(chunkLabel(chunk))"
            )
            let correctionContext = LLMCorrectionContext(
                topic: topic,
                glossary: glossary,
                previousText: previousContext.suffix(5).joined(separator: "\n"),
                runningSummary: "",
                document: document
            )
            finalText = await correctionService.correct(text: rawText, context: correctionContext)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? rawText
            try Task.checkCancellation()
        } else {
            finalText = rawText
        }

        let segment = Segment(
            id: rawResult.segment.id,
            text: finalText,
            timestamp: startedAt.addingTimeInterval(chunk.startSeconds),
            duration: chunk.durationSeconds
        )
        segments.append(segment)
        previousContext.append(finalText)
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
        state = MeetingFileImportState(
            stage: stage,
            progress: progress,
            fileName: fileName,
            detailText: detail
        )
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
