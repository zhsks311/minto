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
            return MixedAudioSource()
        }
    }
}
