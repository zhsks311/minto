# sherpa-onnx Korean streaming PoC

## Goal

Evaluate a fully local, free streaming Korean STT path that is not WhisperKit preview/final decoding.

## Candidate

Model: `kangkyu/icefall-asr-ko-streaming-zipformer-72m`

Why this candidate:

- Korean causal Zipformer transducer.
- Trained on KsponSpeech (~1,000 hours).
- Ships sherpa-onnx int8 ONNX files for chunk 16/32/64.
- Model card reports KsponSpeech eval streaming CER:
  - chunk 64: `8.25%`, RTF `0.038`, latency `1.28s`
  - chunk 32: `8.39%`, RTF `0.039`, latency `640ms`
  - chunk 16: `8.635%`, RTF `0.052`, latency `320ms`

This makes it a more realistic streaming baseline than repeatedly decoding rolling Whisper windows.

## Local dependency state

Initial local probe:

- `sherpa_onnx`: not installed globally
- `sherpa-onnx`: CLI not found globally
- `sherpa-onnx-offline`: CLI not found globally

Temporary non-global install used for PoC:

```sh
python3 -m pip install --target /private/tmp/minto2-sherpa-python sherpa-onnx
```

Installed version:

- `sherpa-onnx`: `1.13.2`

## Runner

```sh
env PYTHONPATH=/private/tmp/minto2-sherpa-python \
  python3 scripts/sherpa_streaming_bench.py \
  --raw-dir /Users/d66hjkxwt9/Idea/private/minto2/sample/meeting/raw \
  --max-seconds 120 \
  --chunk-size 16 \
  --audio-chunk-sec 0.64
```

The runner measures:

- partial event count
- partial revision count
- first non-empty partial audio time
- final global CER
- elapsed seconds and RTF

## Interpretation target

Compare it against the committed WhisperKit rolling preview benchmark:

- WhisperKit preview/final on 120s meeting sample:
  - first preview latency: `6.0s`
  - preview revisions: `89 / 120 events`
  - preview RTF p50/p95: `0.11 / 0.19`
  - final RTF p50/p95: `0.16 / 0.20`
  - final global CER: `26.0%`

Sherpa should be judged on the same meeting sample before adopting it. Model-card KsponSpeech CER is only prior evidence, not project evidence.

## Smoke results

30s smoke, chunk 16:

- partial events: `47`
- partial revisions: `28`
- first partial latency: `6.4s`
- elapsed: `0.75s`
- RTF: `0.025`
- global CER: `101.9%` (`distance 53 / ref 52`)

The 30s CER is not decision-grade because the reference segment is too short and early meeting audio has sparse captions.

120s comparison:

| chunk | audio chunk | partial events | partial revisions | first partial | elapsed | RTF | global CER |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | `0.64s` | `188` | `98` | `6.4s` | `2.93s` | `0.024` | `33.3%` |
| 32 | `1.28s` | `94` | `53` | `7.68s` | `2.06s` | `0.017` | `34.5%` |
| 64 | `2.56s` | `47` | `34` | `7.68s` | `1.61s` | `0.013` | `33.7%` |

## Current conclusion

- sherpa-onnx Zipformer is the fastest measured local streaming path so far.
- It is a real streaming recognizer, so its partial revisions are lower than WhisperKit rolling preview when larger chunks are used.
- On this meeting sample, final CER is worse than WhisperKit's 120s result (`26.0%`), so it should not replace WhisperKit as the accuracy-first default.
- It is still worth keeping as a latency-first experimental engine, especially if later paired with correction, domain glossary, or a better Korean meeting-trained Zipformer.
