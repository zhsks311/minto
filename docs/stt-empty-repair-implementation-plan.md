# Empty final repair implementation plan

작성일: 2026-06-09

## 목표

WhisperKit final 전사가 빈 문자열을 반환하는 일부 VAD chunk를 제품 경로에서도 실험할 수 있게 한다.

기본값은 바꾸지 않는다. repair는 feature flag가 켜졌을 때만 동작한다.

## 범위

- `TranscriptionViewModel`이 녹음 중 원본 16kHz PCM sample을 짧게 보관한다.
- final VAD chunk의 첫 STT 결과가 empty일 때만 retry 후보가 된다.
- retry는 chunk 자체가 아니라 원본 buffer에서 `startSeconds/endSeconds` 앞뒤를 조금 넓힌 sample로 수행한다.
- retry는 1회만 수행한다.
- retry 결과도 empty면 기존 empty-final 동작을 유지한다.

## 안전 조건

- feature flag 기본값은 off다.
- chunk duration이 너무 짧으면 retry하지 않는다.
- 원본 chunk RMS가 너무 낮으면 retry하지 않는다.
- 원본 buffer에 앞뒤 padding 구간이 없으면 retry하지 않는다.
- retry 결과가 empty면 pending preview를 지우지 않는다.

## Feature flags

- `MINTO_EMPTY_FINAL_REPAIR=1`: 제품 경로에서 empty final repair를 켠다. 기본값은 off다.
- `MINTO_EMPTY_FINAL_REPAIR_PAD_SEC`: retry용 앞뒤 padding 초. 기본값은 `1.0`이다.
- `MINTO_EMPTY_FINAL_REPAIR_MIN_CHUNK_SEC`: retry 최소 chunk 길이. 기본값은 `2.0`이다.
- `MINTO_EMPTY_FINAL_REPAIR_MIN_AUDIO_DB`: retry 최소 RMS dB. 기본값은 `-35.0`이다.
- `MINTO_EMPTY_FINAL_REPAIR_BUFFER_SEC`: 원본 PCM ring buffer 보관 길이. 기본값은 `45.0`이다.

## 검증 기준

- 기본 off 상태에서는 기존 stop/drain 테스트의 STT 호출 횟수가 늘지 않는다.
- feature flag on 상태에서 empty final이면 padded retry sample로 한 번 더 전사한다.
- guard에 걸린 chunk는 retry하지 않는다.
- `swift test --disable-sandbox --filter TranscriptionViewModelStopTests`가 통과한다.
- `git diff --check`가 통과한다.
