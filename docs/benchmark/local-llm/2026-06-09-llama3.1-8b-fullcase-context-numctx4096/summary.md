# Local LLM benchmark summary

- Started: `2026-06-09T16:58:13`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `3/3` passed
- Mean latency: `6.753` seconds
- Mean term recall: `0.694`
- JSON valid rate: `1.0`
- Max server RSS: `114.42` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 10.991 | 0.75 | None | 114.42 |  |
| summary_json | 0 | passed | 7.839 | 1.0 | True | 83.75 |  |
| grounded_answer | 0 | passed | 1.429 | 0.3333333333333333 | None | 72.62 |  |
