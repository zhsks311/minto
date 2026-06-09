# Local LLM benchmark results

이 디렉터리는 Minto 로컬 LLM 후보의 실제 실행 결과를 보관한다.

## 후보 현황

| 날짜 | Runtime | Model | 결과 | 위치 |
|---|---|---|---|---|
| 2026-06-09 | Ollama | `deepseek-r1:8b` | 첫 correction case 120초 timeout, 기본 후보 보류 | `2026-06-09-deepseek-r1-8b/` |

## 판정 기준

- mock/dry-run은 runner 검증으로만 사용한다.
- 기본값 후보는 실제 endpoint로 correction, summary, grounded answer case를 통과해야 한다.
- latency, term recall, summary JSON validity, source-time preservation을 함께 본다.
- timeout이 난 모델은 기본값 후보로 올리지 않는다.
