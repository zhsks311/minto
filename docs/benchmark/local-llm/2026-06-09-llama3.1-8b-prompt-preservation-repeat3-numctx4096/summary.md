# Local LLM benchmark summary

- Started: `2026-06-09T18:14:23`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `9/9` passed
- Mean latency: `6.039` seconds
- Mean term recall: `0.778`
- JSON valid rate: `1.0`
- Max server RSS: `114.36` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 16.799 | 1.0 | None | 114.36 |  |
| correction_terms_with_context | 1 | passed | 3.414 | 1.0 | None | 80.05 |  |
| correction_terms_with_context | 2 | passed | 4.634 | 1.0 | None | 79.28 |  |
| summary_json | 0 | passed | 9.797 | 1.0 | True | 78.75 |  |
| summary_json | 1 | passed | 8.52 | 1.0 | True | 73.27 |  |
| summary_json | 2 | passed | 7.635 | 1.0 | True | 68.0 |  |
| grounded_answer | 0 | passed | 1.555 | 0.3333333333333333 | None | 71.47 |  |
| grounded_answer | 1 | passed | 1.004 | 0.3333333333333333 | None | 71.7 |  |
| grounded_answer | 2 | passed | 0.995 | 0.3333333333333333 | None | 73.42 |  |
