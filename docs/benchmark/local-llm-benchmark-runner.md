# Local LLM benchmark runner

`scripts/run_local_llm_benchmarks.py` measures local text LLM behavior for Minto correction, summary, and search-answer use cases.

The runner uses the same endpoint compatibility modes as the app:

- `ollama`: `POST /api/generate`
- `openai`: `POST /v1/chat/completions`

## Dry run

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --dry-run \
  --model qwen2.5:7b \
  --cases correction \
  --num-ctx 4096
```

Dry-run writes `request_bodies.json` so Ollama `options.num_ctx` can be checked without contacting a model server.

## Mock validation

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --mock \
  --model mock-model \
  --num-ctx 4096 \
  --output-root /tmp/minto2-local-llm-bench-mock
```

Mock mode validates the runner, output files, summary generation, and heuristic scoring without contacting a model server.

## Correction context

The runner includes two correction cases:

- `correction_terms`: minimal system prompt plus one transcript line.
- `correction_terms_with_context`: Minto-style correction prompt with meeting topic, glossary, previous context, and current transcript line.

Use the context case when checking whether a local model can follow the same glossary-assisted correction path as the app.

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model qwen2.5:3b \
  --cases correction_terms_with_context \
  --num-ctx 4096
```

## Ollama run

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model qwen2.5:7b \
  --num-ctx 4096 \
  --repeat 3
```

`--num-ctx` maps to Ollama `options.num_ctx`. Its default is `MINTO_LOCAL_LLM_CONTEXT_WINDOW`, then `4096`. The runner clamps it to `512...32768` and records the applied value in `run_manifest.json`, `metrics.jsonl`, and `summary.md`. OpenAI-compatible mode does not send this option.

## OpenAI-compatible run

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility openai \
  --base-url http://127.0.0.1:8080 \
  --model Qwen2.5-7B-Instruct \
  --repeat 3
```

## RAM sampling

If the model server process ID is known, pass it with `--server-pid`.

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --model qwen2.5:7b \
  --server-pid 12345 \
  --num-ctx 4096 \
  --repeat 3
```

The runner records sampled server RSS in MB while each request is in flight. This is not a whole-system memory profile, but it is enough to compare candidate local runtimes under the same machine state.

## Output

Default output goes to:

```text
tmp/local-llm-benchmarks/<timestamp>/
```

Files:

- `run_manifest.json`: run settings and selected cases
- `request_bodies.json`: dry-run request previews
- `metrics.jsonl`: one metric row per case/repeat
- `<case>-<repeat>.json`: per-run metric detail, including capped `output_preview`, `output_sha256`, and found/missing terms
- `summary.json`: aggregate metrics, `by_case_type`, and `default_candidate_gate`
- `summary.csv`: tabular metrics with found/missing terms
- `summary.md`: human-readable benchmark report with gate breakdown and missing-term triage

For committed benchmark evidence, set an explicit output path under `docs/benchmark/local-llm/`.

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --model qwen2.5:7b \
  --num-ctx 4096 \
  --repeat 3 \
  --output-root docs/benchmark/local-llm/2026-06-09-qwen2.5-7b
```

## Metrics

- correction: expected domain-term preservation
- summary: required JSON fields and term recall
- answer: grounded answer term recall and source-time preservation
- all cases: latency, status, output length, capped output preview/hash, found/missing terms, optional sampled server RSS
- default candidate gate: real non-mock run, correction/summary/answer coverage, transport pass, correction-only output cleanliness, per-type minimum recall, and summary JSON validity

Do not promote a local model as the default until a real non-mock run is recorded and reviewed.
