import Foundation
import Testing
@testable import MintoCore

// MARK: - VAD 엔진 설정/팩토리

@Suite("VADEnginePreferences")
struct VADEnginePreferencesTests {
    @Test("저장값이 없으면 기본은 silero다")
    func defaultsToSilero() {
        let defaults = InMemoryUserDefaults()
        #expect(VADEnginePreferences.selectedEngine(in: defaults) == .silero)
    }

    @Test("저장된 엔진을 읽고, 알 수 없는 값은 기본으로 돌아간다")
    func readsStoredEngine() {
        let defaults = InMemoryUserDefaults()
        defaults.set(VADEngineID.energy.rawValue, forKey: VADEnginePreferences.selectedEngineKey)
        #expect(VADEnginePreferences.selectedEngine(in: defaults) == .energy)

        defaults.set("unknown-engine", forKey: VADEnginePreferences.selectedEngineKey)
        #expect(VADEnginePreferences.selectedEngine(in: defaults) == .silero)
    }
}

@Suite("VoiceActivityDetectorFactory 설정 기반 선택")
struct VoiceActivityDetectorFactoryPreferenceTests {
    /// 머신에 실제 모델이 있어도 테스트가 흔들리지 않도록 모델 경로를 항상 env로 고정한다.
    private let missingModelEnvironment = [
        "MINTO_FLUIDAUDIO_MODEL_DIR": "/private/tmp/minto2-missing-silero-model-\(UUID().uuidString)"
    ]

    @Test("설정이 energy면 Energy VAD를 쓴다")
    func energyPreferenceUsesEnergyVAD() {
        let defaults = InMemoryUserDefaults()
        defaults.set(VADEngineID.energy.rawValue, forKey: VADEnginePreferences.selectedEngineKey)

        let detector = VoiceActivityDetectorFactory.makeDefault(
            environment: missingModelEnvironment,
            defaults: defaults
        )

        #expect(detector is VADProcessor)
    }

    @Test("설정 기본값(silero)이라도 모델이 없으면 Energy VAD로 fallback한다")
    func sileroPreferenceWithoutModelFallsBack() {
        let defaults = InMemoryUserDefaults()

        let detector = VoiceActivityDetectorFactory.makeDefault(
            environment: missingModelEnvironment,
            defaults: defaults
        )

        #expect(detector is VADProcessor)
    }

    @Test("설정이 silero이고 모델이 있으면 Silero VAD를 쓴다")
    func sileroPreferenceWithModelUsesSilero() throws {
        let modelRoot = try makeModelBundleFixture()
        defer { try? FileManager.default.removeItem(at: modelRoot) }
        let defaults = InMemoryUserDefaults()
        defaults.set(VADEngineID.silero.rawValue, forKey: VADEnginePreferences.selectedEngineKey)

        let detector = VoiceActivityDetectorFactory.makeDefault(
            environment: ["MINTO_FLUIDAUDIO_MODEL_DIR": modelRoot.path],
            defaults: defaults
        )

        let silero = try #require(detector as? SileroVADProcessor)
        // 검증된 조합의 기본값이 그대로 적용되는지 고정한다.
        #expect(silero.configuration.threshold == 0.6)
        #expect(silero.configuration.speechPadding == 0.12)
        #expect(silero.configuration.mergeGapSeconds == 1.1)
    }

    @Test("환경변수 MINTO_VAD_ENGINE은 사용자 설정보다 우선한다")
    func environmentOverridesPreference() throws {
        let modelRoot = try makeModelBundleFixture()
        defer { try? FileManager.default.removeItem(at: modelRoot) }
        let defaults = InMemoryUserDefaults()
        defaults.set(VADEngineID.silero.rawValue, forKey: VADEnginePreferences.selectedEngineKey)

        let detector = VoiceActivityDetectorFactory.makeDefault(
            environment: [
                "MINTO_VAD_ENGINE": "energy",
                "MINTO_FLUIDAUDIO_MODEL_DIR": modelRoot.path,
            ],
            defaults: defaults
        )

        #expect(detector is VADProcessor)
    }

    @Test("makeNext는 엔진 종류가 같으면 기존 인스턴스를 재사용한다")
    func makeNextReusesSameEngineKind() {
        let defaults = InMemoryUserDefaults()
        defaults.set(VADEngineID.energy.rawValue, forKey: VADEnginePreferences.selectedEngineKey)
        let current = VADProcessor()

        let next = VoiceActivityDetectorFactory.makeNext(
            current: current,
            environment: missingModelEnvironment,
            defaults: defaults
        )

        #expect(next === current)
    }

    @Test("makeNext는 엔진 종류가 바뀌면 새 인스턴스로 교체한다")
    func makeNextSwapsWhenEngineKindChanges() throws {
        let modelRoot = try makeModelBundleFixture()
        defer { try? FileManager.default.removeItem(at: modelRoot) }
        let defaults = InMemoryUserDefaults()
        defaults.set(VADEngineID.silero.rawValue, forKey: VADEnginePreferences.selectedEngineKey)
        let current = VADProcessor()

        let next = VoiceActivityDetectorFactory.makeNext(
            current: current,
            environment: ["MINTO_FLUIDAUDIO_MODEL_DIR": modelRoot.path],
            defaults: defaults
        )

        #expect(next is SileroVADProcessor)
    }

    @Test("기본 모델 경로는 temp가 아니라 Application Support 아래다")
    func defaultModelDirectoryIsPersistent() {
        let path = SileroVADProcessor.Configuration.defaultModelDirectory.path
        #expect(path.contains("Application Support"))
        #expect(path.hasSuffix("Minto/models/fluidaudio"))
    }

    private func makeModelBundleFixture() throws -> URL {
        let modelRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto2-silero-pref-\(UUID().uuidString)", isDirectory: true)
        let modelBundle = modelRoot
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("silero-vad", isDirectory: true)
            .appendingPathComponent(SileroVADProcessor.Configuration.modelFileName, isDirectory: true)
        try FileManager.default.createDirectory(at: modelBundle, withIntermediateDirectories: true)
        return modelRoot
    }
}

// MARK: - Empty final repair 설정 해석

@Suite("EmptyFinalRepairPolicy.resolve")
struct EmptyFinalRepairPolicyResolveTests {
    @Test("환경변수가 없고 설정 저장값도 없으면 검증된 조합으로 켜진다")
    func defaultsToVerifiedCandidate() {
        let policy = EmptyFinalRepairPolicy.resolve(environment: [:], defaults: InMemoryUserDefaults())

        #expect(policy == .verifiedCandidate)
        #expect(policy.isEnabled)
        #expect(policy.padSeconds == 1.0)
        #expect(policy.minChunkSeconds == 2.0)
        #expect(policy.minAudioDB == -35.0)
    }

    @Test("설정 토글이 꺼져 있으면 비활성이다")
    func disabledByPreference() {
        let defaults = InMemoryUserDefaults()
        defaults.set(false, forKey: EmptyFinalRepairPolicy.preferenceKey)

        let policy = EmptyFinalRepairPolicy.resolve(environment: [:], defaults: defaults)

        #expect(policy == .disabled)
    }

    @Test("환경변수가 있으면 설정보다 우선한다 — 켜는 경우")
    func environmentEnableOverridesPreference() {
        let defaults = InMemoryUserDefaults()
        defaults.set(false, forKey: EmptyFinalRepairPolicy.preferenceKey)

        let policy = EmptyFinalRepairPolicy.resolve(
            environment: ["MINTO_EMPTY_FINAL_REPAIR": "1", "MINTO_EMPTY_FINAL_REPAIR_PAD_SEC": "0.75"],
            defaults: defaults
        )

        #expect(policy.isEnabled)
        #expect(policy.padSeconds == 0.75)
    }

    @Test("환경변수가 있으면 설정보다 우선한다 — 끄는 경우")
    func environmentDisableOverridesPreference() {
        let defaults = InMemoryUserDefaults()
        defaults.set(true, forKey: EmptyFinalRepairPolicy.preferenceKey)

        let policy = EmptyFinalRepairPolicy.resolve(
            environment: ["MINTO_EMPTY_FINAL_REPAIR": "0"],
            defaults: defaults
        )

        #expect(policy == .disabled)
    }
}

// MARK: - 녹음 시작 시 VAD 재생성

@MainActor
@Suite("TranscriptionViewModel VAD 재생성")
struct TranscriptionViewModelVADRecreationTests {
    @Test("factory가 주입되면 녹음 시작마다 VAD를 새로 만든다")
    func recreatesVADOnEachRecordingStart() async {
        let stt = RecreationStubSTTService()
        let audioSource = RecreationStubAudioSource()
        let initialVAD = RecreationStubVAD()
        var madeVADs: [RecreationStubVAD] = []
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: audioSource,
            vadProcessor: initialVAD,
            vadProcessorFactory: { _ in
                let vad = RecreationStubVAD()
                madeVADs.append(vad)
                return vad
            }
        )

        viewModel.startRecording()
        #expect(madeVADs.count == 1)
        #expect(madeVADs.last?.resetCount == 1)
        #expect(madeVADs.last?.onChunk != nil)
        await viewModel.stopRecordingAndDrain()

        viewModel.startRecording()
        #expect(madeVADs.count == 2)
        #expect(madeVADs.last?.resetCount == 1)
        await viewModel.stopRecordingAndDrain()

        // 초기 인스턴스는 factory 교체 이후 사용되지 않는다.
        #expect(initialVAD.resetCount == 0)
    }

    @Test("factory가 없으면 주입된 VAD를 그대로 재사용한다")
    func keepsInjectedVADWithoutFactory() async {
        let stt = RecreationStubSTTService()
        let audioSource = RecreationStubAudioSource()
        let vad = RecreationStubVAD()
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: audioSource,
            vadProcessor: vad
        )

        viewModel.startRecording()
        #expect(vad.resetCount == 1)
        await viewModel.stopRecordingAndDrain()

        viewModel.startRecording()
        #expect(vad.resetCount == 2)
        await viewModel.stopRecordingAndDrain()
    }
}

@MainActor
private final class RecreationStubSTTService: TranscriptionSTTServicing {
    var modelState: ModelState = .loaded
    var modelVariant: String = "stub"
    var speechEngineID: SpeechEngineID = .whisperAccurate
    var supportsPreviewTranscription: Bool = false
    var onModelStateChange: ((ModelState) -> Void)?

    func loadEngine(_ engineID: SpeechEngineID) async {
        speechEngineID = engineID
    }

    func loadModel(variant: String) async {
        modelVariant = variant
    }

    func recoverModelCacheAndReload(variant: String) async {
        modelVariant = variant
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        TranscriptionResult(
            segment: Segment(text: "", timestamp: Date(), duration: 0),
            isFinal: true
        )
    }
}

private final class RecreationStubAudioSource: AudioSourceProtocol {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []

    func start() throws {}
    func stop() {}
    func selectDevice(_ device: AudioDevice) throws {}
}

private final class RecreationStubVAD: VoiceActivityDetector, @unchecked Sendable {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?
    private(set) var resetCount = 0

    func process(samples: [Float]) {}

    func flushPending() async -> AudioChunk? {
        nil
    }

    func reset() {
        resetCount += 1
    }
}
