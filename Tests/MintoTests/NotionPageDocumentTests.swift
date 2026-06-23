import Foundation
import Testing
@testable import MintoCore

/// 토큰이 없는/재연결 필요 상태를 만들기 위한 인메모리 backend.
private struct StubTokenBackend: OAuthTokenStorageBackend {
    func exists(key: String) -> Bool { false }
    func load(key: String) -> Data? { nil }
    func save(key: String, data: Data) {}
    func delete(key: String) {}
}

@MainActor
@Suite("NotionMCPService.fetchPageDocument")
struct NotionPageDocumentTests {

    private func makeService(needsReconnect: Bool = false) -> NotionMCPService {
        let storage = KeychainTokenStorage(keychainKey: "test-notion-\(UUID().uuidString)", storage: StubTokenBackend())
        if needsReconnect {
            storage.markRequiresReconnect()
        }
        return NotionMCPService(tokenStorage: storage)
    }

    @Test("미연결이면 notConnected 로 분류한다 — 네트워크 호출 없음")
    func disconnectedYieldsNotConnected() async {
        let service = makeService()
        #expect(service.connectionState == .disconnected)

        let result = await service.fetchPageDocument(url: "https://www.notion.so/page")

        #expect(result == .failure(.notConnected))
    }

    @Test("재연결 필요 상태면 needsReconnect 로 분류한다")
    func needsReconnectYieldsNeedsReconnect() async {
        let service = makeService(needsReconnect: true)
        #expect(service.connectionState == .needsReconnect)

        let result = await service.fetchPageDocument(url: "https://www.notion.so/page")

        #expect(result == .failure(.needsReconnect))
    }

    @Test("본문 첫 줄을 제목으로 쓴다")
    func titleFromFirstLine() {
        #expect(NotionMCPService.notionTitle(from: "주간 회의록\n안건 1") == "주간 회의록")
    }

    @Test("마크다운 heading 마커를 제거한다")
    func titleStripsHeadingMarkers() {
        #expect(NotionMCPService.notionTitle(from: "## 2분기 계획\n본문") == "2분기 계획")
    }

    @Test("빈 본문이면 기본 제목을 쓴다")
    func titleFallsBackWhenEmpty() {
        #expect(NotionMCPService.notionTitle(from: "   \n\n  ") == "Notion 문서")
    }

    @Test("제목은 80자로 자른다")
    func titleIsCapped() {
        let long = String(repeating: "가", count: 200)
        #expect(NotionMCPService.notionTitle(from: long).count == 80)
    }
}
