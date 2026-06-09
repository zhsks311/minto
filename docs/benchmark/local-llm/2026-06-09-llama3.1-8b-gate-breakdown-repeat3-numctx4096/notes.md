# llama3.1:8b gate breakdown repeat-3

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
  --output-root docs/benchmark/local-llm/2026-06-09-llama3.1-8b-gate-breakdown-repeat3-numctx4096 \
  --fail-fast
```

## Result

- Runs: 9/9 passed
- Mean latency: 15.905s
- Summary JSON valid rate: 1.0
- Correction min recall: 1.0
- Correction clean rate: 0.0
- Answer min recall: 0.667
- Default candidate ready: false

## Decision

`llama3.1:8b` remains on hold as the default local model candidate. Term recall alone is not sufficient because every correction repeat included explanatory output markers such as `출력:`, `교정합니다`, and `→`. One grounded answer repeat also missed `parent page`.
