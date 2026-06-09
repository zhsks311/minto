# qwen2.5:3b Minto correction-context benchmark note

작성일: 2026-06-09
결론: Minto형 회의 맥락/용어집 prompt에서도 기본 로컬 LLM 후보로는 보류한다.

## 환경

- Runtime: Ollama
- Model: `qwen2.5:3b`
- Endpoint: `http://127.0.0.1:11434/api/generate`
- Installed model digest: `357c53fb659c`
- Context window: `4096`
- Runner timeout: `120` seconds
- Server PID sampled: `58693`
- Benchmark case: `correction_terms_with_context`

## 실행

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model qwen2.5:3b \
  --cases correction_terms_with_context \
  --num-ctx 4096 \
  --repeat 1 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-correction-context-numctx4096 \
  --fail-fast
```

## 결과

- `1/1` case가 timeout 없이 응답했다.
- Latency는 `5.223s`다.
- Correction term recall은 `0.0`이다.
- Missing terms는 `PDCR-2901`, `Liquibase`, `Confluence`, `dry-run`이다.
- `server_rss_peak_mb`는 `96.69` MB로 기록됐다.

## 해석

- 기존 minimal correction prompt뿐 아니라 Minto형 meeting topic/glossary prompt에서도 domain term 보존이 실패했다.
- 현재 결과만으로 `qwen2.5:3b`를 Minto 기본 로컬 LLM 후보로 올리지 않는다.
- 빠른 응답 시간은 장점이지만, 교정 기능의 핵심 기준인 glossary-assisted domain term preservation을 충족하지 못했다.
