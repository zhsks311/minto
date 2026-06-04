import Foundation

/// 전사 기반으로 위키/Notion/Confluence에서 찾은 관련 문서 한 건.
public struct RelatedDoc: Identifiable, Sendable, Hashable {
    /// URL을 안정적 식별자로 사용 — 같은 문서가 재조회돼도 동일 id라 SwiftUI 불필요한 재구성 방지.
    public var id: String { url }
    public let source: Source
    public let title: String
    public let snippet: String
    public let url: String

    public enum Source: String, Sendable {
        case notion = "Notion"
        case confluence = "Confluence"
    }

    public init(source: Source, title: String, snippet: String = "", url: String) {
        self.source = source
        self.title = title
        self.snippet = snippet
        self.url = url
    }
}
