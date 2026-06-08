# Nemotron Sidecar Mock

## 목적

- 실제 MLX/Nemotron 모델을 로드하기 전에 Swift 앱과 sidecar 사이의 HTTP 계약을 검증한다.
- `/health`, `/transcribe`, timeout, warming/error, metric field 처리를 가볍게 재현한다.
- 이 mock은 ASR을 수행하지 않으므로 CER, RTF 성능 판단에 사용하지 않는다.

## 실행

```sh
python3 scripts/nemotron_sidecar_mock.py --port 8765
```

유용한 옵션:

- `--text`: `/transcribe`가 반환할 고정 transcript
- `--delay-ms`: 지연 응답 재현
- `--status warming --http-status 503`: 모델 warm-up 또는 worker unavailable 재현
- `--model-id`, `--quantization`, `--device`: health/metric 표시값 변경

## HTTP 계약

`GET /health` 응답:

- `status`
- `model_id`
- `quantization`
- `device`
- `detail`

`POST /transcribe` 요청:

- `schema_version`: `1`
- `language`: 예: `ko`
- `sample_rate`: `16000`
- `audio_format`: `f32le`
- `audio_base64`: 16kHz mono Float32 little-endian PCM bytes를 base64 인코딩한 값
- `audio_seconds`: payload 길이와 일치해야 한다

`POST /transcribe` 응답:

- `text`
- `model_id`
- `audio_seconds`
- `elapsed_seconds`
- `rtf`
- `peak_memory_mb`

## 다음 단계

- 실제 `mlx-audio` Nemotron worker도 같은 HTTP 계약을 구현한다.
- 앱 연결 전에는 cold start latency, warm latency, timeout, peak memory를 먼저 기록한다.
- meeting CER 비교는 mock이 아니라 실제 worker와 `sample/meeting` 전체 기준으로만 판단한다.
