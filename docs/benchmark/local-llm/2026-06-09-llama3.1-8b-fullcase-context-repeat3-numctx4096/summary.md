# Local LLM benchmark summary

- Started: `2026-06-09T17:03:29`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `9/9` passed
- Mean latency: `4.288` seconds
- Mean term recall: `0.769`
- JSON valid rate: `1.0`
- Max server RSS: `79.81` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 6.627 | 0.75 | None | 76.0 |  |
| correction_terms_with_context | 1 | passed | 2.071 | 0.75 | None | 76.56 |  |
| correction_terms_with_context | 2 | passed | 2.08 | 0.75 | None | 77.92 |  |
| summary_json | 0 | passed | 7.852 | 1.0 | True | 78.83 |  |
| summary_json | 1 | passed | 7.22 | 1.0 | True | 78.72 |  |
| summary_json | 2 | passed | 7.385 | 1.0 | True | 79.81 |  |
| grounded_answer | 0 | passed | 2.384 | 0.6666666666666666 | None | 70.89 |  |
| grounded_answer | 1 | passed | 1.038 | 0.3333333333333333 | None | 71.58 |  |
| grounded_answer | 2 | passed | 1.931 | 0.6666666666666666 | None | 72.84 |  |
