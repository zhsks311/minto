import Foundation

public struct SpeakerTalkTime: Equatable, Sendable {
    public let speakerLabel: String
    public let seconds: TimeInterval
    public let ratio: Double

    public init(speakerLabel: String, seconds: TimeInterval, ratio: Double) {
        self.speakerLabel = speakerLabel
        self.seconds = seconds
        self.ratio = ratio
    }
}

public enum TalkTimeAnalyzer {
    private static let unknownSpeakerLabel = "알 수 없음"

    public static func analyze(segments: [Segment]) -> [SpeakerTalkTime] {
        var secondsBySpeaker: [String: TimeInterval] = [:]
        for segment in segments {
            let label = normalized(segment.speaker) ?? unknownSpeakerLabel
            secondsBySpeaker[label, default: 0] += segment.duration
        }

        let totalSeconds = secondsBySpeaker.values.reduce(0, +)
        return secondsBySpeaker
            .map { label, seconds in
                SpeakerTalkTime(
                    speakerLabel: label,
                    seconds: seconds,
                    ratio: totalSeconds > 0 ? seconds / totalSeconds : 0
                )
            }
            .sorted {
                if $0.seconds == $1.seconds {
                    return $0.speakerLabel < $1.speakerLabel
                }
                return $0.seconds > $1.seconds
            }
    }

    // Domain(Models)은 UI에 의존할 수 없어 UI의 SpeakerLabel.normalized를 직접 쓰지 않는다.
    // 동일 규칙(trim + non-empty)을 의도적으로 로컬 보유한다. 공통화가 필요하면 Domain 레이어로
    // 정규화 primitive를 올리고 SpeakerLabel이 위임하는 별도 리팩터 커밋으로 분리한다.
    private static func normalized(_ speaker: String?) -> String? {
        guard let trimmed = speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
