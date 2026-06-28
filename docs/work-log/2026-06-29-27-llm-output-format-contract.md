# LLM 출력 형식 계약 도입

작성일: 2026-06-29
근거 계획: `.omx/plans/prd-llm-output-contract-strategy-20260628T124046Z.md`

## 배경

최종 회의 요약은 JSON으로 파싱하지만, 기존 provider adapter는 `useCase == .finalSummary`를 보고
각자 요약 schema를 붙였다. 이 방식은 provider가 앱 수준의 요약 의미를 알아야 하고,
새 provider를 추가할 때 같은 schema 분기와 복사본이 늘어나는 문제가 있었다.

## 변경

- `LLMTextRequest.outputFormat`을 추가하고 기본값을 `.plainText`로 유지했다.
- `LLMOutputFormat.jsonSchema`와 `LLMJSONSchema`/`LLMJSONValue`로 transport에 넘길 schema 계약을 명시했다.
- `MeetingSummarySchema`를 모델 옆 단일 소스로 분리했다.
- `SummaryService.generateFinal`만 `MeetingSummarySchema.schema`를 요청하고, 증분 요약·문서 요약·교정·답변은 plain text 기본값을 유지한다.
- Ollama, OpenAI Responses, Gemini, OpenRouter의 구조화 출력 요청은 `outputFormat`을 기준으로 매핑한다.
- Claude API, Claude Code CLI, legacy 계정 provider, local OpenAI-compatible endpoint는 검증되지 않은 schema 강제를 하지 않고 `.unsupportedOutputFormat`으로 명시 실패한다.
- unsupported provider에서도 최종 요약은 기존 running summary 폴백으로 fail-soft 동작을 유지한다.
- OpenAI/OpenRouter strict schema 호환을 위해 모든 object schema에 `additionalProperties: false`를 붙였다.
- OpenRouter structured output 요청에는 `provider.require_parameters = true`를 같이 보내 route가 schema 지원을 우회하지 않게 했다.

## 검증

- `git diff --check` 통과.
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-output-contract-test --filter 'LLMProviderTests|SummaryServiceTests|ClaudeCodeCLIProviderTests'` 통과: 78 tests.
- `./scripts/dev.sh build` 통과: Swift build + 개발 서명 검증.

## 결정 메모

- provider adapter는 앱의 `finalSummary` 의미가 아니라 `outputFormat` transport 계약만 해석한다.
- `unsupportedOutputFormat`은 retry 대상이 아니다. 사용자에게 구조화 요약을 지원하는 provider/model 선택을 안내한다.
- Claude Code CLI의 `--output-format json`은 CLI wrapper JSON이지 schema-enforced 본문 JSON이 아니므로 구조화 요약 지원으로 취급하지 않는다.
- Architect 리뷰에서 provider별 structured-output 지원 판정을 capability 메타데이터로 승격하라는 WATCH가 남았다. 이번 변경은 PRD의 작은 계약 도입 범위에 맞춰 adapter-local 판정으로 닫고, provider가 더 늘어나면 별도 설계로 분리한다.
