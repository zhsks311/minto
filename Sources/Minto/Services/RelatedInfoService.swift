import Foundation

/// 전사 키워드로 Notion(MCP)·Confluence를 동시에 조회해 관련 문서를 모으는 통합 서비스.
/// 회의 목록의 "관련 문서" 탭이 on-demand로 호출한다(매 청크 자동 조회는 rate-limit 위험).
@MainActor
public final class RelatedInfoService: ObservableObject {
    public static let shared = RelatedInfoService()

    private let notionMCP: NotionMCPService
    private let confluence: ConfluenceService

    public init(notionMCP: NotionMCPService = .shared, confluence: ConfluenceService = .shared) {
        self.notionMCP = notionMCP
        self.confluence = confluence
    }

    @Published public private(set) var results: [RelatedDoc] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var statusMessage: String?

    /// 둘 중 하나라도 연동 설정이 되어 있으면 조회 가능.
    public var isAnyConfigured: Bool {
        notionMCP.isConfigured || confluence.isConfigured
    }

    public func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAnyConfigured else {
            statusMessage = "설정에서 Notion 또는 Confluence를 먼저 연동하세요."
            return
        }
        guard !trimmed.isEmpty else {
            statusMessage = "조회할 키워드가 없습니다."
            return
        }

        isSearching = true
        statusMessage = nil
        defer { isSearching = false }

        async let notionResults = notionMCP.isConfigured ? notionMCP.search(trimmed) : []
        async let confluenceResults = confluence.isConfigured ? confluence.search(trimmed) : []
        let combined = await notionResults + confluenceResults

        results = combined
        statusMessage = combined.isEmpty ? "관련 문서를 찾지 못했습니다." : nil
    }

    public func clear() {
        results = []
        statusMessage = nil
        isSearching = false
    }
}
