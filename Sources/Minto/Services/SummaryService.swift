import Foundation
import SwiftUI

/// 회의 요약 생성 서비스.
///
/// `LLMCorrectionService`와 동일한 provider 분기(Codex/Gemini/Copilot)를 재사용한다.
/// 사용자가 교정용으로 고른 provider(`selectedProvider`)를 그대로 쓰며, Codex는 tier-aware
/// 모델 상향도 그대로 적용된다.
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
            newBatch: batch
        )
        guard let summary = await dispatch(prompt) else { return nil }
        meeting.runningSummary = summary
        return summary
    }

    /// 종료 시 최종 요약. 성공 시 `MeetingContext.finalSummary`를 갱신하고 반환한다.
    /// LLM 최종 호출이 실패하면 마지막 runningSummary를 최종으로 사용한다(있으면).
    public func generateFinal(tailText: String) async -> String? {
        let meeting = MeetingContext.shared
        let prompt = SummaryPrompt.buildFinal(
            topic: meeting.topic,
            glossary: meeting.glossary,
            runningSummary: meeting.runningSummary,
            tailText: tailText
        )
        if let summary = await dispatch(prompt) {
            meeting.finalSummary = summary
            return summary
        }
        // 최종 LLM 실패 → 마지막 증분 요약으로 폴백(빈 요약이면 nil).
        let fallback = meeting.runningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return nil }
        meeting.finalSummary = fallback
        return fallback
    }

    /// provider 분기 — `LLMCorrectionService.selectedProvider`를 재사용. 실패·none·빈 응답이면 nil.
    private func dispatch(_ prompt: (instructions: String, userContent: String)) async -> String? {
        let provider = LLMCorrectionService.shared.selectedProvider
        guard provider != .none else { return nil }

        activeGenerations += 1
        defer { activeGenerations -= 1 }

        do {
            let result: String
            switch provider {
            case .none:
                return nil
            case .gemini:
                result = try await GeminiOAuthService.shared.correct(instructions: prompt.instructions, userContent: prompt.userContent)
            case .copilot:
                result = try await CopilotOAuthService.shared.correct(instructions: prompt.instructions, userContent: prompt.userContent)
            case .codex:
                result = try await CodexOAuthService.shared.correct(instructions: prompt.instructions, userContent: prompt.userContent)
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            fputs("[Summary] generation failed via \(provider.rawValue): \(error)\n", stderr)
            return nil
        }
    }
}
