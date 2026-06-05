# BatiSay CT2 smoke result

## Command

```sh
python3 scripts/batisay_faster_whisper_bench.py \
  --raw-dir /Users/d66hjkxwt9/Idea/private/minto2/sample/meeting/raw \
  --max-windows 3 \
  --download-root /private/tmp/minto2-batisay-models
```

## Result

- `faster-whisper`: installed (`1.2.1`)
- `huggingface_hub`: installed (`1.16.1`)
- `soundfile`: installed (`0.13.1`)
- `numpy`: installed (`2.2.4`)
- `mlx_whisper`: installed but unavailable in this headless session because Metal device loading fails
- `transformers`: not installed
- `whisper-cli`: installed at `/opt/homebrew/bin/whisper-cli`, but the BatiSay model card warns that Homebrew whisper.cpp 1.8.4 is broken for this model

The live smoke could not run because `huggingface_hub.list_repo_files("batiai/batisay-ko-base")` currently exposes only:

- `.gitattributes`
- `README.md`
- `sanity_check.py`

No `ct2/`, `ggml/`, `mlx/`, or `coreml/` files are exposed by the current repository API. The model card describes those formats, but the downloadable files are not currently present from this environment.

The runner now fails before model initialization with:

```text
FileNotFoundError: batiai/batisay-ko-base currently exposes no ct2/ files via huggingface_hub. Visible files: .gitattributes, README.md, sanity_check.py. Provide --model-path if you have a local CT2 export.
```

## Interpretation

- BatiSay remains a good Korean-specialized candidate based on its model card, but it is not currently measurable here without a local CT2/GGML/CoreML export.
- The runner now fails with a clear message when the advertised `ct2/` files are absent.
- Next valid step is to re-check the repo later or obtain a local CT2 export path and rerun with `--model-path`.
