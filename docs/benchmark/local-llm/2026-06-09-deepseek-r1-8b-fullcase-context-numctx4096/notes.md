# deepseek-r1:8b full-case context benchmark

## Scope

- Runtime: Ollama
- Model: `deepseek-r1:8b`
- Cases: `correction_terms_with_context`, `summary_json`, `grounded_answer`
- Context window: `4096`
- Repeat: `1`

## Command

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model deepseek-r1:8b \
  --cases correction_terms_with_context,summary_json,grounded_answer \
  --num-ctx 4096 \
  --repeat 1 \
  --server-pid 58693 \
  --output-root docs/benchmark/local-llm/2026-06-09-deepseek-r1-8b-fullcase-context-numctx4096 \
  --fail-fast
```

## Result

- Passed: `3/3`
- Mean latency: `36.874s`
- Mean term recall: `0.778`
- Summary JSON valid rate: `1.0`
- Max server RSS: `89.66 MB`

## Case Notes

- `correction_terms_with_context`: term recall `1.0`
- `summary_json`: JSON valid, required field recall `1.0`, term recall `1.0`
- `grounded_answer`: term recall `0.333`, missing `dry-run preview` and `parent page`

## Decision

- `deepseek-r1:8b` is a strong correction/summary candidate in this corpus.
- It is not promoted as the default local model because grounded answer recall is weak and latency is high.
- Next default-candidate evidence should test another model or adjust the answer prompt before repeat runs.
