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
- Local LLM benchmark runner:
  - `scripts/run_local_llm_benchmarks.py` measures correction, summary JSON, and grounded answer cases.
  - The runner supports Ollama and OpenAI-compatible endpoints, dry-run, mock validation, repeat runs, and optional server RSS sampling.
  - Ollama runs now control `options.num_ctx` with `--num-ctx` or `MINTO_LOCAL_LLM_CONTEXT_WINDOW`, and record the applied value in manifest, metrics, and summary output.
  - Benchmark instructions are documented under `docs/benchmark/local-llm-benchmark-runner.md`.
  - Real Ollama run for `deepseek-r1:8b` is recorded under `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b`; first correction case timed out after 120s and a direct 16-token request timed out after 60s, so this model is not promoted as a default candidate.
  - The `deepseek-r1:8b` failure happened with Ollama model context `131072`; rerun evidence should use a controlled context such as `--num-ctx 4096`.
  - Controlled `deepseek-r1:8b` rerun with `--num-ctx 4096` is recorded under `docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-numctx4096`; timeout was resolved, but correction term recall was `0.0`, so default-candidate status remains on hold.
  - Controlled `qwen2.5:3b` run with `--num-ctx 4096` is recorded under `docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-numctx4096`; it completed 3/3 cases with mean latency `6.957s`, but correction term recall was `0.0`, so default-candidate status remains on hold.
  - Controlled `llama3.1:8b` run with `--num-ctx 4096` is recorded under `docs/benchmark/local-llm/2026-06-09-llama3.1-8b-numctx4096`; it completed 3/3 cases with mean latency `6.894s`, but correction term recall was `0.0`, so default-candidate status remains on hold.
  - The runner now includes `correction_terms_with_context`, which mirrors Minto's meeting topic/glossary correction prompt more closely than the minimal correction case.
  - Context correction reruns are recorded under `docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-correction-context-numctx4096` and `docs/benchmark/local-llm/2026-06-09-llama3.1-8b-correction-context-numctx4096`; qwen remained at term recall `0.0`, while llama improved to `0.75` but missed `Liquibase`, so default-candidate status remains on hold.
- SecretStore dev mode:
  - Default secret storage remains Keychain.
  - `MINTO_DEV_SECRET_STORE=file` selects the opt-in local dev file store for LLM API keys, OAuth tokens, and Confluence API tokens.
  - `MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto-dev-secrets` can isolate dev secret files during app QA.
  - Dev secret files are written under the app support dev-secrets directory with restricted directory/file permissions.
  - Settings copy now says secret store instead of hardcoding Keychain-only storage.
- Validation:
  - `git diff --check`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-test --filter LLMProviderTests`: passed, 27 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-test --filter 'LLMProviderTests|MeetingSearchAnswerService|SummaryServiceTests'`: passed, 51 tests
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-local-llm-settings-build`: passed
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter AudioInputMode`: passed, 13 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-test --filter 'AudioInputMode|TranscriptionViewModelStopTests'`: passed, 21 tests
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-mixed-audio-build`: passed
  - `python3 -m py_compile scripts/run_local_llm_benchmarks.py`: passed
  - `python3 scripts/run_local_llm_benchmarks.py --dry-run --model mock-model --cases correction --output-root /tmp/minto2-local-llm-bench-dryrun`: passed
  - `python3 scripts/run_local_llm_benchmarks.py --mock --model mock-model --repeat 1 --output-root /tmp/minto2-local-llm-bench-mock`: passed, 3 mock cases
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-test --filter SecretStore`: passed, 6 tests
  - `swift test --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-related-test --filter 'SecretStore|LLMProviderTests|RelatedInfoTests'`: passed, 71 tests
  - `swift build --disable-sandbox --scratch-path /tmp/minto2-secret-store-root-build`: passed
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

## Remaining Manual QA

- System audio:
  - 권한 없음 상태에서 readiness warning, start disabled, 시스템 설정 열기 동작 확인
  - 권한 허용 후 앱 복귀 시 readiness 갱신과 level meter 동작 확인
  - 실제 화상회의 앱 출력으로 system audio capture 확인
  - `마이크+시스템` 선택 후 마이크와 시스템 출력이 모두 VAD/STT pipeline으로 들어오는지 확인
  - echo 상황과 장시간 녹음 drift 측정
- Local LLM:
  - Settings에서 local provider 선택, endpoint/model 저장, 상태 문구 확인
  - Ollama 또는 OpenAI-compatible local endpoint로 correction, summary, answer 호출 확인
  - correction term recall이 높은 추가 실제 후보 모델 benchmark를 `docs/benchmark/local-llm/`에 기록하고 기본값 후보를 결정
- Keychain reconnect UX:
  - invalid Confluence token으로 검색/내보내기 실패 후 `다시 연결 필요` 표시 확인
  - invalid Notion token으로 관련 문서 검색 실패 후 재연결/지우기 동작 확인
  - Settings 진입만으로 반복 Keychain 원문 읽기 prompt가 늘지 않는지 확인
  - 개발 실행에서 `MINTO_DEV_SECRET_STORE=file MINTO_DEV_SECRET_STORE_ROOT=/tmp/minto-dev-secrets`로 LLM API key, OAuth token, Confluence token save/load/delete 확인

## Stop Conditions

- Stop integration if any lane edits an explicitly excluded file set.
- Stop integration if any lane branch has uncommitted changes after its final report.
- Stop integration if build/test failure reproduces twice with the same code failure.
- Do not move the release branch after lane work starts.
