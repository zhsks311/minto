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
    public let maxChunks: Int
    public let maxContextCharacters: Int

    public init(maxChunks: Int = 8, maxContextCharacters: Int = 5_000) {
        self.maxChunks = max(1, maxChunks)
        self.maxContextCharacters = max(500, maxContextCharacters)
    }

    public func retrieve(query: String, index: MeetingSearchIndex) -> [MeetingSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return index.search(trimmed, limit: maxChunks * 3)
    }

    public func answer(
        query: String,
        index: MeetingSearchIndex,
        provider: any LLMTextGenerationProvider
    ) async throws -> MeetingSearchAnswer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingSearchAnswerError.emptyQuery }
        return try await answer(query: trimmed, results: retrieve(query: trimmed, index: index), provider: provider)
    }

    public func answer(
        query: String,
        results: [MeetingSearchResult],
        provider: any LLMTextGenerationProvider
    ) async throws -> MeetingSearchAnswer {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MeetingSearchAnswerError.emptyQuery }
        let context = contextBlock(from: results)
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

    private func contextBlock(from results: [MeetingSearchResult]) -> (text: String, citations: [MeetingSearchAnswerCitation]) {
        var blocks: [String] = []
        var citations: [MeetingSearchAnswerCitation] = []
        var usedCharacters = 0

        for result in results.prefix(maxChunks) {
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
}
