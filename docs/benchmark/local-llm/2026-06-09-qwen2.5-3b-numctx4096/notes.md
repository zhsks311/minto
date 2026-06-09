# qwen2.5:3b num_ctx=4096 benchmark note

작성일: 2026-06-09
결론: latency는 좋지만 Minto 기본 로컬 LLM 후보로는 보류한다.

## 환경

- Runtime: Ollama
- Model: `qwen2.5:3b`
- Endpoint: `http://127.0.0.1:11434/api/generate`
- Installed model digest: `357c53fb659c`
- Context window: `4096`
- Runner timeout: `120` seconds
- Server PID sampled: `58693`

## 실행

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model qwen2.5:3b \
  --num-ctx 4096 \
  --repeat 1 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-qwen2.5-3b-numctx4096 \
  --fail-fast
```

## 결과

- `3/3` case가 timeout 없이 응답했다.
- Mean latency는 `6.957s`, max latency는 `14.27s`다.
- Summary JSON case는 valid JSON과 required field recall `1.0`을 기록했다.
- Grounded answer case는 term recall `0.6666666666666666`을 기록했다.
- Correction case는 응답은 받았지만 expected domain term recall이 `0.0`이다.
- `server_rss_peak_mb`는 `ollama serve` PID 기준이라 model runner 전체 메모리로 해석하지 않는다.

## 해석

- `qwen2.5:3b`는 `deepseek-r1:8b` controlled run보다 훨씬 빠르다.
- 다만 교정 case에서 `PDCR-2901`, `Liquibase`, `Confluence`, `dry-run` 보존이 모두 실패했다.
- Runner의 `status=passed`는 비어 있지 않은 응답과 형식 검증 기준이다. 기본 후보 판단은 term recall과 latency를 함께 본다.
- 현재 결과만으로 `qwen2.5:3b`를 Minto 기본 로컬 LLM 후보로 올리지 않는다.

## 다음 후보 기준

- correction term recall이 `1.0`에 가까운 instruct 모델을 우선 측정한다.
- 같은 runner case, 같은 `num_ctx=4096`, 같은 machine state로 비교한다.
- 후보 승격 전에는 correction, summary JSON, grounded answer를 모두 통과하고 latency가 실제 설정 UX에서 감당 가능한 수준이어야 한다.
