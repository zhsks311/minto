# Silero VAD 승격 · 교정 배치화 · 오디오 보존 계획

작성일: 2026-06-12

사용자 목표: ① Silero VAD main 승격(검증된 조합 단위, 회의 중 설정 변경 UX 검토 포함), ② Phase 2 교정 배치화, ③ 화자분리 진행.

## 전제 (조사 결과)

- Silero VAD(`SileroVADProcessor`)·`VoiceActivityDetectorFactory`·empty repair(`EmptyFinalRepairPolicy` + `TranscriptionViewModel.transcribeFinalChunk`)는 **이미 main에 존재**하며 환경변수로만 활성화된다(`MINTO_VAD_ENGINE=silero`, `MINTO_EMPTY_FINAL_REPAIR=1`). 기본 모델 경로는 `/private/tmp/minto2-fluidaudio-models`(휘발성).
- FluidAudio `VadManager(config:modelDirectory:progressHandler:)`는 모델이 없으면 **자동 다운로드**한다(silero-vad ~1.0MB). 별도 다운로드 코드가 필요 없다.
- 검증된 조합(experiment/stt-engine-poc 벤치마크): Silero `threshold=0.6, padding=0.12s, merge gap=1.1s`(= 코드의 `Configuration.defaultCandidate`) + repair `pad=1.0s, min chunk=2.0s, min audio=-35dB`(= `fromEnvironment` 기본값). short3 full-duration에서 weighted CER 56.5%→30.7%, empty 75→9. all7에서 empty 329→133.
- 화자분리의 전제인 녹음 오디오 보존은 현재 없음(`MeetingRecord`에 오디오 경로 필드 없음).

## A. Silero VAD 승격 (feat/silero-vad-promotion)

승격 단위는 "Silero VAD + empty repair" 검증 조합이다. 활성화 게이트를 환경변수 → 사용자 설정으로 옮기고, 모델은 앱이 직접 받는다.

1. **모델 경로 영속화**: 기본 modelDirectory를 `/private/tmp/...` → `~/Library/Application Support/Minto/models/fluidaudio`. 환경변수 override는 유지(벤치마크 호환).
2. **`SileroVADModelStore`**(@MainActor, ObservableObject): `ModelState` 재사용(downloading 진행률), `prepare()`가 `VadManager` init으로 다운로드를 트리거. AppDelegate 시작 시 silero 선택 + 모델 부재면 백그라운드 prepare(1MB라 부담 없음).
3. **설정화**: `VADEnginePreferences`(key `selectedVADEngine`, `energy|silero`, **기본 silero**) — 벤치마크 근거(CER −10%p, empty −199)로 기본 승격하되, 모델 미준비·로드 실패 시 Energy로 fail-soft(기존 factory 동작 유지). env `MINTO_VAD_ENGINE`은 설정보다 우선.
4. **repair 설정화**: key `emptyFinalRepairEnabled`(**기본 켬**). env `MINTO_EMPTY_FINAL_REPAIR`가 있으면 env 우선. 파라미터는 검증값 고정(설정 노출 안 함 — 단계적 공개 원칙).
5. **VAD 생명주기**: `TranscriptionViewModel.vadProcessor`를 `var` + factory closure로 바꿔 **녹음 시작 시점에 설정을 읽어 재생성**. DI init은 기존처럼 고정 인스턴스(테스트 비영향).
6. **Settings UI**: "음성 구간 감지" 그룹 — 엔진 선택(Silero 권장/Energy), 모델 상태 표시(다운로드 중 %/준비됨/실패+재시도), 빈 구간 복구 토글. 설정 변경 onChange 로그(기존 `logSettingChange` 패턴).
7. **로깅**: 녹음 시작 시 적용 엔진(`vad=` 실제 적용값)과 repair 여부를 `.info`로 — "설정이 반영됐는지"를 로그로 확인(이벤트 로깅 컨벤션).

### 회의 중 설정 변경 UX 검토 (사용자 요청)

- **VAD 엔진**: 녹음 중 변경 시 진행 중 버퍼·청크 상태가 깨지므로 **즉시 적용하지 않고 다음 녹음부터 적용**. 설정은 언제든 변경 가능하고, 녹음 중에는 "다음 녹음부터 적용돼요" 캡션을 표시한다. (기존 STT 엔진의 "선택과 전환 분리" 패턴과 일관)
- **빈 구간 복구 토글**: 정책을 사용 시점(녹음 종료 final 처리)에 읽도록 바꿔 **회의 중 변경이 현재 녹음에도 즉시 반영**된다. 상태 파괴가 없는 설정이라 즉시 적용이 사용자 기대와 일치.
- 결론: "회의 중 수정 가능"은 설정별로 갈린다 — 상태 비파괴(repair)는 즉시, 상태 파괴(VAD 엔진)는 다음 녹음. UI가 이 차이를 캡션으로 드러낸다.

### 테스트

factory의 설정 기반 선택/우선순위(env>설정)/모델 부재 fallback, repair 정책 resolve(env>설정>기본), 녹음 시작 시 VAD 재생성(스텁 factory 카운트), 모델 경로 영속 위치.

## B. 교정 배치화 Phase 2 (feat/import-correction-batching)

임포트 교정 호출을 청크 3개 단위로 묶는다. 목적: 호출 수 1/3(rate limit 보호) + 고정비용 절감.

1. `LLMTextRequest`에 `maxOutputTokensHint: Int?`(기본 nil) 추가 — `LLMAPIKeyTextProvider.maxOutputTokens(for:)`는 hint가 있으면 hint 사용. 다른 provider는 무시해도 무해(필드 추가만).
2. `BatchCorrectionPrompt`: 번호 매긴 N개 세그먼트를 한 번에 교정하는 instructions + `[1] ...` 형식 응답 계약. 파서는 번호 누락·병합 시 **배치 전체 fail-soft**(원문 유지).
3. `ImportCorrectionPipeline`: 청크를 배치 크기 3으로 모아 디스패치(마지막 잔여는 작은 배치). 배치 hint = `900 × 배치 크기`. 단건(배치 1)은 기존 단일 교정 경로 그대로.
4. 순서 보존·fail-soft·취소 계약은 Phase 1과 동일하게 유지. 테스트: 배치 프롬프트/파싱 왕복, 파싱 실패 fail-soft, 잔여 배치, hint 전달.

## C. 화자분리 1단계 — 녹음 오디오 보존 (feat/recording-audio-retention)

화자분리(사후 diarization)의 전제. 이번 단계 범위는 보존만이고 diarizer 연결은 후속.

1. `RecordingAudioArchiver`: 녹음 중 마이크 샘플(16kHz mono)을 `Application Support/Minto/recordings/<recordID>.wav`로 스트리밍 기록. 실패는 fail-soft(녹음·전사에 영향 금지, `.error` 로그).
2. `MeetingRecord.audioFileName: String?`(optional, Codable 하위 호환 — 기존 파일 로드 시 nil).
3. 설정: "녹음 오디오 보관"(기본 켬, 로컬 전용 명시) + 보관 기간(기본 30일). 앱 시작 시 기간 경과 파일 정리(`.info` 로그로 건수 기록).
4. 임포트 오디오 보존은 diarizer 연결 시점에 결정(원본 파일 접근 유지 vs 추출본 저장).

기본값 근거: 화자분리·재전사·구간 듣기의 공통 전제라 기본 켬. 프라이버시는 "로컬 저장, 외부 전송 없음"을 설정 문구에 명시하고 끌 수 있게 한다.

## 순서와 검증

A → B → C1 순서로 브랜치별 opus 리뷰 → main 머지. 각 단계: `git diff --check` + `./scripts/dev.sh build` + 전체 테스트.

## 범위 제외 (후속)

- 화자분리 diarizer 연결(pyannote 사이드카 벤치마크 — HF gated 모델 인증 필요), 단어 타임스탬프 정렬, 클러스터 rename UI
- Silero 파라미터의 설정 노출(검증값 고정 유지)
- 녹음 경로 교정 배치화(이미 30초 window 배치 존재)
