# LS-EEND vs VBx — 자동 화자수 추정 비교 측정 (설계)

작성 2026-06-21, 실행 2026-06-22. 브랜치 `feat/diarization-clustering`. 상태: **실행 완료 → 결과 `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md`** (요약: LS-EEND가 count는 근접하나 **DER proxy(AMI)에서 VBx 12% vs LS-EEND 25.7%로 VBx 2배 우수 → H1 기각**. LS-EEND는 스트리밍용, 오프라인 정확도는 VBx. 오프라인 경로 교체 안 함). 분류: benchmark/measurement.

## 질문

community-1 VBx의 자동 화자수 추정이 우리 병목인데(Phase 2), **클러스터링을 우회하는 EEND(LS-EEND)가 같은 한국어 코퍼스에서 화자수를 더 정확히 맞추는가?**

- 맞추면 → provider 디커플링과 함께 LS-EEND 자동 경로 도입을 ADR로 검토.
- 못 맞추면 → VBx + exactSpeakerCount 체제 확정.

## 대상 (FluidAudio 0.15.2, 검증된 API)

- **LS-EEND**: `LSEENDDiarizer(variant: .dihard3)` → `processComplete(...)`(완전버퍼). 클러스터링 없음, neural attractor가 화자수 직접 추론, **최대 10명**. (`Sources/FluidAudio/Diarizer/LS-EEND/LSEENDDiarizer.swift`)
- **VBx**(현행): `FluidAudioOfflineDiarizationProvider()` 자동(무인자).

## 코퍼스 (정답 화자수 알려진 것 우선)

- `sample/toron-4/4people.wav` (4명) — diar-eval 워크트리
- `sample/toron-4/5people.wav` (5~6명)
- (옵션) `sample/meeting/raw/*.wav` 국회 회의 — 단 **10명 초과 가능 → LS-EEND 상한 포화 예상**, 보조 참고만

## 방법

각 파일에 대해 A(VBx 자동) · B(LS-EEND) 예측 화자수를 산출해 정답과 비교.

**실행 옵션 (싼 것부터)**:
1. ~~**FluidAudio CLI** (`fluidaudiocli lseend <wav> --variant <ami|dihard3|...>`)~~ — **❌ 막힘(2026-06-21)**: `fluidaudiocli` 타겟이 무관한 ASR 파일(`NemotronMultilingualFleursBenchmark.swift:790`, 거대 문자열 `+` → 타입체크 타임아웃)에서 컴파일 실패. Swift가 타겟 전체를 컴파일하므로 lseend도 빌드 불가. FluidAudio **라이브러리**는 정상(우리 의존성). 의존성 소스 임시수정은 fragile → 채택 안 함.
2. **Swift 측정 하니스 (채택)** — 우리 테스트 타겟에 `LSEENDDiarizer(variant:.ami/.dihard3)` 로드 → `processComplete(samples)` → `timeline.speakers` 중 세그먼트 보유 화자 수 집계. `VoiceprintFeasibilityTests` 패턴 재사용(WAV 로드·env 게이트). **코드 작성 = Codex 위임**, 측정 실행·분석 = 메인 세션.

VBx 쪽은 기존 `VoiceprintFeasibilityTests`/`DiarizationEvalRunnerTests` 경로 재사용(자동 모드, exactN 미지정).

## 지표

1. **예측 화자수 vs 정답**(핵심): 파일별 |예측−정답|, A vs B 나란히.
2. 방향성: 과분할/under-count.
3. (참조 RTTM 있으면) DER. 한국어 코퍼스는 정밀 정답 없을 수 있어 count 정확도 중심.

## 결정 규칙

- LS-EEND가 ≤10명 회의에서 VBx보다 count를 유의하게 정확히 → **H1**: EEND 경로 도입 검토(provider 디커플링 + ADR: 온디바이스 비용·겹침 이점 vs community-1 일관성 상실).
- 비슷하거나 LS-EEND가 못함(특히 한국어 OOD로 약할 수 있음) → **H0**: VBx + exactSpeakerCount 확정.

## 리스크 / 한계

- **LS-EEND는 dihard3 학습 + 온라인 지향** — 한국어 OOD(모든 모델 공통), 긴 파일 complete-buffer 동작 확인 필요.
- **10명 상한** — 국회 회의(대규모)는 포화. 소규모 토론(4·5명)이 주 비교 대상.
- 모델 라이선스(LS-EEND/Sortformer NVIDIA Open Model License 등) 확인 — 제품 도입 시 영향.
- 측정 자체는 코드 통합 불필요(CLI 우선) → 측정=메인 세션 직접. 제품 도입(provider 통합)은 측정 후 별도 결정.

## 산출물

- 결과: `docs/benchmark/2026-06-21-lseend-vs-vbx-count.md`
- 결론 따라 ADR(provider 디커플링 + EEND 경로) 또는 VBx 체제 확정 메모.
