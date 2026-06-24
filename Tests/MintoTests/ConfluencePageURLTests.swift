import Foundation
import Testing
@testable import MintoCore

/// Confluence 페이지 URL → pageId 파싱과 빈 입력 단락(short-circuit) 검증.
/// pageID(fromURL:)는 순수 정적 함수라 네트워크·자격증명 없이 결정적으로 검증한다.
@Suite("ConfluenceService.pageID(fromURL:)")
struct ConfluencePageURLTests {

    @Test("모던 URL(/pages/{id}/Title)에서 숫자 id를 뽑는다")
    func modernURLWithTitle() {
        let id = ConfluenceService.pageID(fromURL: "https://acme.atlassian.net/wiki/spaces/ENG/pages/123456789/Design+Doc")
        #expect(id == "123456789")
    }

    @Test("제목 없는 /pages/{id} URL에서도 뽑는다")
    func modernURLWithoutTitle() {
        let id = ConfluenceService.pageID(fromURL: "https://acme.atlassian.net/wiki/spaces/ENG/pages/987654")
        #expect(id == "987654")
    }

    @Test("편집 중 복사한 /pages/{id}/edit 형식에서도 뽑는다")
    func editURL() {
        let id = ConfluenceService.pageID(fromURL: "https://acme.atlassian.net/wiki/spaces/ENG/pages/246810/edit")
        #expect(id == "246810")
    }

    @Test("레거시 viewpage.action?pageId= 형식에서 뽑는다")
    func legacyPageIdQuery() {
        let id = ConfluenceService.pageID(fromURL: "https://acme.atlassian.net/wiki/pages/viewpage.action?pageId=555111")
        #expect(id == "555111")
    }

    @Test("pageId 파라미터 대소문자를 무시한다")
    func pageIdQueryCaseInsensitive() {
        let id = ConfluenceService.pageID(fromURL: "https://acme.atlassian.net/x?PAGEID=42")
        #expect(id == "42")
    }

    @Test("페이지 id가 없는 URL은 nil")
    func noPageID() {
        #expect(ConfluenceService.pageID(fromURL: "https://acme.atlassian.net/wiki/spaces/ENG") == nil)
    }

    @Test("빈 문자열·공백은 nil")
    func emptyIsNil() {
        #expect(ConfluenceService.pageID(fromURL: "") == nil)
        #expect(ConfluenceService.pageID(fromURL: "   ") == nil)
    }

    @Test("URL이 아닌 임의 텍스트는 nil")
    func garbageIsNil() {
        #expect(ConfluenceService.pageID(fromURL: "그냥 메모입니다") == nil)
    }

    @MainActor
    @Test("빈 URL 첨부는 네트워크 없이 fetchFailed로 단락된다")
    func emptyURLShortCircuits() async {
        let service = ConfluenceService(defaults: UserDefaults(suiteName: "test-confluence-\(UUID().uuidString)")!)
        let result = await service.fetchPageDocument(url: "   ")
        #expect(result == .failure(.fetchFailed))
    }
}
