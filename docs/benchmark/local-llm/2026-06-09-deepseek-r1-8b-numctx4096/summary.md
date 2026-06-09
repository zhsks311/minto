# Local LLM benchmark summary

- Started: `2026-06-09T12:05:31`
- Model: `deepseek-r1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `3/3` passed
- Mean latency: `29.916` seconds
- Mean term recall: `0.667`
- JSON valid rate: `1.0`
- Max server RSS: `82.97` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms | 0 | passed | 19.6 | 0.0 | None | 46.08 |  |
| summary_json | 0 | passed | 50.723 | 1.0 | True | 80.7 |  |
| grounded_answer | 0 | passed | 19.426 | 1.0 | None | 82.97 |  |
