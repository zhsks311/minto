# 화자분리 계층형 구현 + 부수 UI 계획

작성일: 2026-06-13

사용자 방향(확정): 화자분리를 단일 방법이 아니라 **계층**으로 쌓는다(각 층이 아래층 실패에 영향 안 줌). 1·3·4층(확실·저위험)을 먼저 main에 넣고, 2층(B/C blind diarization)은 테스트 브랜치에서 pyannote·FluidAudio·EEND/Sortformer를 철저 분석·비교 후 셋 다 앱에 넣어 실측한다. 부수로 (3번) 로그 가시성과 메인 윈도우 레벨 미터도 함께.

## 계층 정의 (재확인)

- **1층 (A 채널 분리)**: 마이크=나 / 시스템오디오=상대. ML 없이 결정적. 1:1 화상회의를 공짜로 해결.
- **2층 (B/C blind diarization)**: 시스템 채널 안의 다중 화자 분리. 품질 불확실 → Phase 2.
- **3층 (E 단어 정렬)**: 단어 타임스탬프로 화자 경계를 단어 단위로.
- **4층 (D enrollment)**: 반복 참석자 음성 등록·매칭. **임베딩 모델 의존 → Phase 2와 동행**.

## 코드베이스 사실 (조사 완료, 2026-06-13)

오디오 캡처:
- `AudioSourceProtocol.onBuffer`는 순수 `(@Sendable ([Float]) -> Void)?` — 소스 라벨 없음.
- `MixedAudioSource`는 `DualAudioBufferMixer`로 마이크+시스템을 **단일 믹스로 합산**(샘플 수 정렬, 타임스탬프 동기화 없음). 분리 트랙 미유지.
- `SystemAudioSource`는 ScreenCaptureKit(`excludesCurrentProcessAudio=true`), 16kHz mono.
- `AudioInputMode`는 MeetingRecord에 저장 안 됨. 아카이버는 항상 mono 단일 WAV(`AVNumberOfChannelsKey:1`).

전사 모델·표시:
- `Segment`(Meeting.swift) 필드 = id/text/timestamp/duration. 화자 필드 없음 → `speaker: String?` 추가 시 Codable 하위호환 유지.
- 전사 렌더 3곳: `TranscriptionOverlayView.committedRow`(:338), `MeetingLibraryView.transcriptBlock`(:1785), `MeetingSummaryView.transcriptList`(:272).
- `MeetingExporter.swift:22` map 클로저 한 줄에 화자 분기 추가.
- `audioLevelMeter`: `TranscriptionOverlayView.swift:410`, `viewModel.audioLevel`(0~1) → 16막대. `AudioLevelMeterView(audioLevel:)` struct로 추출해 `MeetingLibraryView.liveMeetingRow`(:928)에서 재사용.
- 단어 타임스탬프: WhisperKit `TranscriptionSegment.words: [WordTiming]?` 이미 존재. `WhisperKitSTTEngine.swift:60 wordTimestamps:false` → true + `Segment.words` 추가 + transcribe에서 `seg.words` 수집. SpeechAnalyzer 경로는 현재 단어 API 미사용.
- `TranscriptNormalizer.merge`는 `current`의 id/timestamp만 보존 → `shouldMerge`에 speaker 동일 조건, merge에 words concat 필요.

## Phase 1 — main 머지 (침습도로 분할)

### Task A — 그라운드워크 + 안전 UI (라이브 캡처 파이프라인 미접촉)

품질 불확실성 0. 1·2·3층이 공유하는 "레일" + 부수 UI.

1. **로그 가시성**: 녹음 시작 시 적용 VAD/repair 결정 로그(`TranscriptionViewModel.swift:237`)와 엔진 결정 로그를 `.info` → `.notice`로 승격(영속·Console 노출). 흐름 로그는 `.info` 유지. (CLAUDE.md 컨벤션: 결정 이벤트는 관측 가능해야)
2. **레벨 미터 컴포넌트화 + 메인 노출**: `audioLevelMeter`를 `AudioLevelMeterView(audioLevel:)` 공용 struct로 추출, 오버레이는 이를 사용, `MeetingLibraryView.liveMeetingRow`에 컴팩트 버전 추가(사이드바=요약 모니터, 오버레이=정밀).
3. **화자 라벨 레일**: `Segment.speaker: String?`(+ `MeetingResult.TranscriptLine` 대응 필드) 추가. 3개 렌더 사이트에서 speaker 있으면 줄 앞에 표시. `MeetingExporter`에서 speaker 있으면 `**[시간] 화자:** 텍스트`. `TranscriptNormalizer`는 speaker 동일할 때만 merge + 다를 때 분리 유지.
4. **단어 타임스탬프 레일**: `Segment.words: [WordTiming]?`(경량 타입) 추가, WhisperKit `wordTimestamps:true` + transcribe에서 수집. normalizer merge 시 words concat. (정렬 로직 자체는 Task B/Phase2에서 소비)
5. 테스트: Segment Codable 하위호환(speaker/words 없는 기존 JSON 로드), normalizer speaker 경계 분리, export 화자 포맷, 단어 타임스탬프 수집, 레벨 미터 추출 후 동등 렌더.

### Task B — 1층 채널 분리 ("나/상대") — 라이브 파이프라인 변경

Task A 머지 후 착수(Segment.speaker 의존). 결정적이지만 7개 지점 변경이라 단독 격리 + 집중 리뷰.

1. `onBuffer` 시그니처에 소스 라벨 추가(또는 `onLabeledBuffer` 신설) — 모든 소스 구현체(Mic/System/Mixed/FileExtractor) 갱신.
2. `MixedAudioSource`에 **분리 방출 모드**: 합산 대신 mic/system을 각 소스 라벨과 함께 상위로. (믹스 모드는 옵션으로 유지)
3. `TranscriptionViewModel`: 채널별 VAD 인스턴스(`[AudioChannel: VoiceActivityDetector]`) + 채널별 onBuffer 분기. STT 결과 Segment에 채널→화자 라벨("나"/"상대") 주입.
4. `AudioChunk.source: AudioChannel?` 추가(VAD→STT까지 소스 관통).
5. 화자 수 동기화 함정: mic/system 타임스탬프 동기화가 없으므로, 채널 라벨은 "어느 파이프라인에서 나왔나"로만 결정(시간 정렬 의존 안 함) → 동기화 부재가 라벨 정확도에 영향 없음.
6. 아카이버: 사후 diarization(Phase 2)을 위해 채널 분리 보존이 필요한지 결정 — 이번엔 기존 mono 유지(2층에서 재검토), 또는 2트랙. **기본: mono 유지**(범위 통제).
7. 시스템오디오 없는 녹음(마이크 only)은 라벨 안 붙임(기존 동작). 설정: 화상회의 모드(mixed/system)에서만 화자 라벨.
8. 테스트: 채널별 청크 라벨링, 분리 방출, mic-only 시 라벨 없음, mixed 모드 라벨 주입.

## Phase 2 — 테스트 브랜치 (B/C 분석 → 비교 → 앱 실측)

병렬 리서치 진행 중(pyannote / FluidAudio 튜닝 여지 / EEND·Sortformer). 결과 취합 후:

1. **비교 매트릭스**: 3종(+필요시 더)의 사용 가능 기능·파라미터·실행 환경(사이드카/CoreML/ONNX)·라이선스·회의 도메인 DER·overlap·enrollment 지원을 한 표로.
2. **벤치마크 하니스 재사용**: 기존 7샘플 + display gate. **타깃 도메인 샘플(소규모 근거리)** 확보가 핵심 — 국회 코퍼스로만 재면 pyannote도 억울하게 기각됨.
3. **셋 다 앱에 통합**(테스트 브랜치): 사이드카/어댑터로 pyannote·FluidAudio·EEND를 같은 인터페이스(오디오→RTTM/세그먼트) 뒤에 두고, 설정/플래그로 전환하며 실측.
4. **4층 enrollment**: 선택된 임베딩 모델로 화자 등록·매칭 + "Speaker N → 이름" 수정의 클러스터 전파. Task A의 speaker 레일에 연결.
5. 게이트 통과 후보만 제품 배선. 미통과여도 1층(채널)+레일은 이미 main에 있어 손실 없음.

## 실행 방식

- 코드 구현: Codex CLI(worktree 분리 + spec.md + `codex exec` 백그라운드 → 활동 워처 → opus 리뷰 → 지적 반영 → 머지). spec은 위 사실/지점을 그대로 박아 구체화.
- 리서치/분석: document-specialist 병렬(진행 중).
- 리뷰: opus critic. QA: ui-qa/실기기 스모크(레벨 미터·화자 표시 렌더, 실녹음 전사).
- 검증 게이트: `./scripts/dev.sh build`/`test`, `git diff --check`, 민감정보 로그 점검.

## 범위 밖 (명시)

- 2층 diarizer 제품 배선(게이트 통과 전), 채널 2트랙 아카이빙(Phase 2 재검토), Silero 파라미터 설정 노출.
