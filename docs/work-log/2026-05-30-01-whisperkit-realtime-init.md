# 세션 1 — WhisperKit 기반 실시간 전사 앱 초기 구현

_2026-05-30 · 커밋 `5e3c89b`_

## 프롬프트
> "뭔가 비슷하게 기록 하려고 하는 거 같긴한데 내용 엄청 비어있고 많이 부정확해"
> "왜 실시간 전사를 안 하는거야? 아예 거의 실시간으로 오는거 받아 적을 수 없어?"

## 작업 내용
- VAD 파라미터 조정: `maxChunkDuration=15s`, `previewInterval=1.0s`, `minPreviewSamples=0.5s`
- 텍스트 사라짐 버그 수정: `pendingSegment = nil` 위치를 `await transcribe()` 완료 후로 이동
- 전사 stalling 수정: preview를 별도 cancel-and-replace Task로 분리 (serial AsyncStream에서 꺼냄)
- Whisper 품질 지표 기반 할루시네이션 필터 도입: `noSpeechProb`, `avgLogprob`, `compressionRatio`
- `TranscriptionState` sliding window → 직접 커밋 방식으로 변경
