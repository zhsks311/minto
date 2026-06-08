import Foundation
import SwiftUI

@MainActor
public final class LLMCorrectionService: ObservableObject {

    public enum Provider: String, CaseIterable {
        case none    = "none"
        case gemini  = "gemini"
        case copilot = "copilot"
        case codex   = "codex"

        public var providerID: LLMProviderID? {
            LLMProviderRegistry.shared.providerID(forLegacyCorrectionProviderRawValue: rawValue)
        }

        public var label: String {
            if self == .none { return "사용 안 함" }
            guard let providerID else { return rawValue }
            let descriptor = LLMProviderRegistry.shared.descriptor(for: providerID)
            return descriptor?.displayName ?? providerID.displayName
        }

        public init?(providerID: LLMProviderID) {
            guard let rawValue = LLMProviderRegistry.shared.legacyCorrectionProviderRawValue(for: providerID) else {
                return nil
            }
            self.init(rawValue: rawValue)
        }

        // ToS 회색 지대 경고 필요 여부
        public var requiresWarning: Bool {
            guard let providerID else { return false }
            return LLMProviderRegistry.shared.descriptor(for: providerID)?.requiresWarning ?? false
        }
    }

    public static let shared = LLMCorrectionService()
    private init() {}

    @AppStorage("llmProvider") public var selectedProvider: Provider = .none

    // 교정 진행 중 카운터 (ViewModel에서 UI 인디케이터에 사용)
    @Published public var activeCorrections: Int = 0

    // MARK: - Correct

    /// 비동기 교정 수행. 실패 시 nil 반환 (원본 유지).
    public func correct(text: String, context: String) async -> String? {
        guard selectedProvider != .none, !text.isEmpty else { return nil }

        activeCorrections += 1
        defer { activeCorrections -= 1 }

        // 회의 맥락 + 직전 발화 + 현재 인식을 한 곳에서 프롬프트로 조립 (provider 공통)
        let meeting = MeetingContext.shared
        let (instructions, userContent) = CorrectionPrompt.build(
            topic: meeting.topic,
            glossary: meeting.glossary,
            context: context,
            text: text,
            summary: meeting.runningSummary,
            document: meeting.document
        )

        fputs("[LLM] correcting via \(selectedProvider.rawValue): \"\(text)\"\n", stderr)
        do {
            let corrected: String
            switch selectedProvider {
            case .none:
                return nil
            case .gemini:
                corrected = try await GeminiOAuthService.shared.correct(instructions: instructions, userContent: userContent)
            case .copilot:
                corrected = try await CopilotOAuthService.shared.correct(instructions: instructions, userContent: userContent)
            case .codex:
                corrected = try await CodexOAuthService.shared.correct(instructions: instructions, userContent: userContent)
            }
            fputs("[LLM] corrected → \"\(corrected)\"\n", stderr)
            return corrected
        } catch {
            fputs("[LLM] correction failed: \(error)\n", stderr)
            return nil
        }
    }

    // MARK: - Auth helpers

    public var isLoggedIn: Bool {
        switch selectedProvider {
        case .none:    return false
        case .gemini:  return GeminiOAuthService.shared.isLoggedIn
        case .copilot: return CopilotOAuthService.shared.isLoggedIn
        case .codex:   return CodexOAuthService.shared.isLoggedIn
        }
    }

    public var loginEmail: String {
        switch selectedProvider {
        case .none:    return ""
        case .gemini:  return GeminiOAuthService.shared.email
        case .copilot: return CopilotOAuthService.shared.email
        case .codex:   return ""
        }
    }

    public func logout() {
        switch selectedProvider {
        case .none:    break
        case .gemini:  GeminiOAuthService.shared.logout()
        case .copilot: CopilotOAuthService.shared.logout()
        case .codex:   CodexOAuthService.shared.logout()
        }
    }
}

// AppStorage에서 enum을 쓰기 위한 RawRepresentable 준수 (String으로 저장)
extension LLMCorrectionService.Provider: RawRepresentable {}
