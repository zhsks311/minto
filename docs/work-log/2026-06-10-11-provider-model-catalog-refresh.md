# Provider 모델 카탈로그 갱신

## 배경

Claude API 설정에서 `목록에 없는 모델 ID 직접 입력` 예시가 오래된 dated 모델을 보여 사용자가 현재 provider가 제공하는 값을 확인하기 어려웠다.

## 변경

- API key provider의 bundled fallback 모델 목록을 현재 공식 provider 모델 ID 기준으로 갱신했다.
  - GPT API: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`
  - Gemini API: `gemini-3.5-flash`, `gemini-3.1-pro-preview`, `gemini-3.1-flash-lite`
  - Claude API: `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`, `claude-opus-4-8`, `claude-fable-5`
  - OpenRouter API: `openai/gpt-5.5`, `anthropic/claude-sonnet-4.6`, `google/gemini-3.5-flash`, `openai/gpt-5.4-mini`
- 설정 화면의 직접 입력 예시를 같은 모델 ID로 맞췄다.
- bundled fallback 모델 ID가 다시 낡아지는 것을 막기 위해 단위 테스트를 추가했다.

## 확인한 공식 출처

- OpenAI model docs: `https://platform.openai.com/docs/models`
- Gemini model docs: `https://ai.google.dev/gemini-api/docs/models`
- Anthropic model overview: `https://docs.anthropic.com/en/docs/about-claude/models/overview`
- OpenRouter model API: `https://openrouter.ai/api/v1/models`

## 검증

- 완료: `git diff --check`
- 완료: `swift build --disable-sandbox`
- 제한: `swift build --disable-sandbox --scratch-path /tmp/minto2-provider-model-catalog-build`
  - `/tmp` checkout 중 `No space left on device`
- 제한: `swift test --disable-sandbox --filter LLMProviderTests`
  - 테스트 컴파일 후 dSYM/link 단계에서 `No space left on device`
- 제한: 앱 실행 화면 확인
  - `./scripts/dev.sh run`은 빌드 후 codesign 단계에서 `internal error in Code Signing subsystem`로 실패했다.
  - `.build/debug/minto2` 직접 실행은 PID 확인까지 완료했으나, 접근성 도구에서 SwiftPM executable을 app으로 지정할 수 없어 화면 스크린샷 확인은 보류했다.
