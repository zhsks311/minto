import Testing
@testable import MintoCore

@Suite("LLMProvider 공통 타입")
struct LLMProviderTests {

    @Test("공급자 표시 이름은 사용자 용어를 사용한다")
    func providerDisplayNames() {
        #expect(LLMProviderID.local.displayName == "로컬 LLM")
        #expect(LLMProviderID.gpt.displayName == "GPT")
        #expect(LLMProviderID.claude.displayName == "Claude")
        #expect(LLMProviderID.openRouter.displayName == "OpenRouter")
        #expect(LLMProviderID.chatGPTAccount.displayName == "GPT 계정 로그인")
    }

    @Test("로컬 공급자와 클라우드 공급자를 구분한다")
    func providerCloudClassification() {
        #expect(LLMProviderID.local.isCloudProvider == false)
        #expect(LLMProviderID.gpt.isCloudProvider == true)
        #expect(LLMProviderID.gemini.isCloudProvider == true)
        #expect(LLMProviderID.openRouter.isCloudProvider == true)
    }

    @Test("공급자 오류는 사용자에게 보여줄 메시지를 가진다")
    func providerErrorMessages() {
        #expect(LLMProviderError.notConfigured.userMessage == "공급자 설정이 필요합니다.")
        #expect(LLMProviderError.modelUnavailable("gpt-x").userMessage.contains("gpt-x"))
        #expect(LLMProviderError.rateLimited.userMessage.contains("요청 한도"))
    }
}
