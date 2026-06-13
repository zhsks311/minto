let kSpeakerSelfLabel = "나"
let kSpeakerOtherLabel = "상대"

struct ChannelSpeakerLabeler: Sendable {
    func speaker(
        inputMode: AudioInputMode,
        activityProvider: (any RecordingChannelActivityProviding)?,
        startSeconds: Double?,
        endSeconds: Double?
    ) -> String? {
        switch inputMode {
        case .microphone:
            return nil
        case .systemAudio:
            return kSpeakerOtherLabel
        case .mixed:
            guard let activityProvider,
                  let startSeconds,
                  let endSeconds else {
                return nil
            }
            switch activityProvider.dominantChannel(startSeconds: startSeconds, endSeconds: endSeconds) {
            case .microphone:
                return kSpeakerSelfLabel
            case .systemAudio:
                return kSpeakerOtherLabel
            case nil:
                return nil
            }
        }
    }
}
