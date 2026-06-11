import Foundation

public final class LegacyAccountLLMTextProvider: LLMTextGenerationProvider, @unchecked Sendable {
    public let descriptor: LLMProviderDescriptor

    public init?(providerID: LLMProviderID, registry: LLMProviderRegistry = .shared) {
        guard let descriptor = registry.descriptor(for: providerID),
              descriptor.authKind == .accountLogin,
              [.chatGPTAccount, .geminiAccount, .copilot].contains(providerID)
        else {
            return nil
        }
        self.descriptor = descriptor
    }

    public func isConfigured() async -> Bool {
        switch descriptor.id {
        case .chatGPTAccount:
            let service = await CodexOAuthService.shared
            return await service.isLoggedIn
        case .geminiAccount:
            let service = await GeminiOAuthService.shared
            return await service.isLoggedIn
        case .copilot:
            let service = await CopilotOAuthService.shared
            return await service.isLoggedIn
        case .local, .gpt, .gemini, .claude, .openRouter:
            return false
        }
    }

    public func modelCatalog() async -> LLMModelCatalog {
        LLMModelCatalog(
            models: await bundledModels(),
            source: .bundledFallback,
            manualModelHelpURL: nil,
            warning: descriptor.requiresWarning ? "계정 로그인 방식은 공식 API 키 방식이 아닙니다." : nil
        )
    }

    public func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        let rawText: String
        switch descriptor.id {
        case .chatGPTAccount:
            let service = await CodexOAuthService.shared
            rawText = try await mapErrors {
                try await service.correct(
                    instructions: request.instructions,
                    userContent: request.userContent,
                    maxOutputTokens: request.maxOutputTokens
                )
            }
        case .geminiAccount:
            let service = await GeminiOAuthService.shared
            rawText = try await mapErrors {
                try await service.correct(
                    instructions: request.instructions,
                    userContent: request.userContent,
                    maxOutputTokens: request.maxOutputTokens
                )
            }
        case .copilot:
            let service = await CopilotOAuthService.shared
            rawText = try await mapErrors {
                try await service.correct(
                    instructions: request.instructions,
                    userContent: request.userContent,
                    maxOutputTokens: request.maxOutputTokens
                )
            }
        case .local, .gpt, .gemini, .claude, .openRouter:
            throw LLMProviderError.notConfigured
        }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMProviderError.badResponse("빈 응답") }
        return LLMTextResponse(
            text: text,
            providerID: descriptor.id,
            modelID: await selectedModelID(requestModelID: request.modelID),
            finishReason: .stop
        )
    }

    private func bundledModels() async -> [LLMModelInfo] {
        let capabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .correction, .summary, .answer]
        switch descriptor.id {
        case .chatGPTAccount:
            return await CodexOAuthService.availableModels.map {
                LLMModelInfo(
                    id: $0.id,
                    displayName: $0.label,
                    capabilities: capabilities,
                    isRecommended: $0.id == "auto"
                )
            }
        case .geminiAccount:
            return await GeminiOAuthService.availableModels.map {
                LLMModelInfo(
                    id: $0.id,
                    displayName: $0.label,
                    capabilities: capabilities,
                    isRecommended: $0.id == GeminiOAuthService.defaultModelID
                )
            }
        case .copilot:
            return await CopilotOAuthService.availableModels.map {
                LLMModelInfo(
                    id: $0.id,
                    displayName: $0.label,
                    capabilities: capabilities,
                    isRecommended: $0.id == CopilotOAuthService.defaultModelID
                )
            }
        case .local, .gpt, .gemini, .claude, .openRouter:
            return []
        }
    }

    private func selectedModelID(requestModelID: String?) async -> String {
        if let requestModelID, !requestModelID.isEmpty {
            return requestModelID
        }
        switch descriptor.id {
        case .chatGPTAccount:
            let service = await CodexOAuthService.shared
            if let credentials = await service.credentials {
                let plan = await service.chatGPTPlanType(from: credentials.accessToken)
                return await service.correctionModel(for: plan)
            }
            return await service.correctionModel(for: nil)
        case .geminiAccount:
            return await GeminiOAuthService.selectedModel
        case .copilot:
            return await CopilotOAuthService.selectedModel
        case .local, .gpt, .gemini, .claude, .openRouter:
            return ""
        }
    }

    private func mapErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as LLMProviderError {
            throw error
        } catch let error as CodexError {
            throw map(codexError: error)
        } catch let error as GeminiOAuthError {
            throw map(geminiError: error)
        } catch let error as CopilotError {
            throw map(copilotError: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LLMProviderError.network(error.localizedDescription)
        }
    }

    private func map(codexError: CodexError) -> LLMProviderError {
        switch codexError {
        case .notLoggedIn:
            return .unauthorized
        case .notEntitled:
            return .modelUnavailable(codexError.localizedDescription)
        case .rateLimited:
            return .rateLimited
        case .timeout:
            return .network(codexError.localizedDescription)
        case .badResponse:
            return .badResponse(codexError.localizedDescription)
        }
    }

    private func map(geminiError: GeminiOAuthError) -> LLMProviderError {
        switch geminiError {
        case .notLoggedIn:
            return .unauthorized
        case .badURL, .socketError, .noCallback, .noCode, .stateMismatch:
            return .network(geminiError.localizedDescription)
        case .badResponse:
            return .badResponse(geminiError.localizedDescription)
        }
    }

    private func map(copilotError: CopilotError) -> LLMProviderError {
        switch copilotError {
        case .notLoggedIn:
            return .unauthorized
        case .noSubscription:
            return .unauthorized
        case .tokenExpired:
            return .network(copilotError.localizedDescription)
        case .badResponse:
            return .badResponse(copilotError.localizedDescription)
        }
    }
}
