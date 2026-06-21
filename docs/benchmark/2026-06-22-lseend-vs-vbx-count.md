# LS-EEND vs VBx — 자동 화자수 추정 비교 결과

측정 2026-06-22. 브랜치 `feat/diarization-clustering`. 설계: `docs/work/2026-06-21-lseend-vs-vbx-count-measurement.md`.

## 방법

- 하니스: `Tests/MintoTests/LSEENDCountFeasibilityTests.swift`(LS-EEND, Codex 구현) + `DiarizationEvalRunnerTests.swift`(VBx 자동).
- LS-EEND: `LSEENDDiarizer(variant:).processComplete()`, 검출 화자 = finalizedSegments 보유 distinct 화자.
- VBx: `FluidAudioOfflineDiarizationProvider()` 자동(exactN·min/max 미지정).
- 코퍼스: 한국어 토론 4people.wav(정답 4), 5people.wav(정답 5~6).

## 결과 (검출 화자 수)

| 파일 | 정답 | VBx 자동 | LS-EEND ami | LS-EEND dihard3 |
|------|------|----------|-------------|-----------------|
| 4people | 4 | 2 | 2 | **3** |
| 5people | 5~6 | 2 | **4** | 3 |

(참고 totalSegments: LS-EEND dihard3가 ami보다 훨씬 많음 — 4people 688 vs, 5people 1196 vs ami 267. dihard3가 더 잘게 쪼갬. 세그먼트 수는 품질 지표 아님.)

## 해석

- **VBx 자동은 두 파일 모두 2로 붕괴** — Phase 2 재확인(기본 파라미터 under-count).
- **LS-EEND가 일관되게 VBx보다 정답에 근접**(3~4 vs 2). 클러스터링 우회 EEND가 counting 병목을 실제 완화.
- **그러나 정확히는 못 맞춤**(전부 under-count) + **최적 variant가 파일 의존**(ami=5people 유리, dihard3=4people 유리). VBx의 Fa 불안정과 동형의 "레버가 녹음 의존" 문제.

## DER proxy (2026-06-22 추가) — count 결과를 뒤집음

**우리 한국어 코퍼스는 참조 RTTM이 없어 DER 측정 불가**(4people/5people 폴더에 .wav만 존재). 대신 FluidAudio 공개 AMI subset 벤치마크(영어, 정답 있음, `Documentation/Diarization/BenchmarkAMISubset.md`):

| System | Avg DER | Mode |
|--------|---------|------|
| **Offline VBx** | **12.0%** | Offline |
| LS-EEND (AMI) | 25.7% | Streaming |
| Sortformer | 34.3% | Streaming |

VBx는 full 16-meeting AMI SDM에서 10.62% DER, **12/16 화자수 정답**.

→ **DER에선 VBx가 LS-EEND보다 2배 우수.** LS-EEND는 스트리밍(온라인) 모델이라 지연 최소화를 위해 정확도를 희생한다. 화자수를 더 세도(우리 count 결과) 구간 배정이 부정확하면 DER이 나쁘다. AMI(영어) proxy지만 2배 격차는 한국어 도메인 차이로 뒤집힐 수준이 아니다.

## 결론 (수정 — H1 기각)

- **count-근접은 미끼**였다. 홀리스틱 품질(DER)에선 VBx가 LS-EEND를 2배 앞선다.
- LS-EEND의 가치는 **스트리밍/저지연(라이브)**이지 오프라인 정확도가 아니다. 우리 파일 임포트는 **오프라인 배치(지연 압박 없음)** → VBx가 맞다.
- **권고: 오프라인 경로를 LS-EEND로 바꾸지 않는다**(품질 악화 위험). VBx 유지 + 자동 counting 한계는 **exactSpeakerCount(사용자 인원 입력)**로 우회 — 이미 구현·검증됨.
- (LS-EEND는 향후 **라이브 화자분리**가 제품 과제가 될 때 재검토 대상. 그때는 지연 이점이 살아난다.)

## 한계 / 다음

- **count만 측정, DER 미측정** — LS-EEND가 4명을 "검출"해도 배정 품질(DER)은 별개. 도입 결정 전 DER 측정 필요.
- 소표본(2파일)·토론 음질·intra-recording. 국회 회의(>10명)는 LS-EEND 10명 상한 포화 예상 — 별도 확인.
- LS-EEND는 온라인 지향·dihard/ami 학습(한국어 OOD)·variant 선택이 새 튜닝 변수.
- **다음 결정 포인트**: (1) DER 측정으로 품질 확인 → (2) 우수하면 provider 디커플링(`any SpeakerDiarizationProvider`) + LS-EEND 자동 경로 ADR. 못하면 VBx+exactSpeakerCount 확정.

## 산출물
- 하니스: `Tests/MintoTests/LSEENDCountFeasibilityTests.swift`
- 재현: `RUN_LSEEND_POC=1 DIARIZATION_EVAL_WAV=<wav> LSEEND_VARIANT=<ami|dihard3> swift test --disable-sandbox --scratch-path /tmp/minto2-diar-clustering --filter LSEENDCountFeasibility`
