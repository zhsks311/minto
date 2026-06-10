import Foundation
import Testing
@testable import MintoCore

@Suite("MeetingSearchAnswerRerank")
struct MeetingSearchAnswerRerankTests {

    // MARK: - 헬퍼

    private func sampleRecord() -> MeetingRecord {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return MeetingRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "db 스키마 형상 관리",
            startedAt: startedAt,
            durationSeconds: 120,
            summary: MeetingSummary(
                leadAnswer: "liquibase로 스키마를 관리한다.",
                sections: [
                    .init(title: "liquibase 방식", time: "00:30", points: [
                        .init(text: "DDL을 XML로 관리한다.", subPoints: [])
                    ])
                ]
            ),
            transcript: [
                Segment(text: "liquibase 적용 순서를 정리한다.", timestamp: startedAt, duration: 5)
            ]
        )
    }

    // MARK: - ollama 임베딩 성공 경로

    @Test("ollama 임베딩 성공 시 재랭킹이 적용되고 답변 생성이 완료된다")
    func ollamaEmbeddingSuccessPathCompletesAnswer() async throws {
        // ollama /api/embeddings 응답과 /api/generate 응답을 모두 처리하는 transport
        let embeddingVector = (0..<8).map { Double($0) / 8.0 }
        let embeddingJSON = try JSONSerialization.data(withJSONObject: ["embedding": embeddingVector])
        let generateJSON = Data(#"{"model":"test-model","response":"liquibase로 관리한다. [1]","done":true,"done_reason":"stop"}"#.utf8)

        let transport = RoutingTransport(
            embeddingData: embeddingJSON,
            generateData: generateJSON
        )
        let localProvider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:11434")!,
                modelID: "test-model",
                compatibility: .ollamaGenerate
            ),
            transport: transport
        )
        let textProvider = StubTextProvider(responseText: "liquibase로 관리한다. [1]")
        let useCase = MeetingSearchAnswerUseCase(maxChunks: 3, semanticRerankCandidateCount: 4)

        let answer = try await useCase.answer(
            query: "liquibase",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: textProvider,
            embeddingProvider: localProvider
        )

        #expect(!answer.text.isEmpty)
        #expect(!answer.citations.isEmpty)
        // 임베딩 요청이 실제로 발생했는지 확인 (쿼리 1개 + 청크 N개)
        #expect(transport.embeddingRequestCount >= 1)
    }

    // MARK: - 임베딩 실패 시 fallback

    @Test("ollama 임베딩 실패 시 원 순서 그대로 답변 생성을 진행한다")
    func ollamaEmbeddingFailureFallsBackAndContinues() async throws {
        let transport = FailingEmbeddingTransport()
        let localProvider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:11434")!,
                modelID: "test-model",
                compatibility: .ollamaGenerate
            ),
            transport: transport
        )
        let textProvider = StubTextProvider(responseText: "fallback 답변입니다. [1]")
        let useCase = MeetingSearchAnswerUseCase(maxChunks: 3, semanticRerankCandidateCount: 4)

        // 임베딩 실패해도 답변 생성은 성공해야 함
        let answer = try await useCase.answer(
            query: "liquibase",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: textProvider,
            embeddingProvider: localProvider
        )

        #expect(!answer.text.isEmpty)
        #expect(!answer.citations.isEmpty)
    }

    // MARK: - openAIChatCompletions 모드 fallback

    @Test("openAIChatCompletions 모드의 LocalLLMProvider는 임베딩 미지원으로 LocalHash fallback이 된다")
    func openAICompatibleProviderFallsBackToLocalHash() async throws {
        let transport = RecordingTransport(data: Data(#"{"model":"m","response":"답변 [1]","done":true}"#.utf8))
        let localProvider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:11434")!,
                modelID: "test-model",
                compatibility: .openAIChatCompletions
            ),
            transport: transport
        )
        let textProvider = StubTextProvider(responseText: "답변 [1]")
        let useCase = MeetingSearchAnswerUseCase(maxChunks: 3)

        // openAIChatCompletions은 generateEmbedding에서 .notConfigured를 throw하므로
        // semanticRerank 내부에서 LocalHash로 fallback → 답변 생성 진행
        let answer = try await useCase.answer(
            query: "liquibase",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: textProvider,
            embeddingProvider: localProvider
        )

        #expect(!answer.text.isEmpty)
    }

    // MARK: - 임베딩 타임아웃 → fail-soft

    @Test("임베딩이 타임아웃을 초과하면 원 results로 즉시 답변 생성을 진행한다")
    func embeddingTimeoutFallsBackImmediately() async throws {
        // 60초 대기하는 느린 transport — semanticRerankTimeoutSeconds=0.1 로 빠르게 타임아웃 발생
        let transport = SlowEmbeddingTransport(delaySeconds: 60)
        let localProvider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:11434")!,
                modelID: "test-model",
                compatibility: .ollamaGenerate
            ),
            transport: transport
        )
        let textProvider = StubTextProvider(responseText: "타임아웃 후 fallback 답변. [1]")
        // 집합 타임아웃을 0.1초로 주입 — 테스트가 오래 걸리지 않는다
        let useCase = MeetingSearchAnswerUseCase(maxChunks: 3, semanticRerankTimeoutSeconds: 0.1)

        let start = Date()
        let answer = try await useCase.answer(
            query: "liquibase",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: textProvider,
            embeddingProvider: localProvider
        )
        let elapsed = Date().timeIntervalSince(start)

        // 타임아웃 후 원 results로 즉시 진행하므로 답변이 생성되어야 한다
        #expect(!answer.text.isEmpty)
        // 60초 대기가 아니라 타임아웃(0.1초) + 여유분(2초) 이내에 완료되어야 한다
        #expect(elapsed < 2.0, "타임아웃 초과 시 즉시 fallback이 되어야 함 (elapsed: \(elapsed)s)")
    }

    // MARK: - embeddingProvider nil이면 LocalHash 사용

    @Test("embeddingProvider가 nil이면 LocalHash로 재랭킹하고 답변을 생성한다")
    func nilEmbeddingProviderUsesLocalHash() async throws {
        let textProvider = StubTextProvider(responseText: "LocalHash 재랭킹 답변. [1]")
        let useCase = MeetingSearchAnswerUseCase(maxChunks: 3)

        let answer = try await useCase.answer(
            query: "liquibase",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: textProvider,
            embeddingProvider: nil
        )

        #expect(!answer.text.isEmpty)
        #expect(!answer.citations.isEmpty)
    }
}

// MARK: - 테스트 스텁

/// 쿼리 경로(/api/embeddings vs /api/generate)로 응답을 분기하는 transport
private final class RoutingTransport: LLMAPITransport, @unchecked Sendable {
    private let embeddingData: Data
    private let generateData: Data
    private let lock = NSLock()
    private var _embeddingRequestCount = 0

    var embeddingRequestCount: Int {
        lock.withLock { _embeddingRequestCount }
    }

    init(embeddingData: Data, generateData: Data) {
        self.embeddingData = embeddingData
        self.generateData = generateData
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let isEmbedding = request.url?.path.hasSuffix("embeddings") == true
        if isEmbedding {
            lock.withLock { _embeddingRequestCount += 1 }
        }
        let responseData = isEmbedding ? embeddingData : generateData
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

/// 모든 요청에서 네트워크 오류를 발생시키는 transport
private struct FailingEmbeddingTransport: LLMAPITransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw LLMProviderError.network("테스트 네트워크 오류")
    }
}

/// 요청을 기록하는 transport
private final class RecordingTransport: LLMAPITransport, @unchecked Sendable {
    private let responseData: Data
    private(set) var requests: [URLRequest] = []

    init(data: Data) {
        self.responseData = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

/// 지정한 시간 동안 응답을 지연하는 transport — 타임아웃 테스트용
private struct SlowEmbeddingTransport: LLMAPITransport {
    let delaySeconds: TimeInterval

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        throw LLMProviderError.network("SlowEmbeddingTransport: 타임아웃 이전에 완료되면 안 됨")
    }
}

/// 텍스트 생성 스텁
private final class StubTextProvider: LLMTextGenerationProvider, @unchecked Sendable {
    let descriptor: LLMProviderDescriptor
    private let responseText: String

    init(responseText: String) {
        self.responseText = responseText
        self.descriptor = LLMProviderDescriptor(
            id: .gpt,
            description: "테스트 text provider",
            authKind: .apiKey,
            supportedCapabilities: [.textGeneration, .answer]
        )
    }

    func isConfigured() async -> Bool { true }

    func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(models: [], source: .bundledFallback)
    }

    func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        LLMTextResponse(text: responseText, providerID: .gpt, modelID: "stub")
    }
}
