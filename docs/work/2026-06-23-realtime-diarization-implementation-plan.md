# 실시간 화자분리 (앵커드 하이브리드) 구현 계획

> **For agentic workers:** 코드 단위는 Codex 위임, 계획·리뷰(critic+Codex 크로스)·검증·머지는 메인 세션. push 보류. ADR 0005 기준.

**Goal:** 회의 녹음 중 실시간 임시 화자 라벨을 보여주고, 저장 시 VBx로 정확히 확정하는 "앵커드 하이브리드" 화자분리를 구현한다.

**Architecture:** 라이브 = LS-EEND(CPU, 전용 actor) 임시 라벨 → UI publish. 저장 시 = VBx(아카이브 믹스) authoritative 재실행 → IOU 매핑으로 재조정·실명. "나" 채널·보이스프린트는 앵커(라이브 UX + VBx 제약). 실패 시 채널 라벨 자동 강등(fail-soft).

**Tech Stack:** Swift 6, FluidAudio 0.15.2(`LSEENDDiarizer`/offline VBx), WhisperKit(STT), SwiftUI/AppKit.

## Global Constraints (ADR 0005 + CLAUDE.md, verbatim)
- LS-EEND는 `.cpuOnly`(STT ANE와 경합 회피). 라이브 diarization은 `@MainActor`에서 직접 호출 금지 → 전용 actor, 라벨만 publish.
- streaming/offline diarizer는 **별개 프로토콜**(통합 금지).
- 앵커(보이스프린트/enrollSpeaker)는 **세션 시작 전 pre-enrollment만**(중간 호출 시 LS-EEND 타임라인 리셋).
- 보이스프린트 앵커는 **Phase 3 이후**; 현재는 "나" 마이크 채널 단일 앵커.
- 아카이브는 믹스 mono(채널 소실) → 앵커가 최종에 닿으려면 라이브 "나" 구간·보이스프린트를 **VBx 제약으로 명시 전달**.
- 사용자가 라이브 중 고친 라벨은 재조정이 **덮어쓰지 않음**.
- fail-soft: 라이브 diarization 실패가 녹음·STT를 막으면 안 됨.
- feature flag(수동/빌드 토글)는 보류, 자동 fail-soft만 구현(2026-06-22 결정).
- 로그: `Log.<category>`(os.Logger)만, 민감값 금지(카운트·enum·식별자만), 시작·성공·실패 함께.

## Scope 분해 (skill Scope Check)
이 계획 = **핵심 실시간 화자분리(ADR 0005)**만. 다음은 **각각 별도 계획**(여기 포함 안 함):
- 방법2(대화 맥락 화자 실명) — ADR 0005 follow-up, LLM 후처리 별도 레이어
- Phase 3 보이스프린트 풀구현(크로스세션) — 앵커 신뢰성 토대
- 트랙 B(오프라인 추가향상)·트랙 C(회의 간 기억)
- 한국어 DER 측정 계획 — **사용자 지시로 제외**

---

## Phase 0 — 선행 게이트 (구현 코드 진입 전 필수)

상세 TDD 코드 단계(Phase 1~)는 아래 두 산출물이 확정돼야 무-플레이스홀더로 작성 가능. 따라서 Phase 0을 먼저 완료한다.

### Task 0a: LS-EEND 스트리밍 API 매핑 (조사 = 메인 세션)
**Files:** Read `.build/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/LS-EEND/LSEENDDiarizer.swift`, `DiarizerProtocol.swift`, `DiarizerTimeline*.swift`.
- [ ] 스트리밍 호출 패턴 확정: `process(samples:sourceSampleRate:)` 시그니처, 청크 크기, 반환 `DiarizerTimelineUpdate` 구조, finalize 시점.
- [ ] `timeline.speakers` 갱신·화자 등장/소멸 표현, 라벨 ID 체계.
- [ ] enrollSpeaker(pre-session) 호출 시그니처·제약.
- [ ] 산출물: `docs/work/lseend-streaming-api-notes.md` (실측 시그니처·예제).

### Task 0b: 재조정 알고리즘 명세 (설계 = 메인 세션)
- [ ] 라이브 임시 라벨 ID ↔ VBx 최종 라벨 ID 매핑 = **시간 겹침(IOU) 최대 매칭** 의사코드 확정(동점·미매칭 처리 포함).
- [ ] 사용자 편집 라벨 보존 규칙(편집된 segment는 고정, 미편집만 VBx로 치환).
- [ ] 앵커("나" 구간) → VBx 제약 전달 방식 확정(min/max·numSpeakers·known-segment 중 무엇).
- [ ] 산출물: `docs/work/reconciliation-algorithm-spec.md`.

### Task 0c: 재조정 UX 설계 (Pencil — CLAUDE.md 3+상태 필수)
- [ ] 상태: 녹음 중(임시 라벨) / 저장 중(확정 진행) / 저장 후(확정·실명) / 편집됨(보존) / fail-soft(채널 라벨).
- [ ] "임시→확정 라벨 변경"을 불신 없이 보여주는 화면(예: "정리 중…" → 부드러운 전환, 변경 표시).
- [ ] `.pen` + export → `Resources/designs/`.

**Phase 0 게이트**: 0a·0b·0c 완료 후 critic 리뷰 → 통과 시 Phase 1 착수. (이 시점에 본 계획의 Phase 1~ 상세 TDD 단계를 확정 API/알고리즘으로 채운다.)

---

## Phase 1 — StreamingSpeakerDiarizationProvider (Infra, 코드=Codex)
**Files:** Create `Sources/Minto/Services/Diarization/StreamingSpeakerDiarizationProvider.swift`, Test `Tests/MintoTests/StreamingSpeakerDiarizationProviderTests.swift`.
**Interfaces (produces):** `protocol StreamingSpeakerDiarizationProvider: Sendable { func start(preEnrolled: [Voiceprint]) async throws; func process(samples: [Float]) async throws -> [DiarizedSpeakerSegment]; func finish() async throws -> [DiarizedSpeakerSegment] }` (정확 시그니처는 Task 0a 후 확정). FluidAudio `LSEENDDiarizer(.cpuOnly)` 래핑. 기존 offline `SpeakerDiarizationProvider`와 **별개**.
- 작업: LS-EEND 어댑터(actor-safe 래핑), pre-enrollment, 청크 처리→세그먼트 변환. TDD 단계는 0a 확정 후.

## Phase 2 — LiveSpeakerAssignmentUseCase (App, 전용 actor, 코드=Codex)
**Files:** Create `Sources/Minto/Services/LiveSpeakerAssignmentUseCase.swift`, Test 동.
**Interfaces:** actor. 오디오 청크 수신 → StreamingProvider 호출 → transcript segment와 시간 바인딩(기존 `TranscriptSpeakerMatcher` 재사용) → **라벨만 @MainActor로 publish**(AsyncStream/콜백). "나" 채널 prior 적용. `TranscriptionViewModel.onBuffer`에서 직접 호출 안 함 — UseCase에 오디오 전달.

## Phase 3 — UI 라이브 라벨 표시 (코드=Codex)
**Files:** Modify `Sources/Minto/ViewModels/TranscriptionViewModel.swift`, 라이브 transcript 뷰.
- UseCase 결과 구독 → 임시 라벨 표시(Task 0c UX 반영). 상태: empty/실시간/저장중/확정/fail-soft.

## Phase 4 — 저장 시 재조정 (App, 코드=Codex)
**Files:** Modify `MeetingFileImportUseCase`/저장 경로 또는 신규 `LiveDiarizationReconciler.swift`.
- `stopRecordingAndDrain`(아카이브 finish) 이후, 저장 직전: 아카이브 믹스에 offline VBx 실행 → Task 0b IOU 매핑으로 재조정 → 보이스프린트 실명(`VoiceprintMatching.identifySpeakers` 재사용) → 사용자 편집 보존. `isFinalizingMeeting` 대기 UI. 앵커("나" 구간)를 VBx 제약으로 전달.

## Phase 5 — 자동 fail-soft (코드=Codex)
- 라이브 diarization throw/과부하/에러 → catch → 채널 라벨(`ChannelSpeakerLabeler`) 경로로 강등, `Log.diarization.error`. 녹음·STT 불영향 단위테스트.

## Phase 6 — 구현 중 검증 (스파이크 이월분, 측정=메인)
- [ ] 스트리밍 모드 RTFx(라이브 청크 처리, batch 55× 대비).
- [ ] 실제 STT(ANE)+LS-EEND(CPU) 동시 구동 RTFx>1.0.
- [ ] 장시간(1~2h) 발열·배터리(STT 단독 대비 +30% 이내 목표).
- [ ] UI 프레임 드롭 없음.
- 미달 시 → 폴백(채널 라벨 라이브 + 저장 시 VBx)으로 범위 축소(UseCase 인터페이스가 엔진 교체 허용).

## 각 Phase 공통 검증
`swift build/test --disable-sandbox --scratch-path /tmp/minto2-rtdiar`; 코드=Codex→critic+Codex 크로스 리뷰→빌드게이트→머지(--no-ff, push 보류). 하이브리드 QA(앱 실행, 저장 JSON 화자수·라벨).

## Self-review
- Spec 커버리지: ADR 0005 Decision 1~9 → Phase 0~5 매핑됨. Verification → Phase 6.
- 미확정 코드: Phase 1~5의 정확 Swift 시그니처는 Task 0a/0b 산출물로 확정 후 채움(현재 fabricate 금지).
- 분해: 방법2/Phase3/트랙은 별도 계획으로 분리(여기 미포함).
