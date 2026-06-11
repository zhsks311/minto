import Foundation

public struct MeetingSearchAnswerCitation: Identifiable, Sendable, Equatable {
    public let number: Int
    public let chunkID: String
    public let meetingID: UUID
    public let meetingTitle: String
    public let kind: MeetingSearchChunk.Kind
    public let label: String
    public let sourcePath: String
    public let time: String
    public let preview: String

    public var id: String { chunkID }
}

public struct MeetingSearchAnswer: Sendable, Equatable {
    public let query: String
    public let text: String
    public let citations: [MeetingSearchAnswerCitation]
    public let providerID: LLMProviderID
    public let modelID: String
    public let warnings: [String]
}

public enum MeetingSearchAnswerError: Error, Sendable, Equatable {
    case emptyQuery
    case noResults
    case providerNotConfigured
    case providerUnsupported
    case emptyAnswer
    case generationFailed(String)
}

extension MeetingSearchAnswerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "검색어를 먼저 입력하세요."
        case .noResults:
            return "답변에 사용할 회의 근거를 찾지 못했어요."
        case .providerNotConfigured:
            return "AI 연결 설정이 필요해요."
        case .providerUnsupported:
            return "현재 AI 서비스는 검색 답변을 지원하지 않아요."
        case .emptyAnswer:
            return "AI가 빈 답변을 반환했어요."
        case .generationFailed(let message):
            return message
        }
    }
}

public struct MeetingSearchAnswerUseCase: Sendable {
    /// 랭킹에는 유용하지만 인용 근거로는 빈 껍데기인 메타데이터 chunk 종류.
    /// (제목 chunk의 preview는 제목 그 자체라 근거 카드에 같은 문장이 반복된다)
    public static let metadataKinds: Set<MeetingSearchChunk.Kind> = [.title, .topic, .keywords]

    public let maxChunks: Int
    public let maxContextCharacters: Int
    public let maxChunksPerMeeting: Int
    /// 답변 생성 시 의미 재랭킹에 사용할 후보 상위 N개.
    public let semanticRerankCandidateCount: Int
    /// 의미 재랭킹 전체(쿼리+청크 임베딩) 집합 타임아웃(초).
    /// 초과 시 즉시 원 results로 진행(fail-soft). 테스트에서 작은 값으로 주입 가능.
    public let semanticRerankTimeoutSeconds: TimeInterval

    public init(
        maxChunks: Int = 8,
        maxContextCharacters: Int = 5_000,
        maxChunksPerMeeting: Int = 3,
        semanticRerankCandidateCount: Int = 16,
        semanticRerankTimeoutSeconds: TimeInterval = 5
    ) {
        self.maxChunks = max(1, maxChunks)
        self.maxContextCharacters = max(500, maxContextCharacters)
        self.maxChunksPerMeeting = max(1, maxChunksPerMeeting)
        self.semanticRerankCandidateCount = max(1, semanticRerankCandidateCount)
        self.semanticRerankTimeoutSeconds = max(0.01, semanticRerankTimeoutSeconds)
    }

    public func retrieve(query: String, index: MeetingSearchIndex) -> [MeetingSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return index.search(trimmed, limit: maxChunks * 3)
    }

    public func answer(
        query: String,
        index: MeetingSearchIndex,
        provider: any LLMTextGenerationProvider,
        embeddingProvider: (any LLMEmbeddingProvider)? = nil
    ) async throws -> MeetingSearchAnswer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingSearchAnswerError.emptyQuery }
        return try await answer(
            query: trimmed,
            results: retrieve(query: trimmed, index: index),
            provider: provider,
            embeddingProvider: embeddingProvider
        )
    }

    public func answer(
        query: String,
        results: [MeetingSearchResult],
        provider: any LLMTextGenerationProvider,
        embeddingProvider: (any LLMEmbeddingProvider)? = nil
    ) async throws -> MeetingSearchAnswer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingSearchAnswerError.emptyQuery }
        // 답변 생성 직전에 의미 재랭킹 — 실패 시 원 results 그대로 진행(fail-soft)
        let rerankedResults = await semanticRerank(query: trimmed, results: results, embeddingProvider: embeddingProvider)
        let context = contextBlock(from: rerankedResults)
        guard !context.citations.isEmpty else { throw MeetingSearchAnswerError.noResults }
        guard provider.descriptor.supportedCapabilities.contains(.answer) else {
            throw MeetingSearchAnswerError.providerUnsupported
        }
        guard await provider.isConfigured() else { throw MeetingSearchAnswerError.providerNotConfigured }
        let prompt = AnswerPrompt.build(query: trimmed, context: context.text)

        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: .answer,
                instructions: prompt.instructions,
                userContent: prompt.userContent
            ))
            let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw MeetingSearchAnswerError.emptyAnswer }
            return MeetingSearchAnswer(
                query: trimmed,
                text: text,
                citations: context.citations,
                providerID: response.providerID,
                modelID: response.modelID,
                warnings: response.warnings
            )
        } catch let error as MeetingSearchAnswerError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as LLMProviderError {
            throw MeetingSearchAnswerError.generationFailed(error.userMessage)
        } catch {
            throw MeetingSearchAnswerError.generationFailed(error.localizedDescription)
        }
    }

    /// 인용 후보 선별: 메타데이터 chunk 제외 + 회의당 상한으로 같은 회의 도배를 막는다.
    /// 검색어가 제목/주제에만 걸린 경우는 근거가 비어버리므로 원본 결과로 폴백한다.
    func citationCandidates(from results: [MeetingSearchResult]) -> [MeetingSearchResult] {
        let contentResults = results.filter { !Self.metadataKinds.contains($0.chunk.kind) }
        let pool = contentResults.isEmpty ? results : contentResults

        var perMeetingCount: [UUID: Int] = [:]
        var selected: [MeetingSearchResult] = []
        for result in pool {
            guard selected.count < maxChunks else { break }
            let count = perMeetingCount[result.meetingID, default: 0]
            guard count < maxChunksPerMeeting else { continue }
            perMeetingCount[result.meetingID] = count + 1
            selected.append(result)
        }
        return selected
    }

    private func contextBlock(from results: [MeetingSearchResult]) -> (text: String, citations: [MeetingSearchAnswerCitation]) {
        var blocks: [String] = []
        var citations: [MeetingSearchAnswerCitation] = []
        var usedCharacters = 0

        for result in citationCandidates(from: results) {
            let number = citations.count + 1
            let block = Self.citationBlock(number: number, result: result)
            let separatorLength = blocks.isEmpty ? 0 : 2
            if usedCharacters + separatorLength + block.count > maxContextCharacters {
                if blocks.isEmpty {
                    let truncated = String(block.prefix(maxContextCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
                    blocks.append(truncated)
                    citations.append(Self.citation(number: number, result: result))
                }
                break
            }
            blocks.append(block)
            usedCharacters += separatorLength + block.count
            citations.append(Self.citation(number: number, result: result))
        }

        return (blocks.joined(separator: "\n\n"), citations)
    }

    private static func citationBlock(number: Int, result: MeetingSearchResult) -> String {
        let chunk = result.chunk
        let time = chunk.time.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeLine = time.isEmpty ? "" : "\n구간: \(time)"
        return """
        [\(number)]
        회의: \(chunk.meetingTitle)
        종류: \(chunk.kind.label)\(timeLine)
        내용:
        \(chunk.text)
        """
    }

    private static func citation(number: Int, result: MeetingSearchResult) -> MeetingSearchAnswerCitation {
        let chunk = result.chunk
        return MeetingSearchAnswerCitation(
            number: number,
            chunkID: chunk.id,
            meetingID: chunk.meetingID,
            meetingTitle: chunk.meetingTitle,
            kind: chunk.kind,
            label: result.label,
            sourcePath: chunk.sourcePath,
            time: chunk.time,
            preview: result.preview
        )
    }

    /// 상위 후보를 on-demand 임베딩해 의미 재랭킹한다.
    /// 청크 임베딩은 withThrowingTaskGroup으로 병렬 실행하고, 전체 집합 타임아웃(semanticRerankTimeoutSeconds)
    /// 초과 시 즉시 원 results로 진행(fail-soft — 답변 생성을 절대 막지 않는다).
    ///
    /// - Parameters:
    ///   - embeddingProvider: 의미 임베딩 공급자. nil이면 fallbackProvider를 사용.
    ///   - fallbackProvider: embeddingProvider가 nil이거나 실패 시 대체 공급자. 기본값 LocalHashEmbeddingProvider.
    private func semanticRerank(
        query: String,
        results: [MeetingSearchResult],
        embeddingProvider: (any LLMEmbeddingProvider)?,
        fallbackProvider: any LLMEmbeddingProvider = LocalHashEmbeddingProvider()
    ) async -> [MeetingSearchResult] {
        let provider: any LLMEmbeddingProvider = embeddingProvider ?? fallbackProvider
        let candidates = Array(results.prefix(semanticRerankCandidateCount))
        guard !candidates.isEmpty else { return results }

        do {
            return try await withEmbeddingTimeout(seconds: semanticRerankTimeoutSeconds) {
                // 쿼리 벡터 1개
                let queryResponse = try await provider.generateEmbedding(
                    LLMEmbeddingRequest(input: query, sourceID: nil)
                )
                // 후보 청크 벡터 병렬화
                let records: [MeetingSearchEmbeddingRecord] = try await withThrowingTaskGroup(
                    of: MeetingSearchEmbeddingRecord.self
                ) { group in
                    for result in candidates {
                        group.addTask {
                            let response = try await provider.generateEmbedding(
                                LLMEmbeddingRequest(input: result.chunk.text, sourceID: result.chunk.id)
                            )
                            return MeetingSearchEmbeddingRecord(
                                chunkID: result.chunk.id,
                                meetingID: result.chunk.meetingID,
                                providerID: response.providerID,
                                modelID: response.modelID,
                                embeddingKind: response.kind,
                                vector: response.vector
                            )
                        }
                    }
                    var collected: [MeetingSearchEmbeddingRecord] = []
                    collected.reserveCapacity(candidates.count)
                    for try await record in group { collected.append(record) }
                    return collected
                }
                let embeddingIndex = MeetingSearchEmbeddingIndex(
                    providerID: queryResponse.providerID,
                    modelID: queryResponse.modelID,
                    embeddingKind: queryResponse.kind,
                    dimensions: queryResponse.vector.count,
                    records: records
                )
                // 상위 candidates만 재랭킹하고, 나머지는 원순위 그대로 뒤에 붙인다
                let rerankedCandidates = MeetingSearchEmbeddingIndex.rerank(
                    results: candidates,
                    queryVector: queryResponse.vector,
                    embeddings: embeddingIndex
                )
                return rerankedCandidates + results.dropFirst(self.semanticRerankCandidateCount)
            }
        } catch {
            // 타임아웃·임베딩 실패 모두 → 원 results 반환, 답변 생성 진행
            return results
        }
    }

    /// 주어진 작업에 집합 타임아웃을 적용한다.
    /// 타임아웃 초과 시 CancellationError를 throw해 호출측 catch에서 fail-soft 처리한다.
    private func withEmbeddingTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            // 먼저 완료된 쪽을 채택하고 나머지 Task를 취소한다
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
