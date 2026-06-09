# 계정 provider 모델 카탈로그 갱신

## 배경

API key provider의 fallback 모델 목록을 갱신한 뒤, GPT 계정 로그인, Gemini 계정 로그인, GitHub Copilot 계정도 설정 화면에서 오래된 모델을 보여주는 문제가 남았다.

## 변경

- GPT 계정 로그인
  - `auto`는 유지했다.
  - 유료 tier 기본 모델을 `gpt-5.5`로 갱신했다.
  - 선택지에 `gpt-5.3-codex`, `gpt-5.4`, `gpt-5.4-mini`를 추가했다.
  - 최신 모델이 계정 endpoint에서 거부되면 `gpt-5.4` → `gpt-5.4-mini` 순서로 폴백한다.
- Gemini 계정 로그인
  - 기본 모델을 `gemini-3.5-flash`로 갱신했다.
  - 선택지에 `gemini-3.1-pro-preview`, `gemini-2.5-flash`, `gemini-2.5-pro`를 포함했다.
  - 계정 권한이나 Code Assist 노출 차이로 실패하면 기존 안정 모델 `gemini-2.5-flash`로 폴백한다.
- GitHub Copilot 계정
  - 기본 모델을 `gpt-5-mini`로 갱신했다.
  - GPT, Claude, Gemini, MAI, Raptor 계열의 현재 Copilot 모델 id를 선택지에 추가했다.
- 계정 provider의 모델 picker 안내 문구를 계정/조직 정책에 따라 모델이 막힐 수 있다는 방향으로 보강했다.
- 기존 저장값이 현재 목록에 없으면 설정 진입 시 새 기본 모델로 정규화한다.

## 확인한 출처

- OpenAI model docs: `https://platform.openai.com/docs/models`
- GitHub Copilot supported models: `https://docs.github.com/copilot/reference/ai-models/supported-models`
- GitHub Copilot model comparison: `https://docs.github.com/copilot/reference/ai-models/model-comparison`
- Gemini Code Assist docs: `https://developers.google.com/gemini-code-assist/docs`

## 검증

- 완료: `git diff --check`
- 완료: `swift build --disable-sandbox`
- 완료: `swift test --disable-sandbox --filter 'LLMProviderTests|CodexTierTests'`
  - 39 tests passed
- 완료: `./scripts/dev.sh build`
  - build, certificate signing, code signature verification 통과
- 제한: 앱 실행 화면 확인
  - `.build/debug/minto2` 직접 실행 후 PID와 `[STT] Apple speech engine ready: sf_speech_on_device` 로그 확인
  - Computer Use가 SwiftPM executable을 독립 app으로 인식하지 못해 설정 화면 스크린샷 확인은 보류
