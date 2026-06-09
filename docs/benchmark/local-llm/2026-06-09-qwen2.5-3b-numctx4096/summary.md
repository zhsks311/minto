# Local LLM benchmark summary

- Started: `2026-06-09T12:18:50`
- Model: `qwen2.5:3b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `3/3` passed
- Mean latency: `6.957` seconds
- Mean term recall: `0.556`
- JSON valid rate: `1.0`
- Max server RSS: `126.73` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms | 0 | passed | 14.27 | 0.0 | None | 126.73 |  |
| summary_json | 0 | passed | 3.931 | 1.0 | True | 84.72 |  |
| grounded_answer | 0 | passed | 2.671 | 0.6666666666666666 | None | 73.55 |  |
