# BatiSay final STT PoC

## Purpose

Compare `batiai/batisay-ko-base` against the current local WhisperKit final model on the same meeting corpus.

## Why faster-whisper first

- The model card publishes `ct2/` in the main repository.
- Python `faster-whisper` is installed locally.
- `transformers` is not installed.
- `mlx_whisper` currently fails in this headless session because Metal is unavailable.
- Homebrew `whisper-cli` is installed, but the model card warns that macOS Homebrew whisper.cpp 1.8.4 is broken for this model.

## Commands

Dry-run dependency check:

```sh
python3 scripts/batisay_faster_whisper_bench.py --dry-run
```

Short measured run:

```sh
python3 scripts/batisay_faster_whisper_bench.py \
  --raw-dir /Users/d66hjkxwt9/Idea/private/minto2/sample/meeting/raw \
  --max-windows 10
```

The script downloads only the `ct2/` folder from `batiai/batisay-ko-base` unless `--model-path` is supplied.
