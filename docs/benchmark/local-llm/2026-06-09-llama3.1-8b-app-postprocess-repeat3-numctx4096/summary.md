# Local LLM benchmark summary

- Started: `2026-06-09T20:03:11`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `9/9` passed
- Mean latency: `28.813` seconds
- Mean term recall: `1.0`
- JSON valid rate: `1.0`
- Max server RSS: `83.62` MB

## Default Candidate Gate

- Real run: `True`
- Coverage OK: `True`
- Transport passed: `True`
- Correction min recall: `1.0`
- Correction clean rate: `0.0`
- Correction length OK rate: `0.0`
- Summary min recall: `1.0`
- Summary JSON valid rate: `1.0`
- Answer min recall: `1.0`
- Default candidate ready: `False`

## App Candidate Gate

- Real run: `True`
- Coverage OK: `True`
- Transport passed: `True`
- App correction min recall: `1.0`
- App correction clean rate: `1.0`
- App correction length OK rate: `1.0`
- Summary min recall: `1.0`
- Summary JSON valid rate: `1.0`
- Answer min recall: `1.0`
- App default candidate ready: `True`

## Case Type Summary

| Case Type | Runs | Success | Mean Latency | Mean Term Recall | Min Term Recall | JSON Valid | Correction Clean | Length OK | App Mean Recall | App Min Recall | App Correction Clean | App Length OK |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| answer | 3 | 1.0 | 33.908 | 1.0 | 1.0 | None | None | None | None | None | None | None |
| correction | 3 | 1.0 | 17.18 | 1.0 | 1.0 | None | 0.0 | 0.0 | 1.0 | 1.0 | 1.0 | 1.0 |
| summary | 3 | 1.0 | 35.352 | 1.0 | 1.0 | 1.0 | None | None | None | None | None | None |

## Case Runs

| Case | Repeat | Status | Latency | Term Recall | Missing Terms | Correction Clean | Length Ratio | Length OK | App Term Recall | App Missing Terms | App Correction Clean | App Length Ratio | App Length OK | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---|---:|---|---:|---|---|---:|---|---|---:|---|
| correction_terms_with_context | 0 | passed | 23.177 | 1.0 |  | False (multiline_output, marker:출력:, marker:교정합니다, marker:→) | 2.986 | False | 1.0 |  | True | 1.507 | True | None | 80.75 |  |
| correction_terms_with_context | 1 | passed | 14.535 | 1.0 |  | False (multiline_output, marker:출력:, marker:교정합니다, marker:→) | 2.986 | False | 1.0 |  | True | 1.507 | True | None | 81.03 |  |
| correction_terms_with_context | 2 | passed | 13.827 | 1.0 |  | False (multiline_output, marker:출력:, marker:교정합니다, marker:→) | 2.986 | False | 1.0 |  | True | 1.507 | True | None | 81.11 |  |
| summary_json | 0 | passed | 24.832 | 1.0 |  |  | None | None | None |  |  | None | None | True | 82.14 |  |
| summary_json | 1 | passed | 32.17 | 1.0 |  |  | None | None | None |  |  | None | None | True | 83.62 |  |
| summary_json | 2 | passed | 49.055 | 1.0 |  |  | None | None | None |  |  | None | None | True | 83.28 |  |
| grounded_answer | 0 | passed | 35.215 | 1.0 |  |  | None | None | None |  |  | None | None | None | 76.23 |  |
| grounded_answer | 1 | passed | 32.781 | 1.0 |  |  | None | None | None |  |  | None | None | None | 77.11 |  |
| grounded_answer | 2 | passed | 33.727 | 1.0 |  |  | None | None | None |  |  | None | None | None | 73.56 |  |
