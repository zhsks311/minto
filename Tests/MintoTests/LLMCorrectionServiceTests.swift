import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("LLMCorrectionService")
struct LLMCorrectionServiceTests {
    @Test("교정 성공 시 provider 응답을 postprocess해 반환한다")
    func returnsCorrectedTextOnSuccess() async throws {
        let service = makeService(selectedProvider: .gptAPI)
        let provider = StubCorrectionProvider(responseText: "교정 결과: 교정된 문장")

        let result = await service.correct(
            text: "교정전 문장",
            context: LLMCorrectionContext(topic: "회의 주제"),
            providerResolver: { providerID in
                #expect(providerID == .gpt)
                return provider
            }
        )

        #expect(result == "교정된 문장")
        #expect(provider.requests.count == 1)
        #expect(provider.requests.first?.useCase == .correction)
        #expect(provider.requests.first?.userContent.contains("교정전 문장") == true)
    }

    @Test("provider 오류 시 nil을 반환해 호출자가 원문을 유지할 수 있다")
    func providerErrorKeepsOriginalViaFallback() async {
        let service = makeService(selectedProvider: .gptAPI)
        let provider = StubCorrectionProvider(error: LLMProviderError.network("failed"))
        let original = "원문 문장"

        let corrected = await service.correct(
            text: original,
            context: LLMCorrectionContext(),
            providerResolver: { _ in provider }
        ) ?? original

        #expect(corrected == original)
        #expect(provider.requests.count == 1)
    }

    @Test("provider 미선택이면 provider를 호출하지 않고 nil을 반환한다")
    func noneProviderSkipsCorrection() async {
        let service = makeService(selectedProvider: .none)
        let provider = StubCorrectionProvider()
        var resolverWasCalled = false

        let result = await service.correct(
            text: "원문",
            context: LLMCorrectionContext(),
            providerResolver: { _ in
                resolverWasCalled = true
                return provider
            }
        )

        #expect(result == nil)
        #expect(!resolverWasCalled)
        #expect(provider.requests.isEmpty)
    }

    @Test("provider를 해석할 수 없으면 provider를 호출하지 않고 nil을 반환한다")
    func unresolvedProviderSkipsCorrection() async {
        let service = makeService(selectedProvider: .gptAPI)

        let result = await service.correct(
            text: "원문",
            context: LLMCorrectionContext(),
            providerResolver: { _ in nil }
        )

        #expect(result == nil)
    }

    @Test("correction 미지원 provider는 호출하지 않고 nil을 반환한다")
    func unsupportedProviderSkipsCorrection() async {
        let service = makeService(selectedProvider: .gptAPI)
        let provider = StubCorrectionProvider(supportedCapabilities: [.textGeneration, .answer])

        let result = await service.correct(
            text: "원문",
            context: LLMCorrectionContext(),
            providerResolver: { _ in provider }
        )

        #expect(result == nil)
        #expect(provider.requests.isEmpty)
    }

    @Test("빈 입력은 provider를 호출하지 않고 nil을 반환한다")
    func emptyInputSkipsCorrection() async {
        let service = makeService(selectedProvider: .gptAPI)
        let provider = StubCorrectionProvider()

        let result = await service.correct(
            text: "",
            context: LLMCorrectionContext(),
            providerResolver: { _ in provider }
        )

        #expect(result == nil)
        #expect(provider.requests.isEmpty)
    }

    private func makeService(selectedProvider: LLMProviderSelection) -> LLMCorrectionService {
        let service = LLMCorrectionService(defaults: InMemoryUserDefaults())
        service.selectedProvider = selectedProvider
        return service
    }
}

private final class StubCorrectionProvider: LLMTextGenerationProvider, @unchecked Sendable {
    let descriptor: LLMProviderDescriptor
    private let responseText: String
    private let error: Error?
    private let lock = NSLock()
    private var recordedRequests: [LLMTextRequest] = []

    var requests: [LLMTextRequest] {
        lock.withLock { recordedRequests }
    }

    init(
        responseText: String = "교정된 문장",
        error: Error? = nil,
        supportedCapabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .correction]
    ) {
        self.responseText = responseText
        self.error = error
        self.descriptor = LLMProviderDescriptor(
            id: .gpt,
            description: "테스트 provider",
            authKind: .apiKey,
            supportedCapabilities: supportedCapabilities
        )
    }

    func isConfigured() async -> Bool {
        true
    }

    func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(models: [], source: .manualOnly)
    }

    func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        lock.withLock {
            recordedRequests.append(request)
        }
        if let error {
            throw error
        }
        return LLMTextResponse(text: responseText, providerID: .gpt, modelID: "stub-correction")
    }
}
