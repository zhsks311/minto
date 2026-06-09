# Local LLM benchmark summary

- Started: `2026-06-09T18:22:06`
- Model: `llama3.1:8b`
- Compatibility: `ollama`
- Base URL: `http://127.0.0.1:11434`
- Context window: `4096`
- Runs: `9/9` passed
- Mean latency: `4.974` seconds
- Mean term recall: `0.963`
- JSON valid rate: `1.0`
- Max server RSS: `80.42` MB

| Case | Repeat | Status | Latency | Term Recall | JSON | RSS MB | Error |
|---|---:|---|---:|---:|---|---:|---|
| correction_terms_with_context | 0 | passed | 6.959 | 1.0 | None | 76.33 |  |
| correction_terms_with_context | 1 | passed | 3.897 | 1.0 | None | 77.44 |  |
| correction_terms_with_context | 2 | passed | 4.019 | 1.0 | None | 78.59 |  |
| summary_json | 0 | passed | 7.817 | 1.0 | True | 80.42 |  |
| summary_json | 1 | passed | 6.796 | 1.0 | True | 70.47 |  |
| summary_json | 2 | passed | 6.827 | 1.0 | True | 71.98 |  |
| grounded_answer | 0 | passed | 2.787 | 0.6666666666666666 | None | 77.42 |  |
| grounded_answer | 1 | passed | 2.899 | 1.0 | None | 78.0 |  |
| grounded_answer | 2 | passed | 2.763 | 1.0 | None | 76.39 |  |
