# deepseek-r1:8b correction context benchmark

## Scope

- Runtime: Ollama
- Model: `deepseek-r1:8b`
- Case: `correction_terms_with_context`
- Context window: `4096`
- Repeat: `1`

## Command

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model deepseek-r1:8b \
  --cases correction_terms_with_context \
  --num-ctx 4096 \
  --repeat 1 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-correction-context-numctx4096 \
  --fail-fast
```

## Result

- Passed: `1/1`
- Latency: `43.994s`
- Correction term recall: `1.0`
- Missing terms: none
- Max server RSS: `45.88 MB`

## Decision

- `deepseek-r1:8b` preserved all expected domain terms in the Minto-style correction context case.
- It is not promoted as the default local model yet because this run only covers one correction case and latency is high.
- Next default-candidate evidence needs repeat coverage across correction, summary JSON, and grounded answer cases.
