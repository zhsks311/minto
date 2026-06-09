# Local LLM benchmark results

이 디렉터리는 Minto 로컬 LLM 후보의 실제 실행 결과를 보관한다.

## 후보 현황

| 날짜 | Runtime | Model | 결과 | 위치 |
|---|---|---|---|---|
| 2026-06-09 | Ollama | `deepseek-r1:8b` | 첫 correction case 120초 timeout, 기본 후보 보류 | `2026-06-09-deepseek-r1-8b/` |
| 2026-06-09 | Ollama | `deepseek-r1:8b` (`num_ctx=4096`) | 3/3 응답, correction term recall 0.0, 기본 후보 보류 | `2026-06-09-deepseek-r1-8b-numctx4096/` |
| 2026-06-09 | Ollama | `qwen2.5:3b` (`num_ctx=4096`) | 3/3 응답, 평균 6.957s, correction term recall 0.0, 기본 후보 보류 | `2026-06-09-qwen2.5-3b-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`num_ctx=4096`) | 3/3 응답, 평균 6.894s, correction term recall 0.0, 기본 후보 보류 | `2026-06-09-llama3.1-8b-numctx4096/` |
| 2026-06-09 | Ollama | `qwen2.5:3b` (`correction_terms_with_context`, `num_ctx=4096`) | Minto형 용어집 prompt에서도 correction term recall 0.0, 기본 후보 보류 | `2026-06-09-qwen2.5-3b-correction-context-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`correction_terms_with_context`, `num_ctx=4096`) | correction term recall 0.75, `Liquibase` 누락, latency 22.979s, 기본 후보 보류 | `2026-06-09-llama3.1-8b-correction-context-numctx4096/` |
| 2026-06-09 | Ollama | `deepseek-r1:8b` (`correction_terms_with_context`, `num_ctx=4096`) | correction term recall 1.0, latency 43.994s, 전체 케이스 추가 검증 전 기본 후보 보류 | `2026-06-09-deepseek-r1-8b-correction-context-numctx4096/` |

## 판정 기준

- mock/dry-run은 runner 검증으로만 사용한다.
- 기본값 후보는 실제 endpoint로 correction, summary, grounded answer case를 통과해야 한다.
- latency, term recall, summary JSON validity, source-time preservation을 함께 본다.
- Ollama 후보는 context window를 통제하고 `run_manifest.json`에 기록한 실제 run만 후보 판단에 사용한다.
- 교정 후보는 minimal prompt와 Minto형 meeting topic/glossary prompt를 구분해 본다.
- timeout이 난 모델은 기본값 후보로 올리지 않는다.
