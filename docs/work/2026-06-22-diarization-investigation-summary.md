# 화자분리 조사·설계 종합 (2026-06-22)

이 문서는 senko/pyannote 비교에서 시작해 실시간 화자분리 설계(ADR 0005)까지 이어진 조사의 **단일 진입점**이다. 각 단계의 결론과 상세 산출물을 링크한다. 브랜치 `feat/diarization-clustering`(워크트리 minto2-wt-diar-clustering, push·머지 보류).

## 출발 질문

"senko·pyannote와 우리 화자분리를 비교하고 개선 방향을 찾자" → 점점 좁혀져 "실시간 + 정확 + M3 Pro에서 도는 화자분리를 어떻게 구성하나"로 수렴.

## 조사 경로와 결론 (싼 가설부터 기각하며 좁힘)

| # | 질문 | 결론 | 근거/산출물 |
|---|------|------|------------|
| 1 | 우리는 어떤 모델? | **pyannote community-1**(powerset seg + WeSpeaker 256d + VBx) CoreML 변환본. senko도 seg 변환을 FluidAudio서 가져감 — 셋이 공유 계보 | 모델 메타데이터(`version: pyannote-speaker-diarization-community-1`), `docs/reports/2026-06-17-analysis-diarization-senko-pyannote-comparison.html` |
| 2 | CAM++가 더 좋나? | 검증 EER은 CAM++ 우위지만 드롭인 불가(192d vs 256d·PLDA 재구축)·EER≠DER·우리 임베딩 이미 충분 | (1과 동일 리포트) |
| 3 | 설정이 pyannote와 다른가? | **글자 그대로 동일**(threshold 0.6/Fa 0.07/Fb 0.8). 설정·알고리즘 우리 잘못 아님 | `docs/work/2026-06-20-diarization-counting-community1-native-vs-vbx-measurement.md` |
| 4 | 임베딩이 병목인가? | **아님** — 한국어 코퍼스 worst-pair margin 양수, 5people는 변별력 최상인데도 counting 실패 → 병목은 counting | `docs/work/2026-06-21-speaker-embedding-research-review.md` (VoiceprintFeasibilityTests) |
| 5 | 클러스터링 개선법? | VBx는 이미 양호(2/3 정답). cVBx(min/max)·NME-SC·EEND 검토. min/max UI는 한계효용 작아 보류 | `docs/work/2026-06-21-diarization-clustering-improvement-plan.md` |
| 6 | LS-EEND가 VBx보다 나은가? | count는 근접하나 **DER(AMI) VBx 12% vs LS-EEND 25.7%로 VBx 2배 우수**. LS-EEND는 스트리밍용 | `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md` (하니스 `LSEENDCountFeasibilityTests`, Codex+critic) |
| 7 | 실시간 화자분리를 어떻게? | **앵커드 하이브리드**(라이브 LS-EEND 임시 + 저장 시 VBx 확정 + 앵커) | `docs/reports/2026-06-22-analysis-realtime-diarization-design.html`, **ADR 0005** |

## 확정 결론

- **오프라인 경로(파일 임포트·회의 후 등록)**: **VBx + exactSpeakerCount(사용자 인원 입력)가 정답.** 모델·설정·임베딩·클러스터링 어느 것도 바꿀 근거 없음. 이미 구현됨.
- **실시간 경로(녹음 중)**: 미구현(현재 채널 "나/상대"만). 설계 = ADR 0005 **앵커드 하이브리드**. 상태 Proposed, **M3 Pro 스파이크 통과 전 수락 보류**.

## ADR 0005 설계 요지 (리뷰 반영본)

라이브 LS-EEND(CPU 임시 라벨) + 저장 시 VBx(authoritative 재조정) + "나"채널·보이스프린트 앵커. 연산: ANE=STT / CPU=diar / VBx=저장시. architect+critic 리뷰 반영:
- 동시성: `LiveSpeakerAssignmentUseCase`를 **전용 actor**로(LS-EEND가 동기·non-Sendable이라 @MainActor 직접 호출 금지).
- streaming/offline 프로토콜 **분리 유지**(인터페이스 간극 근본적).
- 앵커 **목적 2분리**: 라이브 UX 안정 vs 최종 정확도. 아카이브가 믹스 mono라 채널 소실 → "나"구간·보이스프린트를 **VBx 제약으로 전달**해야 최종에 기여.
- enrollSpeaker는 **세션 전 pre-enrollment만**(중간 호출 시 타임라인 리셋).
- "거친 라이브(채널)+저장시 VBx"를 **폴백 경로로 채택**, UseCase 인터페이스를 엔진교체 가능하게.
- 보이스프린트 앵커는 **Phase 3 이후**(현재 "나" 단일 앵커).

## 다음 게이트

**M3 Pro feasibility 스파이크**(별도 PoC 브랜치): STT+LS-EEND(.cpuOnly) 동시 RTFx>1.0·발열·CPU정확도. 통과 → ADR Accepted·구현(writing-plans). 미통과 → 폴백 경로.

## 미루는 트랙 (사용자 기록 요청)
- 트랙 B(오프라인 정확도 추가 향상): 한계효용 작음, 보류.
- 트랙 C(회의 간 화자 기억=보이스프린트 확장): 위 앵커와 직결. 크로스세션 정확도 측정이 선행.
