import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("AudioInputMode")
struct AudioInputModeTests {
    @Test("입력 모드는 마이크/시스템/혼합을 표현한다")
    func inputModeMetadata() {
        #expect(AudioInputMode.allCases == [.microphone, .systemAudio, .mixed])
        #expect(AudioInputMode.selectableCases == [.microphone, .systemAudio])
        #expect(AudioInputMode.microphone.requiresScreenCapturePermission == false)
        #expect(AudioInputMode.systemAudio.requiresScreenCapturePermission == true)
        #expect(AudioInputMode.mixed.requiresScreenCapturePermission == true)
    }

    @Test("readiness checker는 마이크 입력을 바로 시작 가능으로 표시한다")
    func microphoneReadinessAllowsStart() async {
        let checker = AudioInputReadinessChecker(
            hasScreenCapturePermission: { false },
            requestScreenCapturePermission: { false },
            systemAudioAvailability: { .unavailable("not used") }
        )

        let readiness = await checker.readiness(for: .microphone)

        #expect(readiness.state == .ready)
        #expect(readiness.canStartRecording)
    }

    @Test("시스템 입력은 화면 기록 권한이 없으면 시작을 막고 availability를 조회하지 않는다")
    func systemAudioReadinessRequiresPermissionBeforeAvailability() async {
        let availabilityCalls = InputModeCounter()
        let checker = AudioInputReadinessChecker(
            hasScreenCapturePermission: { false },
            requestScreenCapturePermission: { false },
            systemAudioAvailability: {
                availabilityCalls.increment()
                return .available
            }
        )

        let readiness = await checker.readiness(for: .systemAudio)

        #expect(readiness.state == .permissionRequired)
        #expect(readiness.canStartRecording == false)
        #expect(readiness.actionTitle == "시스템 설정 열기")
        #expect(availabilityCalls.count == 0)
    }

    @Test("시스템 입력은 권한과 캡처 대상이 있으면 시작 가능으로 표시한다")
    func systemAudioReadinessAllowsStartWhenAvailable() async {
        let checker = AudioInputReadinessChecker(
            hasScreenCapturePermission: { true },
            requestScreenCapturePermission: { true },
            systemAudioAvailability: { .available }
        )

        let readiness = await checker.readiness(for: .systemAudio)

        #expect(readiness.state == .ready)
        #expect(readiness.canStartRecording)
    }

    @Test("시스템 입력은 캡처 대상이 없으면 unavailable로 표시한다")
    func systemAudioReadinessReportsUnavailableAvailability() async {
        let checker = AudioInputReadinessChecker(
            hasScreenCapturePermission: { true },
            requestScreenCapturePermission: { true },
            systemAudioAvailability: { .unavailable("캡처 가능한 디스플레이가 없습니다.") }
        )

        let readiness = await checker.readiness(for: .systemAudio)

        #expect(readiness.state == .unavailable)
        #expect(readiness.canStartRecording == false)
        #expect(readiness.detail.contains("디스플레이"))
    }

    @Test("시스템 입력 권한 요청 후 readiness를 다시 계산한다")
    func systemAudioReadinessRechecksAfterPermissionRequest() async {
        let permission = InputModePermissionStub(initial: false, requestedValue: true)
        let checker = AudioInputReadinessChecker(
            hasScreenCapturePermission: { permission.hasPermission },
            requestScreenCapturePermission: { permission.request() },
            systemAudioAvailability: { .available }
        )

        let readiness = await checker.requestPermission(for: .systemAudio)

        #expect(permission.requestCount == 1)
        #expect(readiness.state == .ready)
        #expect(readiness.canStartRecording)
    }

    @Test("source factory는 입력 모드에 맞는 source를 만든다")
    func sourceFactoryCreatesMatchingSource() {
        #expect(AudioSourceFactory.makeSource(for: .microphone) is MicrophoneSource)
        #expect(AudioSourceFactory.makeSource(for: .systemAudio) is SystemAudioSource)
        #expect(AudioSourceFactory.makeSource(for: .mixed) is UnavailableAudioSource)
    }

    @Test("SystemAudioSource stop은 시작 전과 반복 호출에서도 안전하다")
    func systemAudioSourceStopIsIdempotent() {
        let source = SystemAudioSource()

        source.stop()
        source.stop()

        #expect(source.availableDevices == [AudioDevice(id: "system-audio", name: "시스템")])
    }

    @Test("mixed source는 mixer 구현 전 unavailable error로 막는다")
    func mixedSourceIsUnavailableUntilMixerExists() throws {
        let source = AudioSourceFactory.makeSource(for: .mixed)
        let errorSink = InputModeErrorSink()
        source.onError = { error in
            errorSink.record(error)
        }

        try source.start()

        guard case .systemAudioUnavailable(let reason) = errorSink.error else {
            Issue.record("mixed source should report unavailable")
            return
        }
        #expect(reason.contains("mixer"))
    }

    @Test("ViewModel은 녹음 시작 전에 선택한 입력 source로 교체한다")
    func viewModelSwitchesSourceBeforeRecording() async {
        let initialSource = InputModeStubAudioSource()
        let selectedSource = InputModeStubAudioSource()
        let stt = InputModeStubSTT()
        let vad = InputModeStubVAD()
        var requestedModes: [AudioInputMode] = []
        let viewModel = TranscriptionViewModel(
            sttService: stt,
            audioSource: initialSource,
            vadProcessor: vad,
            audioSourceFactory: { mode in
                requestedModes.append(mode)
                return selectedSource
            }
        )

        viewModel.startNewRecordingSession(inputMode: .systemAudio)

        #expect(requestedModes == [.systemAudio])
        #expect(initialSource.stopCount == 1)
        #expect(selectedSource.startCount == 1)
        #expect(viewModel.audioInputMode == .systemAudio)
        await viewModel.stopRecordingAndDrain()
    }
}

private final class InputModeStubAudioSource: AudioSourceProtocol {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func selectDevice(_ device: AudioDevice) throws {}
}

private final class InputModeErrorSink: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedError: AudioSourceError?

    var error: AudioSourceError? {
        lock.lock()
        defer { lock.unlock() }
        return receivedError
    }

    func record(_ error: AudioSourceError) {
        lock.lock()
        receivedError = error
        lock.unlock()
    }
}

private final class InputModeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class InputModePermissionStub: @unchecked Sendable {
    private let lock = NSLock()
    private var currentValue: Bool
    private let requestedValue: Bool
    private var requests = 0

    init(initial: Bool, requestedValue: Bool) {
        self.currentValue = initial
        self.requestedValue = requestedValue
    }

    var hasPermission: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func request() -> Bool {
        lock.lock()
        requests += 1
        currentValue = requestedValue
        let value = currentValue
        lock.unlock()
        return value
    }
}

@MainActor
private final class InputModeStubSTT: TranscriptionSTTServicing {
    var modelState: ModelState = .loaded
    var modelVariant: String = "stub"
    var speechEngineID: SpeechEngineID = .defaultEngine
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
            segment: Segment(text: "stub", timestamp: Date(), duration: 1),
            isFinal: true
        )
    }
}

private final class InputModeStubVAD: VoiceActivityDetector, @unchecked Sendable {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?

    func process(samples: [Float]) {}
    func flushPending() async -> AudioChunk? { nil }
    func reset() {}
}
