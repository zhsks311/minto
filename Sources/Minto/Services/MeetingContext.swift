import Foundation
import Combine

/// 현재 녹음 세션의 회의 맥락(주제 + 용어집).
///
/// 회의마다 "녹음 시작" 시트에서 새로 입력받는 **세션 단위 in-memory 상태**다.
/// 영구 저장(@AppStorage)하지 않으므로 지난 회의 맥락이 다음 회의로 새지 않는다.
/// 현재는 LLM 후교정에만 쓰이지만, 향후 요약/문서/실시간 검색 기능이 공유·확장할 토대다.
@MainActor
public final class MeetingContext: ObservableObject {

    public static let shared = MeetingContext()
    private init() {}

    /// 회의 주제·배경·참석자 등 자유 텍스트.
    @Published public var topic: String = ""

    /// 고유명사·전문용어 목록 (줄 단위).
    @Published public var glossary: String = ""

    /// 교정에 쓸 맥락이 하나라도 있는지.
    public var hasContext: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !glossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 새 회의 세션 시작 시 호출. 지정값으로 교체한다.
    public func start(topic: String, glossary: String) {
        self.topic = topic
        self.glossary = glossary
        let terms = glossary.split(whereSeparator: { $0.isNewline }).count
        fputs("[Meeting] context set — topic: \"\(topic)\", glossary terms: \(terms)\n", stderr)
    }

    /// 맥락 초기화.
    public func clear() {
        topic = ""
        glossary = ""
    }
}
