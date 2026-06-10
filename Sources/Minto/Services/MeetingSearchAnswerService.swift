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
            return "답변에 사용할 회의 근거를 찾지 못했습니다."
        case .providerNotConfigured:
            return "AI 연결 설정이 필요합니다."
        case .providerUnsupported:
            return "현재 AI 서비스는 검색 답변을 지원하지 않습니다."
        case .emptyAnswer:
            return "AI가 빈 답변을 반환했습니다."
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

    public init(
        maxChunks: Int = 8,
        maxContextCharacters: Int = 5_000,
        maxChunksPerMeeting: Int = 3,
        semanticRerankCandidateCount: Int = 16
    ) {
        self.maxChunks = max(1, maxChunks)
        self.maxContextCharacters = max(500, maxContextCharacters)
        self.maxChunksPerMeeting = max(1, maxChunksPerMeeting)
        self.semanticRerankCandidateCount = max(1, semanticRerankCandidateCount)
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
    /// 임베딩 실패·미설정이면 원 results 그대로 반환(fail-soft — 답변 생성을 절대 막지 않는다).
    private func semanticRerank(
        query: String,
        results: [MeetingSearchResult],
        embeddingProvider: (any LLMEmbeddingProvider)?
    ) async -> [MeetingSearchResult] {
        // embeddingProvider가 없으면 LocalHash 사용
        let provider: any LLMEmbeddingProvider = embeddingProvider ?? LocalHashEmbeddingProvider()

        let candidates = Array(results.prefix(semanticRerankCandidateCount))
        guard !candidates.isEmpty else { return results }

        do {
            // 쿼리 벡터 1개
            let queryResponse = try await provider.generateEmbedding(
                LLMEmbeddingRequest(input: query, sourceID: nil)
            )
            // 후보 청크 벡터
            var records: [MeetingSearchEmbeddingRecord] = []
            records.reserveCapacity(candidates.count)
            for result in candidates {
                let response = try await provider.generateEmbedding(
                    LLMEmbeddingRequest(input: result.chunk.text, sourceID: result.chunk.id)
                )
                records.append(MeetingSearchEmbeddingRecord(
                    chunkID: result.chunk.id,
                    meetingID: result.chunk.meetingID,
                    providerID: response.providerID,
                    modelID: response.modelID,
                    embeddingKind: response.kind,
                    vector: response.vector
                ))
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
            let rest = results.dropFirst(semanticRerankCandidateCount)
            return rerankedCandidates + rest
        } catch {
            // 임베딩 실패 시 원 results 반환 — 답변 생성 진행
            return results
        }
    }
}
