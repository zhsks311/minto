# Local LLM benchmark summary

- Started: `2026-06-09T19:23:38`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `9/9` passed
- Mean latency: `15.905` seconds
- Mean term recall: `0.963`
- JSON valid rate: `1.0`
- Max server RSS: `79.47` MB

## Default Candidate Gate

- Real run: `True`
- Coverage OK: `True`
- Transport passed: `True`
- Correction min recall: `1.0`
- Correction clean rate: `0.0`
- Summary min recall: `1.0`
- Summary JSON valid rate: `1.0`
- Answer min recall: `0.667`
- Default candidate ready: `False`

## Case Type Summary

| Case Type | Runs | Success | Mean Latency | Mean Term Recall | Min Term Recall | JSON Valid | Correction Clean |
|---|---:|---:|---:|---:|---:|---:|---:|
| answer | 3 | 1.0 | 10.087 | 0.889 | 0.667 | None | None |
| correction | 3 | 1.0 | 14.617 | 1.0 | 1.0 | None | 0.0 |
| summary | 3 | 1.0 | 23.012 | 1.0 | 1.0 | 1.0 | None |

## Case Runs

| Case | Repeat | Status | Latency | Term Recall | Missing Terms | Correction Clean | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---|---|---:|---|
| correction_terms_with_context | 0 | passed | 20.843 | 1.0 |  | False (multiline_output, marker:출력:, marker:교정합니다, marker:→) | None | 77.02 |  |
| correction_terms_with_context | 1 | passed | 11.589 | 1.0 |  | False (multiline_output, marker:출력:, marker:교정합니다, marker:→) | None | 77.92 |  |
| correction_terms_with_context | 2 | passed | 11.418 | 1.0 |  | False (multiline_output, marker:출력:, marker:교정합니다, marker:→) | None | 77.86 |  |
| summary_json | 0 | passed | 22.61 | 1.0 |  |  | True | 79.47 |  |
| summary_json | 1 | passed | 21.576 | 1.0 |  |  | True | 79.22 |  |
| summary_json | 2 | passed | 24.85 | 1.0 |  |  | True | 68.09 |  |
| grounded_answer | 0 | passed | 13.658 | 1.0 |  |  | None | 72.34 |  |
| grounded_answer | 1 | passed | 6.52 | 0.6666666666666666 | parent page |  | None | 78.08 |  |
| grounded_answer | 2 | passed | 10.083 | 1.0 |  |  | None | 73.42 |  |
