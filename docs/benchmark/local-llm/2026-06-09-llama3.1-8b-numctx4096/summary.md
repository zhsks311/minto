# Local LLM benchmark summary

- Started: `2026-06-09T12:37:32`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `3/3` passed
- Mean latency: `6.894` seconds
- Mean term recall: `0.444`
- JSON valid rate: `1.0`
- Max server RSS: `121.31` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms | 0 | passed | 10.733 | 0.0 | None | 121.31 |  |
| summary_json | 0 | passed | 8.311 | 1.0 | True | 76.97 |  |
| grounded_answer | 0 | passed | 1.638 | 0.3333333333333333 | None | 74.08 |  |
