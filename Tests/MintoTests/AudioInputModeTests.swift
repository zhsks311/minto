import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("AudioInputMode")
struct AudioInputModeTests {
    @Test("입력 모드는 마이크/시스템/혼합을 표현한다")
    func inputModeMetadata() {
        #expect(AudioInputMode.allCases == [.microphone, .systemAudio, .mixed])
        #expect(AudioInputMode.selectableCases == [.microphone, .systemAudio, .mixed])
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
            systemAudioAvailability: { .unavailable("캡처 가능한 디스플레이가 없어요.") }
        )

        let readiness = await checker.readiness(for: .systemAudio)

        #expect(readiness.state == .unavailable)
        #expect(readiness.canStartRecording == false)
        #expect(readiness.detail.contains("디스플레이"))
    }

    @Test("혼합 입력은 시스템 오디오 권한과 가용성을 기준으로 시작 가능 여부를 표시한다")
    func mixedAudioReadinessUsesSystemAudioGate() async {
        let checker = AudioInputReadinessChecker(
            hasScreenCapturePermission: { true },
            requestScreenCapturePermission: { true },
            systemAudioAvailability: { .available }
        )

        let readiness = await checker.readiness(for: .mixed)

        #expect(readiness.state == .ready)
        #expect(readiness.canStartRecording)
        #expect(readiness.title == "마이크+시스템 입력 가능")
        #expect(readiness.detail.contains("Echo cancellation"))
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
        #expect(AudioSourceFactory.makeSource(for: .mixed) is MixedAudioSource)
    }

    @Test("SystemAudioSource stop은 시작 전과 반복 호출에서도 안전하다")
    func systemAudioSourceStopIsIdempotent() {
        let source = SystemAudioSource()

        source.stop()
        source.stop()

        #expect(source.availableDevices == [AudioDevice(id: "system-audio", name: "시스템")])
    }

    @Test("mixer는 마이크와 시스템 버퍼를 같은 길이만큼 섞고 남은 샘플을 보존한다")
    func dualAudioBufferMixerMixesAlignedSamples() {
        let mixer = DualAudioBufferMixer(gain: 0.5)

        #expect(mixer.append([0.5, 1.0], source: .microphone).isEmpty)

        let firstOutput = mixer.append([0.5, -1.0, 0.5], source: .systemAudio)
        #expect(samples(firstOutput.first, approximatelyEqualTo: [0.5, 0.0]))

        let secondOutput = mixer.append([0.5], source: .microphone)
        #expect(samples(secondOutput.first, approximatelyEqualTo: [0.5]))
        #expect(samples(
            DualAudioBufferMixer.mix(microphone: [2.0], systemAudio: [2.0], gain: 1.0),
            approximatelyEqualTo: [1.0]
        ))
    }

    @Test("mixer는 한쪽 입력만 오래 쌓이면 오래된 샘플을 passthrough해 지연과 메모리 증가를 제한한다")
    func dualAudioBufferMixerLimitsSingleSourceBacklog() {
        let mixer = DualAudioBufferMixer(gain: 0.5, maxBufferedSamples: 2)

        let overflow = mixer.append([0.2, 0.4, 2.0], source: .microphone)
        #expect(samples(overflow.first, approximatelyEqualTo: [0.2]))

        let mixed = mixer.append([0.0, 0.0], source: .systemAudio)
        #expect(samples(mixed.first, approximatelyEqualTo: [0.2, 1.0]))
    }

    @Test("MixedAudioSource는 두 child source를 시작하고 섞인 buffer만 전달한다")
    func mixedAudioSourceStartsChildrenAndEmitsMixedBuffers() throws {
        let microphone = InputModeStubAudioSource()
        let systemAudio = InputModeStubAudioSource()
        let bufferSink = InputModeBufferSink()
        let source = MixedAudioSource(
            microphone: microphone,
            systemAudio: systemAudio,
            mixer: DualAudioBufferMixer(gain: 0.5)
        )
        source.onBuffer = { samples in
            bufferSink.record(samples)
        }

        try source.start()
        microphone.emitBuffer([0.4, 0.4])
        #expect(bufferSink.buffers.isEmpty)

        systemAudio.emitBuffer([0.2, -0.2])
        #expect(samples(bufferSink.buffers.first, approximatelyEqualTo: [0.3, 0.1]))

        source.stop()
        microphone.emitBuffer([1.0])
        systemAudio.emitBuffer([1.0])

        #expect(microphone.startCount == 1)
        #expect(systemAudio.startCount == 1)
        #expect(microphone.stopCount == 1)
        #expect(systemAudio.stopCount == 1)
        #expect(bufferSink.buffers.count == 1)
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

    @Test("ViewModel은 혼합 입력 source buffer를 VAD pipeline으로 전달한다")
    func viewModelPassesMixedSourceBuffersToVAD() async {
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

        viewModel.startNewRecordingSession(inputMode: .mixed)
        selectedSource.emitBuffer([0.2, -0.2, 0.4])
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(requestedModes == [.mixed])
        #expect(initialSource.stopCount == 1)
        #expect(selectedSource.startCount == 1)
        #expect(viewModel.audioInputMode == .mixed)
        #expect(samples(vad.processedBuffers.first, approximatelyEqualTo: [0.2, -0.2, 0.4]))
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

    func emitBuffer(_ samples: [Float]) {
        onBuffer?(samples)
    }
}

private final class InputModeBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedBuffers: [[Float]] = []

    var buffers: [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        return receivedBuffers
    }

    func record(_ samples: [Float]) {
        lock.lock()
        receivedBuffers.append(samples)
        lock.unlock()
    }
}

private func samples(_ lhs: [Float]?, approximatelyEqualTo rhs: [Float], tolerance: Float = 0.0001) -> Bool {
    guard let lhs, lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
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
    private let lock = NSLock()
    private var receivedBuffers: [[Float]] = []

    var processedBuffers: [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        return receivedBuffers
    }

    func process(samples: [Float]) {
        lock.lock()
        receivedBuffers.append(samples)
        lock.unlock()
    }

    func flushPending() async -> AudioChunk? { nil }
    func reset() {
        lock.lock()
        receivedBuffers.removeAll()
        lock.unlock()
    }
}
