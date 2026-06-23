import Foundation

/// 회의 시작 시 첨부하는 참고 문서의 소스 종류.
///
/// 소스별 형식 차이(파일 인코딩, Notion 블록, Confluence storage format)는
/// 어댑터에서 평문으로 흡수하고, downstream(용어 추출·교정·요약)은 종류만 구분한다.
/// 세션 단위 in-memory 값이라 영구 저장하지 않으므로 raw value(직렬화)는 두지 않는다.
public enum SourceKind: Sendable, Hashable {
    case file
    case notion
    case confluence
    case manual
}

/// 모든 소스(파일·Notion·Confluence·직접 입력)에서 수집한 참고 문서의 공통 평문 표현.
///
/// downstream은 이 평문(`text`)만 본다 — 소스별 형식 차이는 어댑터에서 이미 흡수됐다.
/// 세션 단위 in-memory 값이며 영구 저장하지 않는다(지난 회의 문서가 다음 회의로 새지 않도록).
public struct AttachedDocument: Identifiable, Sendable, Hashable {
    /// 안정 식별자(파일 경로 해시 / Notion url / Confluence url). 같은 소스는 같은 id → 중복 첨부 감지에 쓴다.
    public let id: String
    /// 표시용 제목(파일명에서 확장자 제거, Notion/Confluence 페이지 제목 등).
    public let title: String
    /// 평문 본문(cap 적용 후).
    public let text: String
    public let sourceKind: SourceKind
    /// 사용자에게 보여줄 출처 라벨(파일명·URL 등). `manual` 등 라벨이 없는 소스는 nil. 절대경로·민감정보 금지(lastPathComponent).
    public let sourceLabel: String?

    public init(
        id: String,
        title: String,
        text: String,
        sourceKind: SourceKind,
        sourceLabel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.sourceKind = sourceKind
        self.sourceLabel = sourceLabel
    }
}
