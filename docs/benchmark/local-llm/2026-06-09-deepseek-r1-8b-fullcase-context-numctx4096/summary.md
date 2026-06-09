# Local LLM benchmark summary

- Started: `2026-06-09T16:17:23`
- Model: `deepseek-r1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `3/3` passed
- Mean latency: `36.874` seconds
- Mean term recall: `0.778`
- JSON valid rate: `1.0`
- Max server RSS: `89.66` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 34.276 | 1.0 | None | 45.27 |  |
| summary_json | 0 | passed | 56.138 | 1.0 | True | 78.41 |  |
| grounded_answer | 0 | passed | 20.209 | 0.3333333333333333 | None | 89.66 |  |
