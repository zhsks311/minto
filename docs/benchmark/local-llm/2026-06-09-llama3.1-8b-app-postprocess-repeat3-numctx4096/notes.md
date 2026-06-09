# llama3.1:8b app postprocess benchmark

날짜: 2026-06-09

## Command

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model llama3.1:8b \
  --cases correction_terms_with_context,summary_json,grounded_answer \
  --num-ctx 4096 \
  --repeat 3 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-llama3.1-8b-app-postprocess-repeat3-numctx4096 \
  --fail-fast
```

## Result

- Transport: 9/9 passed
- Mean latency: 28.813s
- Summary JSON valid rate: 1.0
- Raw correction clean rate: 0.0
- Raw correction length OK rate: 0.0
- App correction term recall: 1.0
- App correction clean rate: 1.0
- App correction length OK rate: 1.0
- Answer min term recall: 1.0
- `default_candidate_ready`: false
- `app_default_candidate_ready`: true

## Decision

앱의 correction output postprocessor를 적용한 품질 gate는 통과했다. 다만 평균 latency가 28.813s이고 summary/answer case가 각각 평균 35.352s, 33.908s이므로 기본값 승격은 별도 latency 정책과 반복 안정성 판단 후 결정한다.
