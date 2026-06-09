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

## Release Candidate

- RC branch: `release/llm-search-export-2026-06-09-rc1`
- RC worktree: `/Users/d66hjkxwt9/Idea/private/minto2-release-rc1`
- RC base commit: `07da899 merge related info reconnect status lane`
- Original lane baseline remains fixed at `release/llm-search-export-2026-06-09` / `4bcff6d`.
- RC validation:
  - `git diff --check`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-release-rc1-smoke-test --filter 'AudioInputMode|LLMProviderTests|MeetingSearchAnswerService|RelatedInfoTests|IntegrationReconnectStateTests|SecretStore'`: passed, 102 tests

## Post-Integration Follow-up

- Local LLM settings connection:
  - `.local` provider selection is now available in correction, summary, and search answer provider pickers.
  - Local runtime settings are stored in UserDefaults and still fall back to `MINTO_LOCAL_LLM_*` environment variables.
  - Settings UI exposes endpoint URL, model ID, Ollama/OpenAI-compatible mode, and timeout without API key/login controls.
  - Endpoint URL validation requires `http` or `https` with a host.
- Mixed audio input connection:
  - `마이크+시스템` is selectable in the meeting setup sheet.
  - `MixedAudioSource` starts microphone and system audio sources together and emits mixed PCM buffers.
  - The mixer combines aligned buffered samples at 0.5 gain with clipping; echo cancellation and long-run drift correction remain measurement items.
  - Single-source backlog is capped with passthrough fallback to avoid unbounded live input latency and memory growth.
  - Mixed readiness uses the same screen/system audio permission and availability gate as system audio.
  - Rendered setup UI QA confirms `시스템` and `마이크+시스템` selection both show ready states and enable `녹음 시작` when screen/system audio permission is already available.
  - `SystemAudioLiveTests` provides an opt-in live QA gate that plays a generated WAV through `/usr/bin/afplay` and verifies `SystemAudioSource` receives buffer and level callbacks from a separate process.
  - ViewModel coverage now confirms `.mixed` input selection replaces the source before recording and sends source buffers into the VAD pipeline.
- Local LLM benchmark runner:
  - `scripts/run_local_llm_benchmarks.py` measures correction, summary JSON, and grounded answer cases.
  - The runner supports Ollama and OpenAI-compatible endpoints, dry-run, mock validation, repeat runs, and optional server RSS sampling.
  - Ollama runs now control `options.num_ctx` with `--num-ctx` or `MINTO_LOCAL_LLM_CONTEXT_WINDOW`, and record the applied value in manifest, metrics, and summary output.
  - Settings-backed local model values are covered through correction, summary, and search answer provider selection readiness.
  - Benchmark instructions are documented under `docs/benchmark/local-llm-benchmark-runner.md`.
  - Real Ollama run for `deepseek-r1:8b` is recorded under `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b`; first correction case timed out after 120s and a direct 16-token request timed out after 60s, so this model is not promoted as a default candidate.
  - The `deepseek-r1:8b` failure happened with Ollama model context `131072`; rerun evidence should use a controlled context such as `--num-ctx 4096`.
  - Controlled `deepseek-r1:8b` rerun with `--num-ctx 4096` is recorded under `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-numctx4096`; timeout was resolved, but correction term recall was `0.0`, so default-candidate status remains on hold.
  - Controlled `qwen2.5:3b` run with `--num-ctx 4096` is recorded under `docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-numctx4096`; it completed 3/3 cases with mean latency `6.957s`, but correction term recall was `0.0`, so default-candidate status remains on hold.
  - Controlled `llama3.1:8b` run with `--num-ctx 4096` is recorded under `docs/benchmark/local-llm/2026-06-09-llama3.1-8b-numctx4096`; it completed 3/3 cases with mean latency `6.894s`, but correction term recall was `0.0`, so default-candidate status remains on hold.
  - The runner now includes `correction_terms_with_context`, which mirrors Minto's meeting topic/glossary correction prompt more closely than the minimal correction case.
  - Context correction reruns are recorded under `docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-correction-context-numctx4096` and `docs/benchmark/local-llm/2026-06-09-llama3.1-8b-correction-context-numctx4096`; qwen remained at term recall `0.0`, while llama improved to `0.75` but missed `Liquibase`, so default-candidate status remains on hold.
  - `llama3.1:8b` context correction repeat-3 is recorded under `docs/benchmark/local-llm/2026-06-09-llama3.1-8b-correction-context-repeat3-numctx4096`; recall was stable at `0.75` for all 3 repeats, but still missed `Liquibase` every time, so it is the current best local candidate but not a default.
  - Provider smoke coverage confirms local LLM Ollama payloads for correction, final summary, and search answer use cases.
  - Search answer flow coverage now confirms `MeetingSearchAnswerUseCase` calls `LocalLLMProvider` with an Ollama `answer` payload, preserves citations, and uses `num_predict=1800` with the configured context window.
  - Rendered app UI QA now confirms the meeting search "AI 답변" button calls the Local LLM Ollama `/api/generate` flow and renders the returned answer with citations.
  - File import pipeline QA now confirms correction and final summary run as pipeline stages rather than standalone buttons: `전사 다듬는 중`/`.correcting` is observed before the corrected transcript is passed to `회의록 정리 중`/`.summarizing`.
- SecretStore dev mode:
  - Default secret storage remains Keychain.
  - `MINTO_DEV_SECRET_STORE=file` selects the opt-in local dev file store for LLM API keys, OAuth tokens, and Confluence API tokens.
  - `MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto-dev-secrets` can isolate dev secret files during app QA.
  - Dev secret files are written under the app support dev-secrets directory with restricted directory/file permissions.
  - Process-env smoke coverage confirms the default LLM API key, OAuth token, and Confluence token backends follow `MINTO_DEV_SECRET_STORE=file` without injected test stores.
  - Settings copy now says secret store instead of hardcoding Keychain-only storage.
- Related info reconnect status:
  - Related document search now prioritizes reconnect guidance over a generic empty-results message when Notion or Confluence enters `needsReconnect`.
  - Confluence search 401 and existing Notion reconnect state are covered through `RelatedInfoService` status-message tests.
  - Confluence export 401 is covered at both space lookup and page create steps, and leaves the service in `needsReconnect`.
  - Notion and Confluence status checks now cover the Settings prompt-count contract by proving status rendering paths do not load token payloads.
- Settings UI QA:
  - `MINTO_DEV_SECRET_STORE=file MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto2-dev-secrets-ui-qa-rc1 ./scripts/dev.sh run` launched the RC integration app through build, signing, and app initialization.
  - Settings UI `GPT API` saved the test value `minto-ui-qa-not-a-secret` into `/tmp/minto2-dev-secrets-ui-qa-rc1/com.minto.app.llm-api__llm-api-key-gpt.json` with `-rw-------` permissions and showed `API 키 저장됨`.
  - Relaunching with the same `MINTO_DEV_SECRET_STORE_ROOT` loaded the saved Settings state and still showed `API 키 저장됨`.
  - Settings UI `로컬 LLM` showed `모델 ID 필요` when the model field was empty, then showed `로컬 런타임 설정됨` after entering `qwen2.5:3b`, with `API 키는 필요하지 않습니다` copy visible.
- Validation:
  - `git diff --check`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-test --filter LLMProviderTests`: passed, 27 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-test --filter 'LLMProviderTests|MeetingSearchAnswerService|SummaryServiceTests'`: passed, 51 tests
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-build`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-routing-test --filter LLMProviderTests`: passed, 29 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-service-smoke-test --filter LLMProviderTests`: passed, 30 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter AudioInputMode`: passed, 13 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter 'AudioInputMode|TranscriptionViewModelStopTests'`: passed, 21 tests
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-build`: passed
  - `python3 -m py_compile scripts/run_local_llm_benchmarks.py`: passed
  - `python3 scripts/run_local_llm_benchmarks.py --dry-run --model mock-model --cases correction --output-root /tmp/minto2-local-llm-bench-dryrun`: passed
  - `python3 scripts/run_local_llm_benchmarks.py --mock --model mock-model --repeat 1 --output-root /tmp/minto2-local-llm-bench-mock`: passed, 3 mock cases
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-test --filter SecretStore`: passed, 6 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-related-test --filter 'SecretStore|LLMProviderTests|RelatedInfoTests'`: passed, 71 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-related-info-reconnect-status-test --filter 'RelatedInfoTests|IntegrationReconnectStateTests'`: passed, 40 tests
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-build`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-process-env-test-2 --filter SecretStore`: passed, 7 tests
  - `MINTO_DEV_SECRET_STORE=file MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto2-dev-secrets-process-env-qa swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-process-env-env-test --filter SecretStore`: passed, 7 tests
  - `MINTO_DEV_SECRET_STORE=file MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto2-dev-secrets-ui-qa ./scripts/dev.sh run`: build/sign/run reached app initialization
  - Settings UI save/load/delete was not verified in that run: `computer-use` did not target the direct SwiftPM `minto2` process, and shell accessibility inspection failed with System Events error `-1728`.
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-context-test --filter LLMProviderTests`: passed, 28 tests
  - `python3 -m py_compile scripts/run_local_llm_benchmarks.py`: passed
  - `python3 scripts/run_local_llm_benchmarks.py --dry-run --model deepseek-r1:8b --cases correction --num-ctx 4096 --output-root /tmp/minto2-local-llm-context-dryrun`: passed, request body preview has `options.num_ctx=4096`
  - `python3 scripts/run_local_llm_benchmarks.py --mock --model mock-model --repeat 1 --num-ctx 4096 --output-root /tmp/minto2-local-llm-context-mock`: passed, 3 mock cases
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-local-llm-context-build`: passed
  - `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model deepseek-r1:8b --num-ctx 4096 --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-numctx4096 --fail-fast`: passed transport/format gates, 3 cases completed, correction term recall `0.0`
  - `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model qwen2.5:3b --num-ctx 4096 --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-numctx4096 --fail-fast`: passed transport/format gates, 3 cases completed, mean latency `6.957s`, correction term recall `0.0`
  - `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model llama3.1:8b --num-ctx 4096 --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-llama3.1-8b-numctx4096 --fail-fast`: passed transport/format gates, 3 cases completed, mean latency `6.894s`, correction term recall `0.0`
  - `python3 scripts/run_local_llm_benchmarks.py --dry-run --model qwen2.5:3b --cases correction_terms_with_context --num-ctx 4096 --output-root /tmp/minto2-local-llm-context-case-dryrun`: passed, request body has Minto correction policy, meeting context, glossary, current transcript, and `options.num_ctx=4096`
  - `python3 scripts/run_local_llm_benchmarks.py --mock --model mock-model --cases correction_terms_with_context --num-ctx 4096 --output-root /tmp/minto2-local-llm-context-case-mock`: passed, correction term recall `1.0`
  - `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model qwen2.5:3b --cases correction_terms_with_context --num-ctx 4096 --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-correction-context-numctx4096 --fail-fast`: passed transport/format gates, mean latency `5.223s`, correction term recall `0.0`
  - `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model llama3.1:8b --cases correction_terms_with_context --num-ctx 4096 --repeat 1 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-llama3.1-8b-correction-context-numctx4096 --fail-fast`: passed transport/format gates, mean latency `22.979s`, correction term recall `0.75`
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-answer-e2e-test --filter MeetingSearchAnswerServiceTests`: passed, 13 tests
  - `CFFIXED_USER_HOME=/tmp/minto2-local-llm-ui-home-1780982611 HOME=/tmp/minto2-local-llm-ui-home-1780982611 ... .build/debug/minto2`: rendered app UI loaded an isolated meeting store with `저장된 회의 1개`, searched `liquibase`, pressed the "AI 답변" card button, and displayed `UI-E2E-LOCAL-LLM-ANSWER: 로컬 검색 답변 성공 [1]`.
  - `/tmp/minto2-local-llm-ui-e2e-requests-1780982633.jsonl`: last mock Ollama request used `/api/generate`, model `minto-ui-e2e`, `stream=false`, `options.num_predict=1800`, `options.num_ctx=4096`, citation instructions, `질문: liquibase`, and meeting evidence containing `db 스키마 형상 관리` plus `change-log-master.xml`.
  - `/tmp/minto2-local-llm-ui-answer-window.png`: window-id capture shows the rendered search answer card, citation list `[1]...[4]`, and the isolated one-meeting search result.
  - Test cleanup: app and mock server processes were stopped; real `com.minto.app` defaults were restored to no `meetingSearchAnswer*` keys, no local endpoint override keys, and `localLLMModelID=qwen2.5:3b`.
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-correction-summary-pipeline-test --filter MeetingFileImportUseCaseTests`: passed, 10 tests
  - `python3 scripts/run_local_llm_benchmarks.py --compatibility ollama --base-url http://127.0.0.1:11434 --model llama3.1:8b --cases correction_terms_with_context --num-ctx 4096 --repeat 3 --server-pid 58693 --output-root docs/benchmark/local-llm/2026-06-09-llama3.1-8b-correction-context-repeat3-numctx4096 --fail-fast`: passed, 3/3 runs, mean latency `5.617s`, correction term recall `0.75`, missing term `Liquibase`
  - `CFFIXED_USER_HOME=/tmp/minto2-system-audio-ui-home-1780984552 HOME=/tmp/minto2-system-audio-ui-home-1780984552 .build/debug/minto2`: rendered setup UI opened from `새 회의`, selected `시스템` and observed `시스템 입력 가능` with `녹음 시작` enabled.
  - Same setup UI run selected `마이크+시스템` and observed `마이크+시스템 입력 가능`, explanatory copy `Echo cancellation은 적용하지 않습니다.`, and `녹음 시작` enabled.
  - `/tmp/minto2-system-audio-setup-mixed-ready.png`: window capture shows the rendered `마이크+시스템` ready state.
  - Test cleanup: the direct SwiftPM app process was stopped. Permission-denied state was not exercised because this macOS environment already had screen/system audio permission available.
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-system-audio-live-default-test --filter 'SystemAudioLiveTests|AudioInputMode'`: passed, 14 tests. The live capture test is skipped by default unless `RUN_SYSTEM_AUDIO_LIVE_TEST=1` is set.
  - `RUN_SYSTEM_AUDIO_LIVE_TEST=1 swift test --disable-sandbox --scratch-path /tmp/minto2-system-audio-live-default-test --filter SystemAudioLiveTests`: passed, 1 test. The opt-in run verified system audio buffer and level callbacks from external `afplay` output.
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-viewmodel-pipeline-test --filter AudioInputMode`: passed, 14 tests. This includes `.mixed` selection and source-buffer-to-VAD handoff coverage.
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-confluence-export-reconnect-test --filter 'ConfluenceExportReconnectTests|IntegrationReconnectStateTests'`: passed, 8 tests.
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-settings-token-status-no-load-test --filter IntegrationReconnectStateTests`: passed, 8 tests.

## Remaining Manual QA

- System audio:
  - 권한 없음 상태에서 readiness warning, start disabled, 시스템 설정 열기 동작 확인. Current QA environment already had screen/system audio permission, so this state remains manual.
  - 권한 거부 상태에서 권한 허용 후 앱 복귀 시 readiness 갱신과 level meter 동작 확인
  - 실제 화상회의 앱 출력으로 source-specific system audio capture 확인. Generic external-process system output is covered by `SystemAudioLiveTests`.
  - 실제 마이크와 화상회의 앱 출력을 동시에 넣은 `마이크+시스템` VAD/STT 결과 확인. ViewModel-level mixed source buffer to VAD handoff is covered by `AudioInputModeTests`.
  - echo 상황과 장시간 녹음 drift 측정
- Local LLM:
  - 실제 앱 화면에서 파일 가져오기 또는 녹음 종료 경로의 correction/summary 진행 상태 rendered QA. There are no standalone correction/summary buttons in the current UI; the automated file import pipeline test covers the stage order and corrected-transcript handoff.
  - correction term recall이 높은 추가 실제 후보 모델 benchmark를 `docs/benchmark/local-llm/`에 기록하고 기본값 후보를 결정
- Keychain reconnect UX:
  - invalid Confluence token으로 Confluence 내보내기 실패 후 실제 export sheet/Settings handoff 렌더 확인. 서비스의 `needsReconnect` 상태 전환은 export 401 자동 테스트로 검증됨.
  - invalid Notion token으로 관련 문서 검색 실패 후 실제 OAuth 실패, 재연결, 지우기 버튼 동작 확인. `needsReconnect` 상태의 검색 안내는 자동 검증됨.
  - 실제 Settings 화면 반복 진입 시 macOS Keychain prompt 카운트 확인. Settings 상태 조회 경로가 token 원문을 읽지 않는 계약은 자동 검증됨.
  - 개발 실행 file secret store에서 Settings UI delete 확인. App launch, save, and relaunch-load are verified with `/tmp/minto2-dev-secrets-ui-qa-rc1`; delete remains manual because it requires a GUI deletion action.

## Stop Conditions

- Stop integration if any lane edits an explicitly excluded file set.
- Stop integration if any lane branch has uncommitted changes after its final report.
- Stop integration if build/test failure reproduces twice with the same code failure.
- Do not move the release branch after lane work starts.
