# Account provider model refresh plan

## 목표

- GPT 계정 로그인, Gemini 계정 로그인, GitHub Copilot 계정의 설정 모델 목록을 현재 provider가 노출하는 모델명에 맞춘다.
- 공식 API key provider와 달리 계정 로그인 provider는 내부/앱 endpoint이므로 새 모델 권한이 없을 때 기존 안정 모델로 폴백한다.

## 범위

1. `CodexOAuthService` 모델 목록과 유료 tier 기본 모델 갱신
2. `GeminiOAuthService` 모델 목록과 기본 모델 갱신, 기존 안정 모델 fallback 유지
3. `CopilotOAuthService` 모델 목록과 기본 모델 갱신
4. `LegacyAccountLLMTextProvider`, `SettingsView`, 관련 테스트 갱신
5. 작업 로그 추가

## 검증

- 완료: `git diff --check`
- 완료: `swift build --disable-sandbox`
- 완료: `swift test --disable-sandbox --filter 'LLMProviderTests|CodexTierTests'`
- 완료: `./scripts/dev.sh build`
- 제한: SwiftPM executable은 Computer Use app target으로 잡히지 않아 설정 모델 picker 스크린샷 확인은 보류
