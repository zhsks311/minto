# STT parallel PoC plan

## Goal

무료 또는 local-first 한국어 STT 후보를 빠르게 걸러낸다. main 앱 구조는 바로 바꾸지 않고, 독립 PoC 결과로 다음 구현 대상을 정한다.

## Common sample

- Primary: `sample/meeting/raw/본회의_20260508_full.wav`
- Reference: `sample/meeting/raw/본회의_20260508_smi.json`
- Smoke test: first 30-60 seconds
- Benchmark target: first 120 seconds when the runner is stable

## Lanes

1. BatiSay Transformers
   - Check whether `AutoModel.from_pretrained("batiai/batisay-ko-base", dtype="auto")` loads.
   - Identify required processor/tokenizer/audio input format.
   - Measure CER/RTF only if inference is available.

2. STT engine structure
   - Find the minimum seam between `TranscriptionViewModel` and STT backends.
   - PoC a small adapter shape without changing production behavior.

3. True streaming candidates
   - Re-check sherpa-onnx Korean Zipformer reproducibility.
   - Re-check Apple SpeechAnalyzer Korean support.
   - Compare against WhisperKit rolling preview/final metrics.

4. CoreML/MLX feasibility
   - Check whether BatiSay can realistically become CoreML/MLX.
   - Check whether MLX ASR candidates can run locally on Mac.

## Decision metrics

- Load success
- Inference success
- CER
- RTF
- First partial latency for streaming candidates
- Integration complexity
- Blocking dependency or model artifact

## Stop conditions

- A lane is complete when it produces measured numbers or a reproducible blocker.
- Do not claim a model is better without sample-based CER/RTF evidence.
- Do not integrate app changes into main until the winning lane is selected.
