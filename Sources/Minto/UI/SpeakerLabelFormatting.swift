import Foundation

/// 전사 줄 화자 라벨 정규화. 공백뿐이거나 빈 라벨은 nil로 취급해 표시하지 않는다.
/// 전사 렌더 뷰 3곳(overlay/library/summary)이 같은 규칙을 쓰도록 단일 출처로 둔다.
enum SpeakerLabel {
    static func normalized(_ speaker: String?) -> String? {
        guard let trimmed = speaker?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
