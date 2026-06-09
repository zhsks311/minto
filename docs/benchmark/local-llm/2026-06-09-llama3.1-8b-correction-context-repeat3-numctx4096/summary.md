# Local LLM benchmark summary

- Started: `2026-06-09T14:49:05`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `3/3` passed
- Mean latency: `5.617` seconds
- Mean term recall: `0.75`
- JSON valid rate: `None`
- Max server RSS: `114.75` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 12.779 | 0.75 | None | 114.75 |  |
| correction_terms_with_context | 1 | passed | 2.029 | 0.75 | None | 77.36 |  |
| correction_terms_with_context | 2 | passed | 2.042 | 0.75 | None | 78.78 |  |
