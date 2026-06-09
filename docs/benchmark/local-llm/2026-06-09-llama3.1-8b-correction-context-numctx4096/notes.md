# llama3.1:8b Minto correction-context benchmark note

작성일: 2026-06-09
결론: Minto형 회의 맥락/용어집 prompt에서는 개선됐지만 기본 로컬 LLM 후보로는 아직 보류한다.

## 환경

- Runtime: Ollama
- Model: `llama3.1:8b`
- Endpoint: `http://127.0.0.1:11434/api/generate`
- Installed model digest: `46e0c10c039e`
- Context window: `4096`
- Runner timeout: `120` seconds
- Server PID sampled: `58693`
- Benchmark case: `correction_terms_with_context`

## 실행

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model llama3.1:8b \
  --cases correction_terms_with_context \
  --num-ctx 4096 \
  --repeat 1 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-llama3.1-8b-correction-context-numctx4096 \
  --fail-fast
```

## 결과

- `1/1` case가 timeout 없이 응답했다.
- Latency는 `22.979s`다.
- Correction term recall은 `0.75`다.
- Found terms는 `PDCR-2901`, `Confluence`, `dry-run`이다.
- Missing term은 `Liquibase`다.
- `server_rss_peak_mb`는 `117.72` MB로 기록됐다.

## 해석

- 기존 minimal correction prompt에서는 term recall이 `0.0`이었지만, Minto형 meeting topic/glossary prompt에서는 `0.75`로 개선됐다.
- 다만 필수 domain term 중 `Liquibase`가 누락됐고 latency도 `22.979s`라 기본 후보 승격 기준에는 부족하다.
- 현재 결과만으로 `llama3.1:8b`를 Minto 기본 로컬 LLM 후보로 올리지 않는다.
- 다음 후보는 correction context case에서 term recall `1.0`에 더 가까운 instruct 모델을 우선 측정한다.
