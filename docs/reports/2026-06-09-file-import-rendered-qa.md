# 2026-06-09 File Import Rendered QA

## Scope

- Target branch: `feature/file-import-rendered-qa`
- Baseline: `release/llm-search-export-2026-06-09-rc1` at `9658b38`
- Goal: verify the rendered app file import path shows correction and final-summary progress states, not only the unit-level `MeetingFileImportUseCase` stage contract.

## Setup

- Built app with `swift build --disable-sandbox --scratch-path /tmp/minto2-file-import-rendered-qa-build`.
- Generated a short QA audio file at `/tmp/minto2-file-import-rendered-qa/minto-import-qa.wav` using `say -v Yuna` and `afconvert`.
- Ran the app with isolated state under `HOME=/tmp/minto2-file-import-rendered-qa/home3` and `CFFIXED_USER_HOME=/tmp/minto2-file-import-rendered-qa/home3`.
- Selected `sf_speech_on_device` for this rendered QA run to avoid the isolated-HOME WhisperKit cache download path.
- Configured local LLM through UserDefaults/environment:
  - `llmProvider=local`
  - `llmSummaryEnabled=true`
  - `llmSummaryProvider=local`
  - `localLLMBaseURL=http://127.0.0.1:18181`
  - `localLLMModelID=minto-rendered-qa`
  - `localLLMContextWindow=4096`

## Result

- Opened the rendered app file-import flow through the `파일 가져오기` button and selected `/tmp/minto2-file-import-rendered-qa/minto-import-qa.wav`.
- Accessibility polling captured the rendered status card sequence:
  - `17:23:25`: `전사 다듬는 중`, file `minto-import-qa.wav`, detail `전사 다듬는 중 1/1`
  - `17:23:28`: `회의록 정리 중`, file `minto-import-qa.wav`, detail `회의 내용을 정리하고 있습니다.`
  - `17:23:34`: `회의록 생성 완료`, detail `파일 import rendered QA 회의록을 만들었습니다.`
- The rendered library showed `저장된 회의 1개`, title `파일 import rendered QA`, and the summary lead answer from the mock local LLM.
- Mock local LLM log recorded two `/api/generate` requests:
  - correction prompt with `options.num_ctx=4096` and `options.num_predict=900`
  - final-summary prompt with `options.num_ctx=4096` and `options.num_predict=3000`
- The app wrote a meeting JSON under `/tmp/minto2-file-import-rendered-qa/home3/Library/Application Support/Minto/meetings/`.

## Validation

- `swift build --disable-sandbox --scratch-path /tmp/minto2-file-import-rendered-qa-build`: passed.
- `swift test --disable-sandbox --scratch-path /tmp/minto2-file-import-rendered-qa-build --filter MeetingFileImportUseCaseTests`: passed, 10 tests.
- Runtime cleanup: direct app process and mock LLM servers were stopped after QA.

## Notes

- First isolated-HOME WhisperKit attempt failed during model cache download/move, before import reached correction. That failure was not used as success evidence.
- A screen-region capture attempt caught another app because the Minto AX window was reported outside the current capture coordinate space. The success evidence is the rendered accessibility tree plus the created meeting JSON and mock LLM request log.
