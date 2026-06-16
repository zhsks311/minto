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

## 수치 해석 주의 (리뷰 반영)

- **startedAt ↔ WAV t=0 오프셋**: `MeetingRecord.startedAt`은 첫 전사 세그먼트 시각이라 WAV t=0(오디오 엔진 첫 샘플)보다 늦을 수 있다. matcher는 `segment.timestamp - meetingStart`로 상대초를 잡으므로, 녹음 시작에 침묵이 길면 diarizer 타임라인과 절대 오프셋이 어긋나 **coverage가 낮게** 나올 수 있다. coverage가 낮으면 파라미터 품질보다 **오프셋을 먼저 의심**하라. 단, 같은 녹음으로 `warmStartFa`/`threshold`를 비교하는 한 오프셋은 상수이므로 **상대 비교는 유효**하다.
- **speaker switch 과소계산**: `speakerSwitchCount`는 라벨 없는(nil) 세그먼트를 투명 처리한다. A→nil→B는 전환 2가 아니라 1로 집계되어, coverage가 낮은 녹음일수록 switch가 과소계산된다. 06-10 display gate의 switch와 직접 비교 시 이 점을 감안하라.
- **화자 번호 결정성**: "화자 N"은 `DiarizationSpeakerLabeling`이 등장 시각순으로 부여하므로 같은 녹음·파라미터에서 실행마다 동일하다(DiarizationResult.segments 배열 순서와 무관).
- **minimumOverlapRatio**(기본 0.5): 러너 env로 노출 안 됨. 조정하려면 `TranscriptSpeakerMatcher(minimumOverlapRatio:)`를 직접 생성한다.
