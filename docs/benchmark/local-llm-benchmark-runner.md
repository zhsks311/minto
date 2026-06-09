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
  --cases correction
```

## Mock validation

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --mock \
  --model mock-model \
  --output-root /tmp/minto2-local-llm-bench-mock
```

Mock mode validates the runner, output files, summary generation, and heuristic scoring without contacting a model server.

## Ollama run

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --base-url http://127.0.0.1:11434 \
  --model qwen2.5:7b \
  --repeat 3
```

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
- `metrics.jsonl`: one metric row per case/repeat
- `<case>-<repeat>.json`: per-run metric detail
- `summary.json`: aggregate metrics
- `summary.csv`: tabular metrics
- `summary.md`: human-readable benchmark report

For committed benchmark evidence, set an explicit output path under `docs/benchmark/local-llm/`.

```bash
python3 scripts/run_local_llm_benchmarks.py \
  --compatibility ollama \
  --model qwen2.5:7b \
  --repeat 3 \
  --output-root docs/benchmark/local-llm/2026-06-09-qwen2.5-7b
```

## Metrics

- correction: expected domain-term preservation
- summary: required JSON fields and term recall
- answer: grounded answer term recall and source-time preservation
- all cases: latency, status, output length, optional sampled server RSS

Do not promote a local model as the default until a real non-mock run is recorded and reviewed.
