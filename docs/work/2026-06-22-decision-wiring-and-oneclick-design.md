# 설계: decision 채택 판정 배선 + 원클릭 재실행 세팅

작성: 2026-06-22. ADR: `docs/adr/0004`. 이 문서는 **설계(합의용)**이며 구현 전 단계.

## 목표
1. **A. decision 채택 판정 배선**: "확실히 우수한 후보만 제품 엔진 교체 권장"(`is_significant_improvement`, CI 비겹침)을 decision/regression 게이트에 연결.
2. **B. 원클릭 재실행 세팅**: "새 모델 넣으면 한 명령으로 측정→비교→판정→리포트"가 되도록 통합 진입점 신설.

## 현재 상태 (조사 결과)
- 채택(`default_allowed`)은 `run_stt_benchmark_decision_gate.py`에서 `product_path=true` + `regression_report_blocker` 통과로 결정(line 191, 222-227).
- regression gate(`run_stt_regression_gate.py`)는 candidate vs baseline weighted_cer delta ≤ **2pp 고정**. `is_significant_improvement`(CI 기반)는 미사용.
- verdict(순위/무승부)는 lane matrix까지 연결됨(`f8a89c5`). decision은 ranking/verdict 미사용.
- `run_stt_official_release_workflow.py`는 **엔진 실행 안 함** — preflight/decision/regression *report*와 run-bundle-manifest를 받아 게이트 조립만. 엔진 전사는 `run_meeting_stt_pipeline.py`(별도).
- 통합 원클릭(데이터→엔진실행→비교→게이트) 래퍼 **없음**.

## A. decision 채택 판정 배선

### 설계
- regression/decision 판정에 `stt_engine_verdict.is_significant_improvement(candidate, baseline)` 도입: **candidate CI 상단 < baseline CI 하단일 때만** "확실히 우수"(교체 권장).
- 2pp 고정 임계 → **CI 기반으로 교체/보완**. CI 없으면(단일 런) 보수적 — 교체하지 않고 현 default 유지.
- baseline = 현 제품 엔진(product_path 엔진). candidate = 신규 후보.

### 흐름 (확정): regression gate=신호 생성, decision=채택
regression gate는 "악화 감지", 사용자 채택 규칙은 "개선 확실"이라 방향이 다르다. 둘을 분리:
- **regression gate**: candidate/baseline의 `cer_ci95_half_width`로 `improvement_signal` 산출 —
  `significant_improvement`(candidate CI 상단 < baseline CI 하단) / `significant_regression`(반대) / `tie`(겹침). CI 없으면 기존 2pp 기반 `regression_state`로 fallback(D-a2). report에 필드 추가.
- **decision gate**: regression report의 `improvement_signal`이 `significant_improvement`일 때만 채택(default_allowed). `tie`/`regression`이면 현 default 유지(교체 안 함, 사용자 "확실히 나을 때만"). CI 없으면 기존 regression `passed`로 fallback.
- `is_significant_improvement(candidate, baseline)`=개선확실, `(baseline, candidate)`=악화확실 — 같은 함수 양방향 재사용.

### 결정 필요 (해소됨)
- ~~D-a1~~: regression gate가 신호 생성, decision이 채택 — 둘 다 배선(위 흐름).
- **D-a2**: 2pp 고정을 **완전 대체**(CI만) vs **CI 우선 + CI 없으면 2pp fallback**.
- **D-a3**: baseline 엔진 지정 — product_path=true 자동 식별 vs `--baseline-engine` 명시.

## B. 원클릭 재실행 세팅

### 설계
통합 오케스트레이터 신설(예: `scripts/run_stt_official_benchmark.py`):
- **입력**(환경변수/인자): 엔진 목록, reference 버전, N(repeats), 출력 루트(`MINTO2_STT_OUTPUT_ROOT`).
- **단계**: (0)reference 확인 → (1)엔진별 **N회** 전사(`run_meeting_stt_pipeline`) → (2)번들(`convert_*`) → (3)lane matrix(순위/무승부) → (4)regression/decision → (5)release workflow → (6)리포트.
- **반복측정 CI**: (1)에서 N회 → `stt_repeat_statistics`로 cer_mean/cer_std/cer_ci95 집계 → metric에 기록 → A의 CI 판정에 공급.
- 새 모델 추가 = 엔진 목록에 한 줄 + (필요시 엔진 러너 어댑터).

### 결정 필요
- **D-b1**: 진입점 형태 — `.sh` wrapper(기존 스크립트 호출) vs `.py` 오케스트레이터(견고).
- **D-b2**: 멱등성 — 재실행 시 기존 산출물 skip(재개) vs 전체 재실행.
- **D-b3**: N(repeats) 기본값 — critic 경고대로 목표 CI에서 역산하되, 잠정 기본값 필요.

## 확정된 결정 (2026-06-22)
- **D-a2**: CI 우선 + 없으면 2pp fallback (반복측정 전 호환, 후 신뢰성 격상).
- **D-a3**: product_path 엔진 자동 baseline.
- D-a1: regression gate에 배선. D-b1: `.py` 오케스트레이터. D-b2: 기존 산출물 skip(재개). D-b3: N 잠정 5(후속 역산).

## 의존성·권장 순서
A(CI 기반 채택)는 CI가 있어야 작동하고, CI는 B의 "N회 반복 실행"에서 나온다. 따라서:
1. **B-반복실행**: `run_meeting_stt_pipeline`을 N회 돌려 `stt_repeat_statistics`로 CI 집계 → metric에 기록 (실측은 사용자 환경, 코드 구조는 지금 가능)
2. **A-채택 판정**: 그 CI로 `is_significant_improvement`를 게이트에 배선 (fixture로 검증 가능)
3. **B-통합 래퍼**: 전체 단계를 한 진입점으로 묶음

→ 코드/fixture로 가능한 것: B-반복실행 루프, A-배선, B-통합 래퍼 골격. 실제 우열 수치는 실측(N회 엔진 구동) 후.

## 검증 (설계 확정 후)
- A: fixture로 "후보가 baseline보다 CI 비겹침이면 교체 권장, 겹치면 유지" 통합 테스트.
- B: 작은 fixture/dry-run으로 단계 연결 e2e(엔진 실제 구동 없이 산출물 흐름).
