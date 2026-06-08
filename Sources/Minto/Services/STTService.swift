import Foundation

/// Speech engine facade used by the app and benchmark tests.
@MainActor
public final class STTService {

    // MARK: - Public state

    public private(set) var modelState: ModelState = .unloaded
    public private(set) var modelVariant: String = "openai_whisper-large-v3-v20240930_turbo"
    public private(set) var speechEngineID: SpeechEngineID = .defaultEngine

    // ViewModel이 modelState 변화를 @Published 없이 수신하는 콜백
    var onModelStateChange: ((ModelState) -> Void)?

    // MARK: - Private

    private var currentEngine: (any SpeechTranscriptionEngine)?

    public init() {}

    public static func engineAvailability(for engineID: SpeechEngineID) async -> SpeechEngineAvailability {
        if engineID.whisperVariant != nil {
            return .available
        }

        switch engineID {
        case .speechAnalyzer:
            return await SpeechAnalyzerSTTEngine.availability()
        case .sfSpeechOnDevice:
            return SFSpeechOnDeviceSTTEngine.availability()
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return .available
        }
    }

    public nonisolated static func requestSFSpeechAuthorization() async -> SpeechEngineAvailability {
        await SFSpeechOnDeviceSTTEngine.requestAuthorization()
    }

    nonisolated static func sfSpeechOnDeviceAvailability() -> SpeechEngineAvailability {
        SFSpeechOnDeviceSTTEngine.availability()
    }

    // MARK: - Model loading

    public var supportsPreviewTranscription: Bool {
        currentEngine?.supportsPreviewTranscription ?? speechEngineID.supportsPreviewTranscription
    }

    public func loadEngine(_ engineID: SpeechEngineID = .defaultEngine) async {
        let availability = await Self.engineAvailability(for: engineID)
        guard availability.isSelectable else {
            currentEngine = nil
            speechEngineID = engineID
            updateState(.failed(availability.detailText ?? "\(engineID.title)을 사용할 수 없습니다."))
            return
        }

        if let variant = engineID.whisperVariant {
            speechEngineID = engineID
            await loadWhisperModel(variant: variant)
            return
        }

        await loadTranscriptionEngine(Self.makeEngine(for: engineID))
    }

    public func loadModel(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        speechEngineID = SpeechEngineID.fromWhisperVariant(variant)
        await loadWhisperModel(variant: variant)
    }

    private func loadWhisperModel(
        variant: String,
        didAttemptMetadataRecovery: Bool = false
    ) async {
        modelVariant = variant
        speechEngineID = SpeechEngineID.fromWhisperVariant(variant)
        await loadTranscriptionEngine(
            WhisperKitSTTEngine(variant: variant),
            didAttemptMetadataRecovery: didAttemptMetadataRecovery
        )
    }

    private func loadTranscriptionEngine(
        _ engine: any SpeechTranscriptionEngine,
        didAttemptMetadataRecovery: Bool = false
    ) async {
        currentEngine = nil
        speechEngineID = engine.engineID
        modelVariant = engine.modelVariant
        do {
            try await engine.load(updateState: { [weak self] state in
                self?.updateState(state)
            })
            currentEngine = engine
            speechEngineID = engine.engineID
            modelVariant = engine.modelVariant
        } catch {
            if engine.engineID.whisperVariant != nil,
               !didAttemptMetadataRecovery,
               Self.isRecoverableMetadataError(error) {
                await recoverFromInvalidMetadataAndReload(variant: engine.modelVariant)
                return
            }

            updateState(.failed(error.localizedDescription))
            fputs("[STT] load error: \(error)\n", stderr)
        }
    }

    nonisolated static func localModelFolderOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        WhisperKitSTTEngine.localModelFolderOverride(environment: environment)
    }

    /// User-triggered recovery path for corrupted Hugging Face/WhisperKit cache metadata.
    /// It removes only the selected model's cached folder and per-file download metadata,
    /// then runs the normal download/load flow again.
    public func recoverModelCacheAndReload(variant: String = "openai_whisper-large-v3-v20240930_turbo") async {
        modelVariant = variant
        currentEngine = nil
        updateState(.loading)

        do {
            try await removeCachedModelFilesAndLog(for: variant, reason: "manual recovery")
            await loadWhisperModel(variant: variant, didAttemptMetadataRecovery: true)
        } catch {
            let message = "모델 캐시 정리에 실패했습니다: \(error.localizedDescription)"
            updateState(.failed(message))
            fputs("[STT] recovery error: \(error)\n", stderr)
        }
    }

    nonisolated static func isRecoverableMetadataError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("invalid metadata")
            || message.contains("corrupted metadata")
    }

    nonisolated static func modelCacheCandidateURLs(for variant: String, repoRoot: URL? = nil) -> [URL] {
        let trimmed = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let root: URL
        if let repoRoot {
            root = repoRoot
        } else {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return []
            }
            root = documents
                .appendingPathComponent("huggingface", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        }

        let downloadRoot = root
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)

        let candidates = matchingChildren(in: root, variant: trimmed)
            + matchingChildren(in: downloadRoot, variant: trimmed)

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    private func recoverFromInvalidMetadataAndReload(variant: String) async {
        currentEngine = nil
        updateState(.loading)

        do {
            try await removeCachedModelFilesAndLog(for: variant, reason: "invalid metadata")
            await loadWhisperModel(variant: variant, didAttemptMetadataRecovery: true)
        } catch {
            let message = "모델 캐시 정리에 실패했습니다: \(error.localizedDescription)"
            updateState(.failed(message))
            fputs("[STT] metadata recovery error: \(error)\n", stderr)
        }
    }

    private func removeCachedModelFilesAndLog(for variant: String, reason: String) async throws {
        let removed = try await Self.removeCachedModelFiles(for: variant)
        if removed.isEmpty {
            fputs("[STT] recovery(\(reason)): no cached model files found for \(variant)\n", stderr)
        } else {
            fputs("[STT] recovery(\(reason)): removed \(removed.count) cached path(s) for \(variant)\n", stderr)
        }
    }

    nonisolated private static func removeCachedModelFiles(for variant: String) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let candidates = modelCacheCandidateURLs(for: variant)
            let fileManager = FileManager.default
            var removed: [String] = []

            for url in candidates {
                guard fileManager.fileExists(atPath: url.path) else { continue }
                try fileManager.removeItem(at: url)
                removed.append(url.path)
            }

            return removed
        }.value
    }

    nonisolated private static func matchingChildren(in root: URL, variant: String) -> [URL] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { url in
            let name = url.lastPathComponent
            return name == variant || name.contains(variant)
        }
    }

    private static func makeEngine(for engineID: SpeechEngineID) -> any SpeechTranscriptionEngine {
        switch engineID {
        case .whisperAccurate, .whisperBalanced, .whisperFast:
            return WhisperKitSTTEngine(variant: engineID.whisperVariant!)
        case .speechAnalyzer:
            return SpeechAnalyzerSTTEngine()
        case .sfSpeechOnDevice:
            return SFSpeechOnDeviceSTTEngine()
        }
    }

    // MARK: - Transcription

    public func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        guard let currentEngine else { throw STTError.modelNotLoaded }
        return try await currentEngine.transcribe(pcmSamples: pcmSamples)
    }

    // MARK: - Private helpers

    private func updateState(_ state: ModelState) {
        modelState = state
        onModelStateChange?(state)
    }

}
