# Phase 2 화자분리 평가 하니스

날짜: 2026-06-13

## 변경 요약

- `SpeakerDiarizationProvider` 인터페이스와 `FluidAudioOfflineDiarizationProvider`를 추가했다.
- FluidAudio `OfflineDiarizerManager` 결과를 앱 내부 `DiarizedSpeakerSegment`로 변환한다.
- `TranscriptSpeakerMatcher`를 추가해 diarization timeline과 `Segment` 시간을 overlap으로 매칭하고 `화자 N` 라벨을 채운다.
- `DiarizationQualityMetrics`를 추가해 speaker 수, speaker switch 수, transcript coverage, 평균 overlap을 계산한다.
- `DiarizationEvalRunnerTests`를 추가해 실제 WAV 평가를 `RUN_DIARIZATION_EVAL=1`일 때만 실행한다.

## 결정

- 제품 기본 녹음/저장/전사/임포트 흐름에는 연결하지 않았다.
- LSEEND/Sortformer는 이번 범위에 구현하지 않고 `SpeakerDiarizationProvider` 뒤에 추가 가능하게 인터페이스만 열었다.
- 단어 타임스탬프 기반 화자 정렬은 후속 범위로 남기고, 이번 matcher는 segment 단위만 처리한다.
- `warmStartFa`와 `clusteringThreshold`는 provider 생성자와 평가 러너 env로 조정 가능하게 했다.

## 사용법

WAV만 평가:

```bash
RUN_DIARIZATION_EVAL=1 \
DIARIZATION_EVAL_WAV="$HOME/Library/Application Support/Minto/recordings/<audioFileName>.wav" \
./scripts/dev.sh test DiarizationEvalRunnerTests
```

저장된 회의 JSON까지 매칭/메트릭 평가:

```bash
RUN_DIARIZATION_EVAL=1 \
DIARIZATION_WARMSTART_FA=0.15 \
DIARIZATION_CLUSTERING_THRESHOLD=0.6 \
DIARIZATION_EVAL_WAV="$HOME/Library/Application Support/Minto/recordings/<audioFileName>.wav" \
DIARIZATION_EVAL_TRANSCRIPT_JSON="$HOME/Library/Application Support/Minto/meetings/<meetingId>.json" \
./scripts/dev.sh test DiarizationEvalRunnerTests
```

## 검증

- 기준 `./scripts/dev.sh build`: passed
- `./scripts/dev.sh build` after provider: passed
- `./scripts/dev.sh test TranscriptSpeakerMatcherTests`: 5 tests passed
- `./scripts/dev.sh test Diarization`: 3 tests / 2 suites passed, eval runner skipped without env
- `git diff --check`: passed
- 최종 `./scripts/dev.sh build`: passed
- 최종 `./scripts/dev.sh test`: 529 tests / 80 suites passed, eval runner skipped without env

## 주의

- 이 작업은 평가용 테스트 브랜치 하니스다. 제품 동작은 명시 호출 전까지 바뀌지 않는다.
- eval runner는 모델 자동 다운로드가 일어날 수 있으므로 반드시 `RUN_DIARIZATION_EVAL=1` 게이트 뒤에서만 실행한다.
- 로그는 `Log.diarization` 숫자 지표만 사용하며 전사 원문, 토큰, 프롬프트는 남기지 않는다.
