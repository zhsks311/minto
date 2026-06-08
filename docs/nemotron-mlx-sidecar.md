# Nemotron MLX Sidecar

## 목적

- `mlx-audio` Nemotron ASR을 앱 밖 Python worker로 띄운다.
- Swift 앱은 기존 `NemotronSidecarClient` HTTP 계약만 본다.
- 앱 기본 엔진으로 연결하기 전, cold start latency, warm latency, timeout, peak memory를 먼저 측정한다.

## 전제

- Apple Silicon Mac
- Python 환경에 `mlx-audio` 설치
- 사용할 Nemotron 모델 weight 다운로드 가능 또는 캐시 완료
- 16kHz mono Float32 PCM 입력

## 실행 전 확인

```sh
python3 scripts/nemotron_mlx_sidecar.py --check-dependencies
```

이 명령은 `mlx_audio.stt` import 가능 여부만 확인하고 모델 weight는 로드하지 않는다.

## 실행

개발 중에는 lazy-load가 기본이다. 서버는 먼저 뜨고, 첫 `/transcribe` 요청에서 모델을 로드한다.

```sh
python3 scripts/nemotron_mlx_sidecar.py --port 8765
```

cold start를 명확히 보고 싶으면 worker 시작 때 모델을 로드한다.

```sh
python3 scripts/nemotron_mlx_sidecar.py --port 8765 --preload
```

## Benchmark

worker를 띄운 뒤 `sample/meeting`을 같은 HTTP 계약으로 측정한다.

```sh
python3 scripts/nemotron_sidecar_bench.py \
  --base-url http://127.0.0.1:8765 \
  --window-sec 60 \
  --max-seconds 0
```

빠른 smoke는 한 샘플, 한 window만 실행한다.

```sh
python3 scripts/nemotron_sidecar_bench.py \
  --base-url http://127.0.0.1:8765 \
  --samples 본회의_20260508 \
  --max-windows 1
```

결과는 `tmp/nemotron-sidecar-benchmarks/<timestamp>/summary.json`과 샘플별 JSON에 저장된다.
mock worker로도 runner smoke는 가능하지만, mock transcript는 CER 근거로 사용하지 않는다.

## 모델과 언어

기본 모델:

- `mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit`

문서상 Nemotron은 `model.generate("speech.wav")`로 자동 언어 감지를 사용한다.
`--force-language`를 주면 `model.generate(..., language="...")`로 넘긴다.
한국어 prompt key는 실제 모델 문서와 샘플로 확인하기 전까지 기본값으로 고정하지 않는다.

## HTTP 계약

- `GET /health`
  - dependency 가능 여부
  - model loaded 여부
  - model load elapsed
  - peak memory
- `POST /transcribe`
  - mock worker와 같은 `schema_version=1`, `audio_format=f32le`, `audio_base64` 계약을 사용한다.
  - worker 내부에서 Float32 PCM을 임시 16kHz mono WAV로 변환한 뒤 `model.generate()`에 전달한다.
- `scripts/nemotron_sidecar_bench.py`는 WAV 전체를 메모리에 올리지 않고 window별로 읽어서 같은 계약으로 요청한다.

## Swift 연결 상태

- `NemotronSidecarClient`는 `/health`와 `/transcribe` HTTP 계약을 구현한다.
- `NemotronSidecarTranscriber`는 sidecar 응답을 앱 내부 `TranscriptionResult`로 변환한다.
- 이 adapter는 0.5초 미만 입력 padding과 무음 skip을 기존 엔진들과 같은 `STTAudioUtilities`로 처리한다.
- 아직 `SpeechEngineID`, 설정 UI, 기본 fallback, `STTService.makeEngine`에는 연결하지 않았다.
- 제품 선택지로 노출하기 전에는 mock worker가 아니라 실제 MLX worker로 전체 `sample/meeting` CER, latency, peak memory, 장시간 안정성을 확인해야 한다.

## 주의

- 이 worker는 true streaming이 아니라 final chunk용 one-shot sidecar다.
- streaming Nemotron 실험은 `stream=True` 또는 모델별 streaming API를 별도 worker로 나눠 측정한다.
- 앱 UI에 연결하기 전에는 `sample/meeting` 전체 CER, current VAD chunk CER, peak memory, 30분 반복 실행을 통과해야 한다.
