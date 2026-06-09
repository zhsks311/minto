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
