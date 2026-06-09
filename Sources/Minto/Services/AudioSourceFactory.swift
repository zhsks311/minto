import Foundation

enum AudioSourceFactory {
    @MainActor
    static func makeSource(for mode: AudioInputMode) -> any AudioSourceProtocol {
        switch mode {
        case .microphone:
            return MicrophoneSource()
        case .systemAudio:
            return SystemAudioSource()
        case .mixed:
            return UnavailableAudioSource(reason: "마이크+시스템 입력은 mixer 보강 후 지원합니다.")
        }
    }
}

final class UnavailableAudioSource: AudioSourceProtocol, @unchecked Sendable {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?

    var availableDevices: [AudioDevice] {
        []
    }

    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func start() throws {
        onError?(.systemAudioUnavailable(reason))
    }

    func stop() {}

    func selectDevice(_ device: AudioDevice) throws {
        throw AudioSourceError.deviceNotFound(device)
    }
}
