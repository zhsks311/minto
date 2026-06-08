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

## 주의

- 이 worker는 true streaming이 아니라 final chunk용 one-shot sidecar다.
- streaming Nemotron 실험은 `stream=True` 또는 모델별 streaming API를 별도 worker로 나눠 측정한다.
- 앱 UI에 연결하기 전에는 `sample/meeting` 전체 CER, current VAD chunk CER, peak memory, 30분 반복 실행을 통과해야 한다.
