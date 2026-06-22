# ADR 0005: 실시간 화자분리 — 앵커드 하이브리드

상태: Proposed
작성일: 2026-06-22

> CLAUDE.md "ADR 필요 조건" 중 ① 공유 core abstraction 추가(streaming diarizer provider) ② 실행 모델 변경(녹음 중 추가 실시간 추론 파이프라인)에 해당 → **구현 전 다중 관점 리뷰 필수**.

## Context

Minto는 "회의에 도움이 되는 정보를 실시간 제공"하는 라이브 미팅 어시스턴트를 지향한다. 그 일부로 녹음 **중** "누가 말하는지"를 보여줘야 한다.

현재 상태(검증된 사실):
- 라이브 녹음은 `ChannelSpeakerLabeler`로 **채널 기반 "나"(mic)/"상대"(system) 라벨만** 붙인다. 신경망 화자분리 없음.
- 파일 임포트(오프라인)는 FluidAudio **VBx**(community-1) + 보이스프린트(Phase 3)를 쓴다.
- 녹음 오디오는 이제 `RecordingAudioArchiver`로 **파일 저장됨**(사후 처리 가능).
- 2소스 캡처: `MicrophoneSource`(나) + `SystemAudioSource`(상대).

조사·연구로 좁혀진 제약(근거: `docs/reports/2026-06-22-analysis-realtime-diarization-design.html`, `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md`):
- **스트리밍은 오프라인보다 본질적으로 부정확**하고("offline↔streaming 격차가 ASR보다 크다"), **VBx는 온라인에 부적합**("온라인에 쓰면 성능 급락"). → 실시간만으로는 정확도를 크게 잃는다.
- 오프라인 정확도 우위 실측: VBx DER 12% vs LS-EEND 25.7%(AMI).
- **Target-Speaker VAD(2024 SOTA)** = 아는 화자를 닻으로 정확도를 올리는 기법. Minto는 닻을 둘 보유: ① "나" 마이크 채널(항상 아는 화자), ② 보이스프린트(등록 화자).
- M3 Pro: 동시 STT+diarization은 연산을 나누면 실현 가능(FluidAudio/speech-swift 사례), 단 **실측 미완**.
- 혼재 회의(원격+대면, 4명 초과 가능) → 엔진은 ≤4명 Sortformer보다 ≤10명 LS-EEND가 안전.

## Decision

**"앵커드 하이브리드(Anchored Hybrid)"** 채택. 4개 요소:

1. **라이브 패스(녹음 중, CPU)**: `LSEENDDiarizer`(≤10명)를 **CPU**에서 실행해 100ms 단위 임시 화자 라벨을 실시간 표시. STT는 ANE 유지 → 경합 회피.
2. **앵커링(정확도 핵심)**: "나" 마이크 채널은 알려진 화자로 고정(채널 prior/personal-VAD), 등록된 보이스프린트는 target-speaker로 추적. 맨바닥 분리 → 부분 지도 분리.
3. **최종 패스(저장 시)**: 아카이브 오디오에 **VBx**(authoritative)를 실행하고 앵커·예상인원으로 제약 → 라이브 임시 라벨을 최종 라벨로 **재조정(reconcile)**·실명.
4. **provider 추상화 분리**: `StreamingSpeakerDiarizationProvider`(라이브) ↔ 기존 offline provider. (이전부터 논의된 `any SpeakerDiarizationProvider` 디커플링 실현.)

경계 매핑: Infrastructure=Live/Offline DiarizationProvider, Application=`LiveSpeakerAssignmentUseCase`(바인딩·재조정·타이밍 소유), UI=라이브 라벨 표시, Domain=화자 라벨 모델(기존).

## Alternatives

- **순수 온라인(라이브 신경망만, 저장 시 재처리 없음)**: 단순하나 오프라인 정확도(VBx 12%)를 버림(LS-EEND 25.7%). 기각 — 정확도 목표와 충돌.
- **거친 라이브 + 오프라인만(채널 라벨 유지 + 저장 시 VBx)**: ANE 부담 0·구현 단순하나 대면 회의에서 전원 "나"로 표시 → "실시간 풍부한 정보" 미달. 기각(단 Phase 1 폴백으로 가치).
- **Sortformer 라이브**: 정체성 안정성 최고이나 **4명 상한**이 혼재 회의에 부족. 기각 — 단 향후 "라이브 화자 등록"엔 후보(enrollment 강점).
- **NME-SC 등 커스텀 클러스터링 자체 구현**: community-1 이탈 + affinity 파이프라인 신설(L비용). 기각 — VBx로 충분.
- **클라우드 diarization**: 정확도 높을 수 있으나 온디바이스·프라이버시 원칙 위반. 기각.

## Consequences

### Positive
- 실시간 화자 표시(요구 충족) + 저장 시 오프라인급 정확도(2-pass).
- **기존 자산 재활용**: 채널·보이스프린트(앵커), 오프라인 VBx(최종), exactSpeakerCount(레버).
- 외부 전송 없음 — 개인정보 범위 불변(전부 온디바이스).
- provider 디커플링으로 향후 엔진 교체(Sortformer 등) 용이.

### Negative
- **M3 Pro 동시 실행 성능 미검증** — RTFx·발열·배터리 실측 필요(최대 리스크).
- LS-EEND 라이브 정체성 불안정(라벨 흔들림) → UX 리스크.
- **재조정 복잡도** — 임시→확정 라벨 교체를 사용자 혼란 없이 보여주는 설계 필요.
- 스트리밍·오프라인 diarizer 추상화 2개 유지 비용.
- LS-EEND/Sortformer 모델 라이선스(NVIDIA Open Model License 등) 제품 도입 시 확인.
- LS-EEND를 CPU로 돌릴 때 정확도/속도가 ANE와 동일한지 미검증.

## Migration

- 기존 채널 라벨("나/상대") 흐름은 유지 → 라이브 신경망 라벨은 그 위에 얹거나 대체(설계 시 결정). 저장 schema는 기존 화자 라벨 구조 재사용(비호환 변경 없음 목표).
- 보이스프린트(Phase 3) 그대로 앵커로 연결. exactSpeakerCount 입력 UX는 파일 임포트 것 재사용.

## Rollback
- 라이브 신경망 패스는 feature flag로 끄면 기존 채널 라벨 동작으로 즉시 복귀(fail-soft).
- 최종 VBx 재조정 실패 시 라이브 임시 라벨을 그대로 저장(품질 저하하되 기능 유지).

## Verification
- **M3 Pro 실측(선행)**: STT+LS-EEND 동시 RTFx, 발열, 배터리; LS-EEND CPU 정확도. ← 수락 전 필수.
- 라이브: 채널 prior가 "나"를 정확히 고정하는지, 임시 라벨 안정성.
- 재조정: 임시↔최종 라벨 매핑 정확도(테스트 + 하이브리드 QA).
- benchmark: 앵커 유무에 따른 DER/화자수 정확도 비교(한국어 코퍼스, 단 참조 라벨 제약 인지).
- 로그: 라이브 diar 시작·성공·실패, 재조정 결과(화자수 변화), CPU/ANE 경합 지표.

## Follow-ups
- M3 Pro 실측 스파이크 → 결과로 본 ADR 수락/수정.
- 재조정 UX 설계(Pencil 검토 — 상태 변화 있는 화면).
- 크로스세션 보이스프린트 정확도 측정(앵커 신뢰성 토대).
- 다중 관점 리뷰(critic/architect) 통과 후 writing-plans로 구현 계획.
