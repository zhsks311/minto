import Testing
@testable import MintoCore
import Foundation

/// Codex 교정 모델의 무료/유료(tier) 분기 단위 테스트.
/// 무료 계정 경로는 무료 토큰이 없어 실측이 불가하므로 결정론적 단위로 검증한다.
@MainActor
@Suite("Codex tier-aware 모델 선택")
struct CodexTierTests {

    /// {"https://api.openai.com/auth":{"chatgpt_plan_type": plan}} 페이로드를 가진 가짜 JWT 생성.
    private func fakeJWT(plan: String?) -> String {
        var auth: [String: Any] = ["chatgpt_account_id": "acc_test"]
        if let plan { auth["chatgpt_plan_type"] = plan }
        let payload: [String: Any] = ["https://api.openai.com/auth": auth]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let b64url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64url).sig"
    }

    @Test("plan_type 추출: pro / free / 클레임 없음")
    func extractsPlanType() {
        let svc = CodexOAuthService.shared
        #expect(svc.chatGPTPlanType(from: fakeJWT(plan: "pro")) == "pro")
        #expect(svc.chatGPTPlanType(from: fakeJWT(plan: "free")) == "free")
        #expect(svc.chatGPTPlanType(from: fakeJWT(plan: nil)) == nil)
        #expect(svc.chatGPTPlanType(from: "not.a.jwt") == nil)
    }

    @Test("무료·미상 tier는 기본(mini) 모델")
    func freeAndUnknownUseDefault() {
        let svc = CodexOAuthService.shared
        #expect(svc.correctionModel(for: "free") == "gpt-5.4-mini")
        #expect(svc.correctionModel(for: "FREE") == "gpt-5.4-mini")   // 대소문자 무시
        #expect(svc.correctionModel(for: nil) == "gpt-5.4-mini")
        #expect(svc.correctionModel(for: "") == "gpt-5.4-mini")
    }

    @Test("유료 tier(pro/plus/team/enterprise)는 상위 모델")
    func paidTiersUseUpgradedModel() {
        let svc = CodexOAuthService.shared
        for plan in ["pro", "plus", "team", "enterprise"] {
            #expect(svc.correctionModel(for: plan) == "gpt-5.4", "\(plan)은 상위 모델이어야 함")
        }
    }
}
