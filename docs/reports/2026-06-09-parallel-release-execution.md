# 2026-06-09 Parallel Release Execution

## Release Baseline

- Release branch: `release/llm-search-export-2026-06-09`
- Baseline commit: `4bcff6d feat: add system audio input foundation`
- Source branch: `feature/llm-correction-search-export`
- Excluded from baseline: untracked local report `docs/reports/2026-06-09-task-summary-current-implementation-status.html`

## Lane Split

### Lane 1: System Audio Readiness

- Branch: `feature/system-audio-readiness`
- Worktree: `/Users/d66hjkxwt9/Idea/private/minto2-system-audio-readiness`
- Result commit: `c295d17 feat: show system audio readiness before recording`
- Scope:
  - 녹음 전 system audio availability/readiness 표시
  - 권한 필요 상태와 설정 안내
  - audio input mode 관련 테스트
- Do not touch:
  - LLM provider
  - Keychain/Confluence
  - `SettingsView`
  - `MeetingLibraryView`

### Lane 2: Local Text LLM Adapter

- Branch: `feature/local-llm-adapter`
- Worktree: `/Users/d66hjkxwt9/Idea/private/minto2-local-llm-adapter`
- Result commit: `7972535 feat: add local HTTP LLM provider`
- Scope:
  - 외부 로컬 런타임용 text generation adapter
  - provider registry capability 전환
  - provider 테스트
- Do not touch:
  - Settings UI
  - Meeting library UI
  - audio input
  - Keychain/Confluence

### Lane 3: Keychain Reconnect UX

- Branch: `feature/keychain-reconnect-ux`
- Worktree: `/Users/d66hjkxwt9/Idea/private/minto2-keychain-reconnect-ux`
- Result commit: `6a96d21 fix: mark integrations needing reconnect`
- Scope:
  - stored credential existence와 actual credential validity 분리
  - invalid/corrupt token 사용 실패 후 다시 연결 필요 상태 표시
  - 관련 Keychain/Confluence/Notion/Settings 상태 테스트
- Do not touch:
  - LLM provider
  - audio input
  - Meeting search/export UI

## Merge Order

1. `feature/system-audio-readiness`
   - UI 충돌 범위가 `MeetingSetupView` 중심이라 먼저 통합한다.
2. `feature/keychain-reconnect-ux`
   - `SettingsView`를 만질 수 있으므로 audio lane 다음에 통합한다.
3. `feature/local-llm-adapter`
   - UI를 건드리지 않는 provider lane으로 제한했기 때문에 마지막 통합 시 conflict risk가 낮다.
4. Integration validation
   - `git diff --check`
   - `swift build --disable-sandbox --scratch-path /tmp/minto2-integration-build`
   - `swift test --disable-sandbox --scratch-path /tmp/minto2-integration-test`

## Baseline Validation

- `git diff --check`: passed
- `swift build --disable-sandbox --scratch-path /tmp/minto2-release-baseline-build`: passed
- `swift test --disable-sandbox --scratch-path /tmp/minto2-release-baseline-test --filter 'LLMProviderTests|MeetingSearchAnswerService|AudioInputMode|RelatedInfoTests|MeetingFileImportUseCaseTests'`: passed, 81 tests

## Integration Result

- Integration branch: `integration/llm-search-export-2026-06-09`
- Merge commits:
  - `5e01941 merge system audio readiness lane`
  - `6e101c6 merge local llm adapter lane`
  - `ad87b7f merge keychain reconnect ux lane`
- Pre-keychain smoke:
  - `git diff --check`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-integration-smoke-test --filter 'AudioInputMode|LLMProviderTests|MeetingSearchAnswerService'`: passed, 48 tests
- Final integration validation:
  - `git diff --check`: passed
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-integration-build`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-integration-smoke-test --filter 'AudioInputMode|LLMProviderTests|MeetingSearchAnswerService|RelatedInfoTests'`: passed, 86 tests

## Remaining Manual QA

- System audio:
  - 권한 없음 상태에서 readiness warning, start disabled, 시스템 설정 열기 동작 확인
  - 권한 허용 후 앱 복귀 시 readiness 갱신과 level meter 동작 확인
  - 실제 화상회의 앱 출력으로 system audio capture 확인
- Local LLM:
  - Ollama 또는 OpenAI-compatible local endpoint로 correction, summary, answer 호출 확인
  - 한국어 회의 교정 품질, 요약 구조화 성공률, 검색 답변 근거 충실도, latency, RAM benchmark 기록
- Keychain reconnect UX:
  - invalid Confluence token으로 검색/내보내기 실패 후 `다시 연결 필요` 표시 확인
  - invalid Notion token으로 관련 문서 검색 실패 후 재연결/지우기 동작 확인
  - Settings 진입만으로 반복 Keychain 원문 읽기 prompt가 늘지 않는지 확인

## Stop Conditions

- Stop integration if any lane edits an explicitly excluded file set.
- Stop integration if any lane branch has uncommitted changes after its final report.
- Stop integration if build/test failure reproduces twice with the same code failure.
- Do not move the release branch after lane work starts.
