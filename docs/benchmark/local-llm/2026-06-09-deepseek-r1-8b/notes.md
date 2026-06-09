# deepseek-r1:8b local LLM benchmark note

작성일: 2026-06-09
결론: 현재 환경에서는 Minto 기본 로컬 LLM 후보로 보류한다.

## 환경

- Runtime: Ollama
- Model: `deepseek-r1:8b`
- Endpoint: `http://127.0.0.1:11434/api/generate`
- Installed model digest: `6995872bfe4c`

## 실행

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model deepseek-r1:8b \
  --repeat 1 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b \
  --fail-fast
```

## 결과

- `correction_terms` 첫 case가 120초 timeout으로 실패했다.
- `--fail-fast` 때문에 summary/answer case는 실행하지 않았다.
- benchmark runner 기준 성공률은 `0/1`이다.
- 실행 후 `ollama ps`에서 model context가 `131072`, model size가 `25 GB`, processor가 `46%/54% CPU/GPU`로 표시됐다.
- `server_rss_peak_mb`는 `ollama serve` PID 기준이라 model runner 전체 메모리로 해석하지 않는다.

## 재현 확인

짧은 직접 요청도 60초 동안 응답을 받지 못했다.

```bash
curl -sS --max-time 60 http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-r1:8b","prompt":"Say OK only.","stream":false,"options":{"num_predict":16,"temperature":0}}'
```

결과:

- `curl: (28) Operation timed out after 60003 milliseconds with 0 bytes received`

## Context window follow-up

- 위 실패는 Ollama가 model context `131072`로 runner를 올린 상태에서 나온 결과다.
- 다음 재측정은 앱/runner와 같은 context cap을 써서 실행한다.
- 권장 재측정 명령:

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model deepseek-r1:8b \
  --num-ctx 4096 \
  --repeat 1 \
  --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-numctx4096 \
  --fail-fast
```

## 해석

- 이 결과는 품질 실패라기보다 현재 모델/runtime 설정에서 latency gate를 통과하지 못한 것이다.
- `deepseek-r1:8b`는 Minto의 교정/요약/검색 답변 기본값 후보로 올리지 않는다.
- 다음 후보는 더 작은 context/빠른 instruct 모델로 측정한다.
