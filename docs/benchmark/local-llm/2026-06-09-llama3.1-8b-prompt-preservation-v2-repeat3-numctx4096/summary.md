# Local LLM benchmark summary

- Started: `2026-06-09T18:19:47`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `9/9` passed
- Mean latency: `4.83` seconds
- Mean term recall: `0.889`
- JSON valid rate: `1.0`
- Max server RSS: `78.89` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 5.626 | 1.0 | None | 78.0 |  |
| correction_terms_with_context | 1 | passed | 3.987 | 1.0 | None | 78.5 |  |
| correction_terms_with_context | 2 | passed | 2.904 | 1.0 | None | 77.86 |  |
| summary_json | 0 | passed | 8.304 | 1.0 | True | 78.89 |  |
| summary_json | 1 | passed | 7.606 | 1.0 | True | 69.2 |  |
| summary_json | 2 | passed | 7.724 | 1.0 | True | 67.55 |  |
| grounded_answer | 0 | passed | 2.909 | 0.6666666666666666 | None | 72.75 |  |
| grounded_answer | 1 | passed | 2.111 | 0.6666666666666666 | None | 74.25 |  |
| grounded_answer | 2 | passed | 2.297 | 0.6666666666666666 | None | 74.66 |  |
