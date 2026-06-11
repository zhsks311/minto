import Testing
@testable import MintoCore
import Foundation

/// Codex 교정 요청 body 구성·에러 분류 단위 테스트.
/// 백엔드 응답 본문은 2026-06-12 실측 원문(chatgpt.com/backend-api/codex/responses) 그대로다.
@Suite("Codex 교정 요청 body·에러 분류")
struct CodexCorrectionRequestTests {

    @Test("요청 body에 max_output_tokens를 절대 넣지 않는다 (백엔드 미지원)")
    func bodyNeverContainsMaxOutputTokens() {
        let body = CodexOAuthService.correctionRequestBody(
            model: "gpt-5.5",
            instructions: "교정 지침",
            userContent: "교정할 본문"
        )

        #expect(body["max_output_tokens"] == nil)
        #expect(body["model"] as? String == "gpt-5.5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["store"] as? Bool == false)
        #expect(body["instructions"] as? String == "교정 지침")
        let input = body["input"] as? [[String: Any]]
        #expect(input?.count == 1)
        #expect(input?.first?["role"] as? String == "user")
        #expect(input?.first?["content"] as? String == "교정할 본문")
    }

    @Test("400 + 모델 미지원 본문 → notEntitled (하위 모델 폴백 대상)")
    func model400IsFallbackable() {
        let body = #"{"detail":"The 'gpt-4o' model is not supported when using Codex with a ChatGPT account."}"#
        let error = CodexOAuthService.classifyCorrectionError(status: 400, body: body)
        #expect(error == .notEntitled)
        #expect(error.isModelFallbackable)
    }

    @Test("400 + 파라미터 미지원 본문 → badRequest (폴백 무의미, 즉시 실패)")
    func parameter400IsNotFallbackable() {
        let body = #"{"detail":"Unsupported parameter: max_output_tokens"}"#
        let error = CodexOAuthService.classifyCorrectionError(status: 400, body: body)
        #expect(error == .badRequest)
        #expect(!error.isModelFallbackable)
    }

    @Test("status code별 분류: 429/401/403/404/5xx")
    func classifiesByStatusCode() {
        #expect(CodexOAuthService.classifyCorrectionError(status: 429, body: "") == .rateLimited)
        #expect(CodexOAuthService.classifyCorrectionError(status: 401, body: "") == .notEntitled)
        #expect(CodexOAuthService.classifyCorrectionError(status: 403, body: "") == .notEntitled)
        #expect(CodexOAuthService.classifyCorrectionError(status: 404, body: "") == .notEntitled)
        #expect(CodexOAuthService.classifyCorrectionError(status: 500, body: "") == .badResponse)
    }
}
