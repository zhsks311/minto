import Foundation
import SwiftUI

public struct SummaryGenerationContext: Sendable, Equatable {
    public let topic: String
    public let glossary: String
    public let runningSummary: String
    public let document: String

    public init(
        topic: String = "",
        glossary: String = "",
        runningSummary: String = "",
        document: String = ""
    ) {
        self.topic = topic
        self.glossary = glossary
        self.runningSummary = runningSummary
        self.document = document
    }
}

/// 회의 요약 생성 서비스.
///
/// 요약 provider는 교정 provider와 별도 설정으로 관리한다.
/// 기존 사용자는 최초 실행 시 교정 provider를 한 번 복사해 요약 동작 회귀를 줄이고,
/// 이후에는 교정 off + 요약 on 조합을 독립적으로 사용할 수 있다.
///
/// 모든 경로 fail-soft: provider 미선택·미로그인·네트워크 오류·빈 응답이면 nil을 반환하고
/// 기존 요약을 유지한다(요약 실패가 전사·교정을 망가뜨리지 않는다).
@MainActor
public final class SummaryService: ObservableObject {

    public static let shared = SummaryService()
    private init() {}

    /// 요약 생성 진행 카운터 (UI 인디케이터용).
    @Published public var activeGenerations: Int = 0

    /// 진행 중 증분 요약. 성공 시 `MeetingContext.runningSummary`를 갱신하고 반환한다.
    /// 실패하면 nil(기존 runningSummary 유지).
    @discardableResult
    public func generateIncremental(correctedBatch: String) async -> String? {
        let batch = correctedBatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batch.isEmpty else { return nil }

        let meeting = MeetingContext.shared
        let prompt = SummaryPrompt.buildIncremental(
            topic: meeting.topic,
            glossary: meeting.glossary,
            runningSummary: meeting.runningSummary,
            newBatch: batch,
            document: meeting.document
        )
        guard let summary = await dispatch(prompt, useCase: .incrementalSummary) else { return nil }
        meeting.runningSummary = summary
        return summary
    }

    /// 종료 시 **구조화 최종 요약**(JSON 파싱 → MeetingSummary). 성공 시 `MeetingContext.finalSummary`를 갱신.
    /// LLM 실패/파싱 실패 시: 평문 폴백(마지막 runningSummary 또는 raw 텍스트). 모두 비면 nil.
    public func generateFinal(transcript: String) async -> MeetingSummary? {
        let meeting = MeetingContext.shared
        let context = SummaryGenerationContext(
            topic: meeting.topic,
            glossary: meeting.glossary,
            runningSummary: meeting.runningSummary,
            document: meeting.document
        )
        let summary = await generateFinal(transcript: transcript, context: context)
        if let summary {
            meeting.finalSummary = summary
        }
        return summary
    }

    /// 명시적 context로 최종 요약을 생성한다.
    ///
    /// 파일 import처럼 live `MeetingContext`를 건드리면 안 되는 사후 처리 경로에서 사용한다.
    public func generateFinal(transcript: String, context: SummaryGenerationContext) async -> MeetingSummary? {
        // 빈 회의(전사 없음)는 요약할 내용이 없으므로 LLM을 호출하지 않는다.
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prompt = SummaryPrompt.buildFinal(
            topic: context.topic,
            glossary: context.glossary,
            transcript: transcript,
            document: context.document
        )

        if let raw = await dispatch(prompt, useCase: .finalSummary) {
            // JSON 파싱 시도 → 실패하면 raw를 평문 요약으로 감싼다(빈 화면 방지).
            let summary = Self.parseStructured(raw) ?? .plain(raw)
            return summary
        }
        // 최종 LLM 호출 실패 → 마지막 증분 요약을 평문 폴백(빈 요약이면 nil).
        let fallback = context.runningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return nil }
        return MeetingSummary.plain(fallback)
    }

    /// LLM 응답에서 JSON 객체를 추출해 MeetingSummary로 디코딩한다.
    /// 코드펜스(```json)·앞뒤 설명이 섞여 와도 첫 '{'~마지막 '}' 구간만 잘라 파싱한다.
    /// 의미 있는 내용이 없으면(isEmpty) nil → 호출부가 평문 폴백.
    static func parseStructured(_ raw: String) -> MeetingSummary? {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
            return nil
        }
        let jsonSlice = raw[start...end]
        guard let data = String(jsonSlice).data(using: .utf8),
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: data),
              !summary.isEmpty
        else { return nil }
        return summary
    }

    /// provider adapter dispatch. 실패·none·빈 응답이면 nil.
    private func dispatch(_ prompt: (instructions: String, userContent: String), useCase: LLMUseCase) async -> String? {
        guard let provider = LLMSummarySettingsService.shared.selectedTextProvider() else { return nil }

        activeGenerations += 1
        defer { activeGenerations -= 1 }

        do {
            let response = try await provider.generateText(LLMTextRequest(
                useCase: useCase,
                instructions: prompt.instructions,
                userContent: prompt.userContent
            ))
            let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            fputs("[Summary] generation failed via \(provider.descriptor.id.rawValue): \(error.localizedDescription)\n", stderr)
            return nil
        }
    }
}
