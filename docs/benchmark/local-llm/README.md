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
| 2026-06-09 | Ollama | `deepseek-r1:8b` (`context correction`, `summary`, `answer`, `num_ctx=4096`) | 3/3 응답, summary JSON valid, mean latency 36.874s, grounded answer recall 0.333, 기본 후보 보류 | `2026-06-09-deepseek-r1-8b-fullcase-context-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`context correction`, `summary`, `answer`, `num_ctx=4096`) | 3/3 응답, summary JSON valid, mean latency 6.753s, correction recall 0.75, grounded answer recall 0.333, 기본 후보 보류 | `2026-06-09-llama3.1-8b-fullcase-context-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`context correction`, `summary`, `answer`, `num_ctx=4096`, repeat 3) | 9/9 응답, summary JSON valid, mean latency 4.288s, correction recall 0.75 고정, grounded answer recall 0.333~0.667, 기본 후보 보류 | `2026-06-09-llama3.1-8b-fullcase-context-repeat3-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`prompt preservation v1`, `num_ctx=4096`, repeat 3) | correction recall 1.0으로 개선, grounded answer recall 0.333 고정, 기본 후보 보류 | `2026-06-09-llama3.1-8b-prompt-preservation-repeat3-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`prompt preservation v2`, `num_ctx=4096`, repeat 3) | correction/summary recall 1.0, grounded answer recall 0.667 고정, 기본 후보 보류 | `2026-06-09-llama3.1-8b-prompt-preservation-v2-repeat3-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`prompt preservation v3`, `num_ctx=4096`, repeat 3) | 9/9 응답, mean latency 4.974s, correction/summary recall 1.0, grounded answer 2/3만 recall 1.0, 기본 후보 보류 | `2026-06-09-llama3.1-8b-prompt-preservation-v3-repeat3-numctx4096/` |
| 2026-06-09 | Ollama | `llama3.1:8b` (`gate breakdown`, `num_ctx=4096`, repeat 3) | 9/9 응답, mean latency 15.905s, correction clean rate 0.0, answer min recall 0.667, default candidate gate false | `2026-06-09-llama3.1-8b-gate-breakdown-repeat3-numctx4096/` |

## 판정 기준

- mock/dry-run은 runner 검증으로만 사용한다.
- 기본값 후보는 실제 endpoint로 correction, summary, grounded answer case를 통과해야 한다.
- latency, term recall, summary JSON validity, source-time preservation을 함께 본다.
- Ollama 후보는 context window를 통제하고 `run_manifest.json`에 기록한 실제 run만 후보 판단에 사용한다.
- case별 JSON/JSONL은 capped `output_preview`, `output_sha256`, `found_terms`, `missing_terms`를 남겨 누락 원인을 재실행 없이 추적한다.
- Markdown/CSV summary는 누락 term을 바로 확인할 수 있어야 하며, 출력 preview는 built-in synthetic benchmark 응답 확인 용도로만 사용한다.
- `summary.json`/`summary.md`는 correction, summary, answer gate를 분리해 어느 use case가 기본값 승격을 막는지 보여야 한다.
- correction term recall이 `1.0`이어도 설명 문구, `출력:` 접두어, 줄바꿈 같은 non-correction output이 섞이면 기본값 gate를 통과하지 않는다.
- 교정 후보는 minimal prompt와 Minto형 meeting topic/glossary prompt를 구분해 본다.
- timeout이 난 모델은 기본값 후보로 올리지 않는다.
