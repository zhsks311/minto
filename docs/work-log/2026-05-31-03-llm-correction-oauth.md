# 세션 3 — LLM 후처리 교정 + OAuth 3종 연동

_2026-05-31 · 커밋 `60cf80e`_

## 프롬프트 → 작업 내용

### "oauth로 구현 가능해? 아니면 로컬에 있는 large-v3 모델로 처리 가능해?"

Anthropic Claude OAuth, Gemini/GPT OAuth 현황 조사.

- Claude OAuth: 2026년 2월 Anthropic이 third-party 앱 사용 전면 차단
- Gemini OAuth: 동년 2~3월 Google도 동일하게 차단
- 로컬 large-v3(Whisper): 음성→텍스트 모델이므로 텍스트 교정 불가
- 결론: **Gemini 무료 API key** 또는 **Claude Haiku API key**가 현실적

### "hermes model 하면 oauth 하면 동작하는 모델들도 떠" + hermes-agent 로컬 클론 확인

`/Users/d66hjkxwt9/Idea/private/hermes-agent` 실제 코드 분석.

- `agent/google_oauth.py`: Google gemini-cli 공개 OAuth credentials + PKCE → `cloudcode-pa.googleapis.com`
- `hermes_cli/copilot_auth.py`: GitHub Device Code Flow → `api.githubcopilot.com` (합법)
- `hermes_cli/providers.py`: openai-codex provider → `chatgpt.com/backend-api/codex` (ToS 회색)
- Nous Portal: 자체 유료 OAuth 서비스 (합법, OpenRouter 경유)

### "Gemini OAuth, GPT/Codex OAuth, GitHub Copilot OAuth 이거 추가해줘."

3종 OAuth 기반 LLM 후처리 교정 기능 구현.

**UI 설계 (Pencil.dev)**
- 3가지 상태 목업: 미연결 / 로그인됨 / Device Code 진행중
- 오버레이 헤더 비교: 기본 vs "✦ 교정 중" 인디케이터

**신규 파일**

| 파일 | 내용 |
|------|------|
| `KeychainService.swift` | OAuth 토큰 `kSecClassGenericPassword` Keychain 저장 |
| `GeminiOAuthService.swift` | PKCE + `cloudcode-pa.googleapis.com/v1internal:generateContent` |
| `CopilotOAuthService.swift` | GitHub Device Code Flow + `api.githubcopilot.com/chat/completions` |
| `CodexOAuthService.swift` | OpenAI Device Auth + `chatgpt.com/backend-api/codex/v1/responses` |
| `LLMCorrectionService.swift` | Provider 라우팅, `activeCorrections` 카운터 |

**수정 파일**

| 파일 | 변경 내용 |
|------|----------|
| `TranscriptionState.swift` | `updateSegmentText(id:newText:)` 추가 |
| `TranscriptionViewModel.swift` | `advanceWindow` 후 비동기 LLM 교정 Task 삽입 |
| `SettingsView.swift` | LLM 교정 섹션 (provider picker, 로그인/로그아웃, device code 표시) |
| `TranscriptionOverlayView.swift` | `✦ 교정 중` 헤더 인디케이터 |
| `Info.plist` | `minto://` URL scheme 등록 (Gemini OAuth redirect) |

**동작 흐름**

> 발화 → Whisper 전사 (즉시 표시) → 비동기 Task로 `LLMCorrectionService.correct()` → 1~3초 후 segment를 교정본으로 조용히 교체

**Provider별 인증 방식**

| Provider | 방식 | 합법성 |
|----------|------|--------|
| GitHub Copilot | Device Code Flow (공식) | ✅ 합법 |
| Gemini | gemini-cli 공개 creds + PKCE | ⚠️ ToS 회색 지대 |
| OpenAI Codex | OpenAI Device Auth | ⚠️ ToS 회색 지대 |

> ⚠️ 이 시점의 구현은 "추가"만 됐고 실제 로그인/교정 동작은 미검증 상태였음 (세션 4에서 동작화).
