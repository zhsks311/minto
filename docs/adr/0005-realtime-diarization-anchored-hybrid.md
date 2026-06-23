# ADR 0005: 실시간 화자분리 — 앵커드 하이브리드

상태: Proposed → **컴퓨트 feasibility 스파이크 PASS** (2026-06-22, M3 Pro에서 LS-EEND CPU **55~64× RTFx**, `docs/benchmark/2026-06-22-m3pro-lseend-feasibility-spike.md`). 구현 단계 진행 가능. 잔여 스모크(스트리밍 모드 RTFx·실제 동시 실행·장시간 발열/배터리)는 구현 verification에 포함. architect+critic 리뷰 반영 개정 완료.
작성일: 2026-06-22

> CLAUDE.md "ADR 필요 조건" ① 공유 core abstraction 추가(streaming diarizer provider) ② 실행 모델 변경(녹음 중 실시간 추론 파이프라인) 해당 → 다중 관점 리뷰 필수. 본 개정은 architect·critic 리뷰(2026-06-22)를 반영했다.

## Context

Minto는 "회의에 도움이 되는 정보를 실시간 제공"하는 라이브 어시스턴트를 지향한다. 그 일부로 녹음 **중** "누가 말하는지"를 보여줘야 한다.

현재 상태(코드 검증):
- 라이브 녹음은 `ChannelSpeakerLabeler`로 **분리된 채널의 "나"(mic)/"상대"(system)** 라벨만 붙인다(신경망 분리 없음). 채널 정보는 믹싱 **전**에 존재한다.
- 캡처는 `MixedAudioSource`(= `MicrophoneSource` + `SystemAudioSource`를 `DualAudioBufferMixer`로 합침)가 **믹스 mono**를 `onBuffer`로 흘리고, `RecordingAudioArchiver`가 그 믹스를 16kHz mono WAV로 저장한다. → **아카이브 파일엔 모든 화자 음성이 있으나 채널 분리(나/상대)는 소실**된다.
- 파일 임포트(오프라인)는 VBx(community-1) + 보이스프린트로 분리·실명한다.
- `TranscriptionViewModel`은 `@MainActor`. STT(WhisperKit)는 `transcriptionTask`에서 ANE 비동기 실행.

조사·연구 제약(근거: `docs/reports/2026-06-22-analysis-realtime-diarization-design.html`, `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md`):
- 스트리밍은 오프라인보다 본질적으로 부정확, **VBx는 온라인 부적합**. 오프라인 정확도 우위 실측: VBx DER 12% vs LS-EEND 25.7%(AMI 영어 proxy — 한국어 직접 DER은 참조 RTTM 부재로 미측정).
- **Target-Speaker VAD(2024 SOTA)**: 아는 화자를 앵커로 정확도 향상.
- 혼재 회의(원격+대면, 4명 초과 가능) → ≤4명 Sortformer보다 ≤10명 LS-EEND.

**의존 상태(중요)**:
- 보이스프린트 **Phase 3 풀구현 미착수**([[diarization-feature-state]]). → 앵커는 당분간 **"나" 마이크 채널 단일 앵커**로 한정, 보이스프린트 앵커는 Phase 3 이후 활성.
- `LSEENDDiarizer`는 FluidAudio 0.15.2 API(동기·stateful·non-Sendable, `computeUnits: .cpuOnly` 기본). `enrollSpeaker`는 세션 중 호출 시 **타임라인 리셋** 부작용.

## Decision

**"앵커드 하이브리드"** 채택. 단 아래 리뷰 반영 결정을 포함한다.

1. **라이브 패스(녹음 중, CPU)**: `LSEENDDiarizer`(≤10명, `.cpuOnly`)로 실시간 임시 라벨. STT는 ANE 유지 → 경합 회피.
2. **동시성 격리(필수)**: 라이브 diarization을 `@MainActor`(`onBuffer` 클로저)에서 직접 호출하지 않는다. `LiveSpeakerAssignmentUseCase`를 **전용 actor**로 두고 오디오를 넘긴 뒤 **결과 라벨만 @MainActor로 publish**한다(메인 스레드 블로킹·non-Sendable 누출 회피).
3. **provider 추상화는 분리 유지**: streaming(samples/push/stateful)과 기존 offline(URL/one-shot/stateless)은 인터페이스 간극이 근본적 → **별개 프로토콜**(`StreamingSpeakerDiarizationProvider` 신설, 기존 `SpeakerDiarizationProvider` 불변). `any` 단일 통합 시도 안 함.
4. **엔진 교체 가능한 UseCase 인터페이스**: `LiveSpeakerAssignmentUseCase`를 "거친 라이브(채널 라벨)"와 "신경망 라이브(LS-EEND)" 둘 다 끼울 수 있게 설계 → **M3 Pro 스파이크 결과로 엔진을 갈아도 UseCase 위 계층 불변**.
5. **앵커의 두 목적 구분(핵심 명료화)**:
   - (a) **라이브 UX 안정성**: "나" 채널·(Phase 3 후)보이스프린트로 라이브 라벨이 덜 흔들리게. enrollSpeaker는 **세션 시작 전 pre-enrollment만**(중간 추가 불가, 타임라인 리셋 때문).
   - (b) **최종 정확도**: 아카이브가 믹스 mono라 채널 정보가 없으므로, **라이브가 산출한 "나" 구간·보이스프린트를 오프라인 VBx 재조정에 명시적 제약으로 전달**해야 앵커가 최종에 기여한다(파일에 채널이 없으니 자동으론 안 됨).
6. **최종 패스(저장 시)**: 아카이브 믹스에 VBx 재실행(authoritative) → 라이브 임시 라벨과 **재조정**. **VBx는 독립 재실행**이므로 LS-EEND의 25.7%가 최종 품질을 직접 좌우하지 않는다(라이브 UX에만 영향).
7. **재조정 알고리즘**: 라이브 임시 라벨 ID ↔ VBx 최종 라벨 ID를 **시간 겹침(IOU) 최대 매칭**으로 대응 + 보이스프린트 식별로 실명. 기존 `TranscriptSpeakerMatcher`·`VoiceprintMatching.identifySpeakers`·`SpeakerLabelEditing.replacingSpeaker` 재사용.
8. **사용자 편집 보존**: 사용자가 라이브 중 수정한 화자 라벨(Phase 1 편집 UI)은 **재조정이 덮어쓰지 않는다**(편집된 라벨은 고정, 미편집분만 VBx로 확정).
9. **VBx 실행 타이밍**: `stopRecordingAndDrain`의 아카이브 finish 이후, 저장 직전 비동기 실행. `isFinalizingMeeting` 플래그로 대기 UI. 실패 시 라이브 임시 라벨 그대로 저장(fail-soft).

경계: Infra=Streaming/Offline DiarizationProvider, App=`LiveSpeakerAssignmentUseCase`(actor; 바인딩·재조정·타이밍·flag 소유), UI=라벨 표시, Domain=화자 라벨 모델. (기존 `MeetingFileImportUseCase`의 concrete provider 직접생성 패턴을 신규 경로에서 반복하지 않는다.)

## Alternatives

- **거친 라이브(채널 라벨) + 저장 시 VBx만** (신경망 라이브 없음): ANE 부담 0·구현 단순. 라이브는 "나/상대"만(대면 다자·원격 다자 구분 못함). **architect 반론대로 더 나은 1.0일 수 있음** → 기각이 아니라 **Decision #4의 폴백 경로로 채택**(M3 스파이크가 신경망 라이브를 정당화 못하면 이 경로로). 정확도 핵심(2-pass VBx)은 이 경로도 보존.
- **순수 온라인(저장 시 재처리 없음)**: 오프라인 정확도(12%) 버림. 기각.
- **Sortformer 라이브**: 정체성 안정성 최고이나 ≤4명. ⚠️ **재검토 필요** — 2025 Streaming Sortformer(arXiv 2507.18446)는 "4+ 화자에서 오프라인 능가하기도"라 4명 상한 기각 근거가 약해짐. 라이브 등록(enrollment) 강점도 있어 **스파이크에서 LS-EEND와 함께 측정**한다.
- **NME-SC 등 커스텀 클러스터링**: community-1 이탈 + 신설 비용. 기각.
- **클라우드 diarization**: 프라이버시·온디바이스 원칙 위반. 기각.

## Consequences

### Positive
- 실시간 화자 표시 + 저장 시 오프라인급 정확도(2-pass). 기존 자산 재활용(채널·보이스프린트·VBx·exactSpeakerCount·라벨편집). 외부 전송 없음(개인정보 범위 불변). 엔진 교체 가능 구조로 미측정 리스크 흡수.

### Negative
- **M3 Pro 동시실행 성능 미검증**(최대 리스크). **LS-EEND CPU 정확도가 ANE 대비 동일한지 미검증**(25.7%가 CPU서 더 나빠질 수 있음).
- 동시성: non-Sendable LS-EEND를 actor 경계로 넘기는 래핑 필요(Swift 6 strict concurrency).
- 재조정 UX 긴장: 라이브 "철수" → 저장 후 라벨 변경 시 사용자 불신 가능 → UX 설계가 성패 좌우.
- 앵커가 최종에 닿으려면 채널·보이스프린트를 VBx 제약으로 전달하는 추가 배선 필요(아카이브가 믹스라 자동 안 됨).
- 모델 라이선스(NVIDIA Open Model License 등) 상업 배포 제한 가능.

## Migration
- 라이브 라벨: 채널 "나/상대"를 **기반**으로 두고, 신경망 분리는 채널로 안 되는 곳(대면 전체·원격 다자 "상대" 측)에 **추가**한다(덮어쓰지 않음). 저장 schema는 기존 화자 라벨 구조 재사용(비호환 변경 없음 목표).
- 앵커: "나" 마이크 채널은 지금 가능, 보이스프린트 앵커는 **Phase 3 이후**. 최종 패스 앵커는 라이브 채널 구간·보이스프린트를 VBx 제약으로 전달(아카이브 포맷 변경 불요).
- exactSpeakerCount 입력 UX는 파일 임포트 것 재사용.

## Rollback
- **현재 보장**: 신경망 라이브 패스를 만들지 않으면 기존 채널 라벨 동작 그대로(회귀 없음).
- **자동 fail-soft(구현 시 포함)**: 라이브 diarization이 throw·과부하·에러면 catch해 `ChannelSpeakerLabeler` 경로로 자동 강등 — 녹음·STT 불영향. 이건 flag가 아니라 프로젝트 fail-soft 원칙에 따른 기본 에러 처리라 유지한다.
- **명시적 feature flag(수동/빌드 토글)는 보류 (2026-06-22 사용자 결정)**: 위험 평가상 고장 확률 낮음(M3 스파이크 PASS, 주 위험은 라벨 부정확=하이브리드 설계로 흡수) → YAGNI. **실제 문제(발열·배터리·UX 불만 등) 발생 시 추가.** 트레이드오프: flag 추가 전까지 "새 배포 없이 끄기"는 자동 fail-soft 범위로 한정(개발자가 임의로 차단하려면 빌드 필요). critic은 "기능과 함께 구현"을 권고했으나, 낮은 위험을 근거로 보류를 선택함.

## Verification (임계값 — 스파이크 후 확정)
- **M3 Pro 스파이크**: ✅ **컴퓨트 헤드룸 PASS(2026-06-22)** — LS-EEND CPU 단독 RTFx **55~64×**(M3 Pro, batch 모드). STT는 이미 ANE 실시간 동작 + LS-EEND는 다른 유닛(CPU) 55× 여유 → 동시 실시간 가능(높은 확신). LS-EEND CPU 정확도 = 측정값(기본 `.cpuOnly`). **구현 verification으로 이월된 잔여(블로커 아님)**: ① 스트리밍 모드 RTFx(측정은 batch), ② 실제 STT+LS-EEND 동시 구동, ③ 장시간(1~2h) 발열·배터리(STT 단독 대비 +30% 이내 목표), ④ UI 프레임 드롭 없음.
- 라이브: "나" 채널 고정 정확도, 임시 라벨 안정성(라벨 전환 빈도 임계 — 스파이크서 확정).
- 재조정: 임시↔최종 IOU 매핑 정확도(단위테스트), 사용자 편집 보존(테스트), 하이브리드 QA(저장 JSON 화자수·라벨).
- 로그: 라이브 diar 시작·성공·실패, 재조정 결과(화자수 변화·매핑), CPU/ANE 경합 지표.

## Follow-ups
- **M3 Pro 스파이크(선행)** → 결과로 본 ADR 수락/수정(누가·어떻게 수락 판정하는지: 사람이 스파이크 결과로 ADR 상태를 Accepted로 갱신).
- 모델 라이선스 법무 검토(수락 전 게이트로 격상 검토).
- 재조정 UX 설계(Pencil — 상태 변화 화면). **구현 착수 전 필수인지 선택인지: 필수**(사용자 불신 리스크).
- 보이스프린트 Phase 3 완료 + 크로스세션 정확도 측정(앵커 신뢰성 토대).
- 한국어 코퍼스 DER 측정 계획(참조 RTTM 확보 또는 대안) — AMI proxy 의존 해소 시점·방법.
- **대화 맥락 기반 화자 실명(2026-06-23 추가, 별도 레이어)**: 보이스프린트(목소리)로 못 잡는 미등록 화자에, 저장 시 LLM이 전사 맥락에서 이름을 추론해 매핑(예: 호명·자기소개 → "화자 2=김부장"). 선례: DiarizationLM(arXiv 2401.03506), Identity-Aware LLM Refinement(arXiv 2509.15082); 제품은 주로 목소리 프로필(Otter) 또는 참가자 메타데이터(Fireflies/Zoom)를 쓰고, 순수 맥락 추론은 보조 수단. **원칙**: ① 단독 신뢰도 낮음(연구도 "fallback") → **자동 적용 금지·사용자 확인 제안 방식**(프로젝트 "후보는 제안" 원칙), ② **참석자 이름 목록 입력 시 신뢰도 급상승**(LLM이 후보 집합 내 선택 + 보이스프린트 매칭에도 공용 — 현 exactSpeakerCount 입력을 "이름"까지 확장), ③ 전사에 실제 등장한 이름만(환각 방지, CLAUDE.md), ④ 확인된 이름→해당 화자 보이스프린트 등록 제안 → 다음 회의 자동 인식(트랙 C 연결). 우리 LLM(교정·요약) 재사용으로 추가 모델 불요. 오프라인(저장 시) 레이어이며 ADR 0005 핵심 흐름과 독립.
- 다중 관점 리뷰 통과 후 writing-plans로 구현 계획.

## 리뷰 반영 changelog (2026-06-22)
architect: 동시성 격리(actor)·프로토콜 분리·enrollSpeaker pre-session·엔진교체 인터페이스·스파이크 게이트 반영. critic(REVISE): rollback 현재/구현 분리·아카이브 믹스mono(채널소실→VBx제약 전달)·Verification 임계값·Phase3 의존·LS-EEND CPU측정·재조정 알고리즘/사용자편집/VBx타이밍 명시·Sortformer 4명상한 재검토·앵커 목적(라이브UX vs 최종정확도) 구분 반영.
