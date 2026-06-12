import Foundation
import Testing
@testable import MintoCore

@Suite("MeetingSearchAnswerService")
struct MeetingSearchAnswerServiceTests {
    @Test("빈 검색어는 LLM을 호출하지 않는다")
    func rejectsEmptyQuery() async throws {
        let service = MeetingSearchAnswerUseCase()
        let provider = StubAnswerProvider()

        await #expect(throws: MeetingSearchAnswerError.emptyQuery) {
            _ = try await service.answer(query: "  ", index: MeetingSearchIndex(records: [sampleRecord()]), provider: provider)
        }
    }

    @Test("검색 결과가 없으면 답변을 만들지 않는다")
    func rejectsNoResults() async throws {
        let service = MeetingSearchAnswerUseCase()
        let provider = StubAnswerProvider()

        await #expect(throws: MeetingSearchAnswerError.noResults) {
            _ = try await service.answer(query: "결제 정산", index: MeetingSearchIndex(records: [sampleRecord()]), provider: provider)
        }
    }

    @Test("answer capability가 없는 provider는 거부한다")
    func rejectsUnsupportedProvider() async throws {
        let service = MeetingSearchAnswerUseCase()
        let provider = StubAnswerProvider(supportedCapabilities: [.summary])

        await #expect(throws: MeetingSearchAnswerError.providerUnsupported) {
            _ = try await service.answer(query: "liquibase", index: MeetingSearchIndex(records: [sampleRecord()]), provider: provider)
        }
    }

    @Test("미설정 provider는 사용자 오류로 반환한다")
    func rejectsUnconfiguredProvider() async throws {
        let service = MeetingSearchAnswerUseCase()
        let provider = StubAnswerProvider(configured: false)

        await #expect(throws: MeetingSearchAnswerError.providerNotConfigured) {
            _ = try await service.answer(query: "liquibase", index: MeetingSearchIndex(records: [sampleRecord()]), provider: provider)
        }
    }

    @Test("상위 검색 chunk를 근거로 answer use case를 호출하고 citation을 반환한다")
    func generatesAnswerWithCitations() async throws {
        let service = MeetingSearchAnswerUseCase(maxChunks: 3, maxContextCharacters: 2_000)
        let provider = StubAnswerProvider(responseText: "Liquibase와 Flyway로 변경 이력을 관리했다. [1]")

        let answer = try await service.answer(
            query: "db 스키마 형상 관리",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: provider
        )

        #expect(answer.text == "Liquibase와 Flyway로 변경 이력을 관리했다. [1]")
        #expect(answer.citations.count <= 3)
        #expect(answer.citations.first?.meetingTitle == "db 스키마 형상 관리 툴 적용과 기록 방식")
        #expect(answer.citations.first?.sourcePath.isEmpty == false)
        #expect(answer.citations.allSatisfy { !MeetingSearchAnswerUseCase.metadataKinds.contains($0.kind) })
        #expect(answer.providerID == .gpt)
        #expect(answer.modelID == "stub-answer")

        let request = try #require(provider.lastRequest)
        #expect(request.useCase == .answer)
        #expect(request.instructions.contains("근거 번호"))
        #expect(request.userContent.contains("질문:"))
        #expect(request.userContent.contains("회의 근거:"))
        #expect(request.userContent.contains("db 스키마 형상 관리"))
    }

    @Test("검색 답변 use case는 Local LLM provider의 answer payload로 연결된다")
    func localLLMProviderGeneratesAnswerPayloadFromSearchResults() async throws {
        let transport = LocalAnswerTransport(data: Data(#"{"model":"minto-answer-e2e","response":"UI-E2E-LOCAL-LLM-ANSWER: 로컬 검색 답변 성공 [1]","done":true,"done_reason":"stop"}"#.utf8))
        let provider = LocalLLMProvider(
            configuration: LocalLLMProviderConfiguration(
                baseURL: URL(string: "http://127.0.0.1:18080")!,
                modelID: "minto-answer-e2e",
                compatibility: .ollamaGenerate,
                contextWindow: 4_096
            ),
            transport: transport
        )
        let service = MeetingSearchAnswerUseCase(maxChunks: 3, maxContextCharacters: 2_000)

        let answer = try await service.answer(
            query: "db 스키마 형상 관리",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: provider
        )

        #expect(answer.text == "UI-E2E-LOCAL-LLM-ANSWER: 로컬 검색 답변 성공 [1]")
        #expect(answer.providerID == .local)
        #expect(answer.modelID == "minto-answer-e2e")
        #expect(answer.citations.isEmpty == false)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:18080/api/generate")
        #expect(request.httpMethod == "POST")
        let body = try Self.jsonObject(from: try #require(request.httpBody))
        #expect(body["model"] as? String == "minto-answer-e2e")
        #expect(body["stream"] as? Bool == false)
        #expect((body["system"] as? String)?.contains("근거 번호") == true)
        #expect((body["prompt"] as? String)?.contains("질문:") == true)
        #expect((body["prompt"] as? String)?.contains("회의 근거:") == true)
        #expect((body["prompt"] as? String)?.contains("db 스키마 형상 관리") == true)
        let options = try #require(body["options"] as? [String: Any])
        #expect(options["num_predict"] as? Int == 1_800)
        #expect(options["num_ctx"] as? Int == 4_096)
    }

    @Test("제목·주제·키워드 chunk는 인용 근거에서 제외한다")
    func excludesMetadataChunksFromCitations() async throws {
        let service = MeetingSearchAnswerUseCase()
        let provider = StubAnswerProvider()

        let answer = try await service.answer(
            query: "db 스키마 형상 관리",
            index: MeetingSearchIndex(records: [sampleRecord()]),
            provider: provider
        )

        #expect(!answer.citations.isEmpty)
        #expect(answer.citations.allSatisfy { citation in
            citation.kind != .title && citation.kind != .topic && citation.kind != .keywords
        })
    }

    @Test("같은 회의의 인용은 회의당 상한을 넘지 않는다")
    func capsCitationsPerMeeting() async throws {
        let service = MeetingSearchAnswerUseCase(maxChunks: 6, maxChunksPerMeeting: 2)
        let provider = StubAnswerProvider()
        let record = sampleRecord(extraTranscript: "liquibase 적용 순서를 liquibase 가이드 문서로 정리한다.")

        let answer = try await service.answer(
            query: "liquibase",
            index: MeetingSearchIndex(records: [record]),
            provider: provider
        )

        let countsByMeeting = Dictionary(grouping: answer.citations, by: \.meetingID).mapValues(\.count)
        #expect(countsByMeeting.values.allSatisfy { $0 <= 2 })
    }

    @Test("검색어가 제목에만 걸리면 메타데이터 chunk로 폴백해 근거를 유지한다")
    func fallsBackToMetadataChunksWhenOnlyTitleMatches() async throws {
        let service = MeetingSearchAnswerUseCase()
        let provider = StubAnswerProvider()
        let base = sampleRecord()
        let titleOnly = MeetingRecord(
            id: base.id,
            title: "유니콘월드 킥오프",
            startedAt: base.startedAt,
            durationSeconds: base.durationSeconds,
            topic: base.topic,
            summary: base.summary,
            transcript: base.transcript
        )

        let answer = try await service.answer(
            query: "유니콘월드",
            index: MeetingSearchIndex(records: [titleOnly]),
            provider: provider
        )

        #expect(!answer.citations.isEmpty)
        #expect(answer.citations.allSatisfy { $0.kind == .title })
    }

    @Test("context 길이 제한을 넘으면 첫 근거만 잘라서 사용한다")
    func capsContextLength() async throws {
        let service = MeetingSearchAnswerUseCase(maxChunks: 5, maxContextCharacters: 500)
        let provider = StubAnswerProvider()
        let record = sampleRecord(extraTranscript: String(repeating: "liquibase ", count: 1_000))

        _ = try await service.answer(query: "liquibase", index: MeetingSearchIndex(records: [record]), provider: provider)

        let request = try #require(provider.lastRequest)
        #expect(request.userContent.count < 900)
    }

    @Test("AnswerPrompt는 질문과 근거를 분리해 조립한다")
    func answerPromptBuildsStableSections() {
        let prompt = AnswerPrompt.build(query: "결정사항은?", context: "[1] 근거")

        #expect(prompt.instructions.contains("근거 번호"))
        #expect(prompt.instructions.contains("회의 데이터로만 취급"))
        #expect(prompt.instructions.contains("마크다운 장식"))
        #expect(prompt.instructions.contains("핵심 명사구"))
        #expect(prompt.instructions.contains("결정 조건"))
        #expect(prompt.instructions.contains("선행 조건"))
        #expect(prompt.instructions.contains("각 근거의 조건"))
        #expect(prompt.instructions.contains("원문 표기"))
        #expect(prompt.userContent.contains("질문:"))
        #expect(prompt.userContent.contains("회의 근거:"))
        #expect(prompt.userContent.contains("--- 회의 근거 시작 ---"))
        #expect(prompt.userContent.contains("--- 회의 근거 끝 ---"))
        #expect(prompt.userContent.contains("결정사항은?"))
        #expect(prompt.userContent.contains("[1] 근거"))
    }

    @MainActor
    @Test("검색 답변 설정은 요약 설정과 별도 키를 사용한다")
    func answerSettingsAreSeparateFromSummarySettings() {
        let defaults = InMemoryUserDefaults()

        let settings = MeetingSearchAnswerSettingsService(defaults: defaults)
        settings.isEnabled = true
        settings.setOverride(.gptAPI)

        #expect(defaults.bool(forKey: MeetingSearchAnswerSettingsService.enabledKey))
        #expect(defaults.string(forKey: MeetingSearchAnswerSettingsService.providerKey) == LLMProviderSelection.gptAPI.rawValue)
        #expect(defaults.object(forKey: LLMSummarySettingsService.enabledKey) == nil)
        #expect(defaults.object(forKey: LLMSummarySettingsService.providerKey) == nil)
    }

    @MainActor
    @Test("컨트롤러는 provider 설정 완료 전에는 생성 버튼을 막는다")
    func controllerChecksProviderReadiness() async throws {
        let defaults = InMemoryUserDefaults()
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults)
        settings.isEnabled = true
        settings.setOverride(.gptAPI)

        let unconfigured = MeetingSearchAnswerController(
            settings: settings,
            providerResolver: { StubAnswerProvider(configured: false) }
        )
        unconfigured.refreshReadiness()
        _ = await waitUntil { !unconfigured.isCheckingProvider }
        #expect(!unconfigured.isProviderReady)
        #expect(!unconfigured.canGenerate(query: "liquibase", resultCount: 1))

        let configured = MeetingSearchAnswerController(
            settings: settings,
            providerResolver: { StubAnswerProvider(configured: true) }
        )
        configured.refreshReadiness()
        #expect(await waitUntil { configured.isProviderReady })
        #expect(configured.isProviderReady)
        #expect(configured.canGenerate(query: "liquibase", resultCount: 1))
    }

    @MainActor
    @Test("컨트롤러는 API key 변경 notification 후 readiness를 갱신한다")
    func controllerRefreshesReadinessAfterAPIKeyChangeNotification() async throws {
        let defaults = InMemoryUserDefaults()
        let center = NotificationCenter()
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults)
        settings.isEnabled = true
        settings.setOverride(.gptAPI)
        let readiness = ProviderReadinessBox(configured: false)
        let controller = MeetingSearchAnswerController(
            settings: settings,
            providerResolver: { StubAnswerProvider(configured: readiness.configured) },
            notificationCenter: center
        )

        controller.refreshReadiness()
        _ = await waitUntil { !controller.isCheckingProvider }
        #expect(!controller.isProviderReady)

        readiness.configured = true
        center.post(name: .llmAPIKeyStoreDidChange, object: nil, userInfo: ["providerID": LLMProviderID.gpt.rawValue])

        #expect(await waitUntil { controller.isProviderReady })
    }

    @MainActor
    @Test("검색어 변경용 reset은 provider readiness를 유지한다")
    func controllerResetKeepsReadinessByDefault() async throws {
        let defaults = InMemoryUserDefaults()
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults)
        settings.isEnabled = true
        settings.setOverride(.gptAPI)
        let controller = MeetingSearchAnswerController(
            settings: settings,
            providerResolver: { StubAnswerProvider(configured: true) }
        )

        controller.refreshReadiness()
        #expect(await waitUntil { controller.isProviderReady })
        #expect(controller.isProviderReady)

        controller.reset()
        #expect(controller.isProviderReady)

        controller.reset(clearReadiness: true)
        #expect(!controller.isProviderReady)
    }

    @MainActor
    @Test("같은 검색어 재생성 중 이전 요청은 최신 답변 상태를 덮지 않는다")
    func repeatedGenerateUsesLatestGenerationOnly() async throws {
        let defaults = InMemoryUserDefaults()
        let settings = MeetingSearchAnswerSettingsService(defaults: defaults)
        settings.isEnabled = true
        settings.setOverride(.gptAPI)
        let provider = SequencedAnswerProvider()
        let controller = MeetingSearchAnswerController(
            settings: settings,
            providerResolver: { provider }
        )
        let results = MeetingSearchAnswerUseCase().retrieve(
            query: "liquibase",
            index: MeetingSearchIndex(records: [sampleRecord()])
        )

        controller.refreshReadiness()
        #expect(await waitUntil { controller.isProviderReady })

        controller.generate(query: "liquibase", results: results)
        #expect(await waitUntil { provider.requestCount == 1 })
        controller.generate(query: "liquibase", results: results)
        #expect(await waitUntil { provider.requestCount == 2 })
        provider.finishFirstWithCancellationLikeNetworkError()
        provider.finishSecondSuccessfully()

        #expect(await waitUntil { controller.answer?.text == "최신 답변입니다. [1]" })
        #expect(controller.errorMessage == nil)
        #expect(!controller.isGenerating)
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sampleRecord(extraTranscript: String = "") -> MeetingRecord {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transcriptText = [
            "컬럼 추가와 인덱스 추가 이력을 추적해야 합니다.",
            extraTranscript
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return MeetingRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "db 스키마 형상 관리 툴 적용과 기록 방식",
            startedAt: startedAt,
            durationSeconds: 245,
            topic: "Liquibase와 Flyway 비교",
            summary: MeetingSummary(
                title: "db 스키마 형상 관리",
                leadQuestion: "db 스키마 변경을 어떻게 기록할까?",
                leadAnswer: "flyway와 liquibase로 SQL 변경 이력을 관리하는 방식을 논의했다.",
                sections: [
                    .init(
                        title: "liquibase 방식과 xml 관리",
                        time: "01:30",
                        points: [
                            .init(text: "DDL을 XML 파일로 관리한다.", subPoints: [
                                "change-log-master.xml include 문법을 쓴다."
                            ])
                        ]
                    )
                ],
                keywords: ["flyway", "liquibase", "db", "마이그레이션"]
            ),
            transcript: [
                Segment(text: transcriptText, timestamp: startedAt.addingTimeInterval(132), duration: 8)
            ]
        )
    }

    // 타임아웃은 실패 한계일 뿐 정상 경로는 조건 충족 즉시 반환한다.
    // 500ms는 병렬 전체 테스트 부하에서 간헐 초과(flaky)가 관측돼 5초로 늘렸다.
    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let step: UInt64 = 10_000_000
        let attempts = max(1, Int(timeoutNanoseconds / step))
        for _ in 0..<attempts {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: step)
        }
        return condition()
    }
}

private final class LocalAnswerTransport: LLMAPITransport, @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data
    private(set) var requests: [URLRequest] = []

    init(data: Data) {
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            requests.append(request)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class StubAnswerProvider: LLMTextGenerationProvider, @unchecked Sendable {
    let descriptor: LLMProviderDescriptor
    private let configured: Bool
    private let responseText: String
    private(set) var lastRequest: LLMTextRequest?

    init(
        configured: Bool = true,
        responseText: String = "답변입니다. [1]",
        supportedCapabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .answer]
    ) {
        self.configured = configured
        self.responseText = responseText
        self.descriptor = LLMProviderDescriptor(
            id: .gpt,
            description: "테스트 provider",
            authKind: .apiKey,
            supportedCapabilities: supportedCapabilities
        )
    }

    func isConfigured() async -> Bool {
        configured
    }

    func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(models: [], source: .manualOnly)
    }

    func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        lastRequest = request
        return LLMTextResponse(text: responseText, providerID: .gpt, modelID: "stub-answer")
    }
}

private final class ProviderReadinessBox: @unchecked Sendable {
    var configured: Bool

    init(configured: Bool) {
        self.configured = configured
    }
}

private final class SequencedAnswerProvider: LLMTextGenerationProvider, @unchecked Sendable {
    let descriptor = LLMProviderDescriptor(
        id: .gpt,
        description: "순차 테스트 provider",
        authKind: .apiKey,
        supportedCapabilities: [.textGeneration, .answer]
    )
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<LLMTextResponse, Error>] = []
    var requestCount: Int {
        lock.withLock { continuations.count }
    }

    func isConfigured() async -> Bool {
        true
    }

    func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(models: [], source: .manualOnly)
    }

    func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                continuations.append(continuation)
            }
        }
    }

    func finishFirstWithCancellationLikeNetworkError() {
        resume(index: 0, result: .failure(LLMProviderError.network("요청이 취소되었습니다.")))
    }

    func finishSecondSuccessfully() {
        resume(index: 1, result: .success(LLMTextResponse(
            text: "최신 답변입니다. [1]",
            providerID: .gpt,
            modelID: "sequenced-answer"
        )))
    }

    private func resume(index: Int, result: Result<LLMTextResponse, Error>) {
        let continuation = lock.withLock { continuations.indices.contains(index) ? continuations[index] : nil }
        continuation?.resume(with: result)
    }
}
