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

    /// 회의 안건/문서(선택). 주어지면 교정·요약 프롬프트에 참고자료로 주입해 품질을 올린다.
    @Published public var document: String = ""

    /// 회의 진행 중 누적되는 요약(증분 갱신). 교정 context로도 쓰이고, 종료 시 최종 요약의 입력이 된다.
    @Published public var runningSummary: String = ""

    /// 회의 종료 시 정제된 **구조화** 최종 요약(사용자에게 표시).
    @Published public var finalSummary: MeetingSummary?

    /// 교정에 쓸 맥락이 하나라도 있는지.
    public var hasContext: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !glossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 새 회의 세션 시작 시 호출. 지정값으로 교체하고 이전 회의의 요약은 비운다(세션 간 누수 방지).
    public func start(topic: String, glossary: String, document: String = "") {
        self.topic = topic
        self.glossary = glossary
        self.document = document
        self.runningSummary = ""
        self.finalSummary = nil
        let terms = glossary.split(whereSeparator: { $0.isNewline }).count
        fputs("[Meeting] context set — topicLen=\(topic.count), glossary terms=\(terms), docLen=\(document.count)\n", stderr)
    }

    /// 맥락 초기화.
    public func clear() {
        topic = ""
        glossary = ""
        document = ""
        runningSummary = ""
        finalSummary = nil
    }
}
