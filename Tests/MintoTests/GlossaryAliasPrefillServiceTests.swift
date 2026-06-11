import Testing
@testable import MintoCore
import Foundation

@MainActor
@Suite("GlossaryAliasPrefillService")
struct GlossaryAliasPrefillServiceTests {

    @Test("provider가 없으면 빈 배열로 fail-soft")
    func returnsEmptyWithoutProvider() async {
        let service = GlossaryAliasPrefillService(providerResolver: { nil })
        let aliases = await service.suggestAliases(for: "Liquibase")
        #expect(aliases.isEmpty)
    }

    @Test("요청에는 후보 용어만 넣고 응답은 한글 alias 1~3개로 정리한다")
    func requestsOnlyTermAndParsesAliases() async throws {
        let provider = StubAliasPrefillProvider(responseText: "1. 리퀴베이스, 리퀴 베이스, Liquibase, 리퀴베이스, 리퀴바이스")
        let service = GlossaryAliasPrefillService(providerResolver: { provider })

        let aliases = await service.suggestAliases(for: "Liquibase")

        #expect(aliases == ["리퀴베이스", "리퀴 베이스", "리퀴바이스"])
        let request = try #require(provider.lastRequest)
        #expect(request.useCase == .correction)
        #expect(request.maxOutputTokens == 64)
        #expect(request.userContent == "용어: Liquibase")
        #expect(!request.userContent.contains("회의"))
    }

    @Test("provider 실패는 빈 배열로 fail-soft")
    func returnsEmptyOnProviderFailure() async {
        let provider = StubAliasPrefillProvider(error: LLMProviderError.network("offline"))
        let service = GlossaryAliasPrefillService(providerResolver: { provider })

        let aliases = await service.suggestAliases(for: "Liquibase")

        #expect(aliases.isEmpty)
    }

    @Test("parseAliases는 bullet, 줄바꿈, 중복, 비한글 값을 정리한다")
    func parseAliasesCleansCommonFormats() {
        let parsed = GlossaryAliasPrefillService.parseAliases(
            """
            - 리퀴베이스
            2) 리퀴 베이스
            Liquibase
            리퀴베이스
            리퀴바이스
            리퀴베이즈
            """,
            excluding: "Liquibase"
        )

        #expect(parsed == ["리퀴베이스", "리퀴 베이스", "리퀴바이스"])
    }

    @Test("parseAliases는 괄호와 라틴 혼재 응답에서 한글 표기만 추출한다")
    func parseAliasesExtractsHangulFromMixedResponse() {
        let parsed = GlossaryAliasPrefillService.parseAliases(
            "리퀴베이스(Liquibase), 리퀴 베이스 / Liquibase, AWS 람다",
            excluding: "Liquibase"
        )

        #expect(parsed == ["리퀴베이스", "리퀴 베이스", "람다"])
    }
}

private final class StubAliasPrefillProvider: LLMTextGenerationProvider, @unchecked Sendable {
    let descriptor = LLMProviderDescriptor(
        id: .gpt,
        description: "alias prefill test provider",
        authKind: .apiKey,
        supportedCapabilities: [.textGeneration, .correction]
    )

    private let responseText: String
    private let error: (any Error)?
    private(set) var lastRequest: LLMTextRequest?

    init(responseText: String = "", error: (any Error)? = nil) {
        self.responseText = responseText
        self.error = error
    }

    func isConfigured() async -> Bool { true }

    func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(models: [], source: .bundledFallback)
    }

    func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        lastRequest = request

        if let error {
            throw error
        }
        return LLMTextResponse(text: responseText, providerID: .gpt, modelID: "stub")
    }
}
