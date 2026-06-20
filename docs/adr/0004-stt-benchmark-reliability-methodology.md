# ADR 0004: STT 벤치마크 신뢰성 방법론 보강

상태: Proposed
작성일: 2026-06-18

## Context

Minto의 목표는 한국어 회의 녹음에서 **어느 STT 엔진/모델이 가장 좋은지 신뢰성 있게·반복 가능하게** 판정해 제품 채택 근거로 쓰는 것이다. 이를 위한 공식 벤치마크 프레임워크가 `experiment/official-stt-benchmark-framework` worktree에 있다.

Phase 0 신뢰성 진단(`docs/benchmark/2026-06-18-reliability-phase0-diagnosis.md`)에서, 프레임워크의 **절차적 게이트**(reference review, operator evidence, comparability)는 정교하지만 **"비교 결과를 믿을 수 있는가"의 통계적·방법론적 핵심이 비어 있음**을 확인했다. 설계 의도 조사 결과 이는 (c)혼재 — reference 검증만 의도적 설계이고, 나머지는 미완(반복측정·엔진 병렬비교는 "후속 phase 유보", phantom은 plan에 인식조차 없는 gap, 절대 임계 35%는 근거 없는 working default)이다. 즉 보강은 기존 설계 위반이 아니라 **미완 phase를 채우고 gap을 메우는** 작업이다.

도메인 제약(검증된 사실):
- SMI 자막 reference는 비verbatim → **절대 CER 무의미**(완벽 전사도 40~50% 바닥). 상대 비교만 유효.
- ANE 비결정성 → 같은 오디오·엔진도 런마다 CER ±8pp → **단일 측정 불신**.
- phantom(환각)이 CER을 *낮춰* 우열을 오도 → CER만으로 순위 매기면 환각 잘 하는 엔진이 이김.

현재 코드 상태(근거):
- decision gate(`run_stt_benchmark_decision_gate.py`): 단일 metric_summary 입력, 분산/CI 개념 없음. weighted_cer 절대 임계 35%(SMI 바닥 미달).
- regression gate(`run_stt_regression_gate.py`): delta 임계 2pp(ANE ±8pp 노이즈보다 작아 신호/노이즈 구분 불가).
- phantom 도구(`classify_stt_skip` in `run_whisper_empty_probe_matrix.py`)는 있으나 decision/regression/release 게이트에 미연결.
- engine bundle 선택(`run_stt_engine_run_bundle_workflow.py`): candidate 1개만 절대 임계 판정. 엔진 N개 병렬 비교 없음.
- engine_run_bundle_manifest 스키마(`validate_stt_benchmark_manifest.py`): 디코딩 파라미터 기록 필드 없음. comparability(`check_stt_engine_comparability.py`)도 파라미터 비교 안 함.

## Decision

벤치마크 신뢰성 방법론을 5개 축으로 보강한다. 핵심 전환은 **"절대 임계 합격/불합격" → "노이즈를 통제한 엔진 간 상대 비교 + 환각 차원 병행"**이다.

1. **반복 측정 / 분산 통제**: `metric_summary`에 `run_count`, `cer_std`, `cer_ci95`를 추가하고, 엔진을 N회(기본값은 ADR 리뷰에서 확정, 잠정 ≥3) 반복 실행한다. decision/regression 판정은 단일 수치가 아니라 **신뢰구간 기반**으로 한다. ANE 노이즈 floor를 반복 측정으로 추정해 regression 임계의 근거로 삼는다(고정 2pp 폐기).

2. **phantom 차원을 decision에 연결**: 기존 `classify_stt_skip`/비발화 프로브를 재사용해 `phantom_rate`(비발화 구간에서 텍스트를 생성한 비율)를 `metric_summary` 공식 필드로 승격한다. decision/regression이 CER과 **함께** phantom_rate를 본다 — CER이 낮아도 phantom_rate가 높으면 우위로 인정하지 않는다.

3. **엔진 병렬 비교**: candidate 1개 선택(`default_gate_input`) 구조에 더해, 동일 조건으로 실행된 엔진들을 **나란히 순위화**하는 비교 산출물(lane matrix 기반 ranking report)을 만든다. "누가 1등인가"에 답하는 출력.

4. **절대 임계 35% 폐기 → 상대 비교**: weighted_cer 절대 임계를 **품질 판정 기준에서 제거**한다(또는 SMI 바닥을 반영한 sanity 상한으로만 강등). 우열 판정은 엔진 간 상대 delta가 노이즈 CI를 넘는지로 한다. 6개 스크립트에 하드코딩된 0.35를 단일 출처로 모으고 의미를 재정의한다.

5. **디코딩 파라미터 기록(R6)**: `engine_run_bundle_manifest`에 각 엔진의 디코딩 파라미터(temperature, beam, no_speech_threshold, logprob_threshold, compression_ratio_threshold, condition_on_previous_text, vad, language 등 엔진별 해당 항목)를 기록하는 필드를 추가한다. **엔진 간 동일성을 강제하지 않는다**(엔진마다 최적·체계가 다름) — 대신 "어떤 값으로 돌았는지 투명하게 기록"하고, phantom 억제 파라미터 차이를 사후 검증 가능하게 한다.

구현은 Phase로 나눈다(우선순위: phantom > 상대비교/임계 > 반복측정 > 엔진 병렬 > R6은 재실행 전 선행). 각 Phase는 별도 작은 커밋 + 테스트.

## Alternatives

- **대안 A: 절대 임계 35% 유지** — 단순. 그러나 SMI 비verbatim 바닥(40~50%)보다 낮아 정상 전사도 통과 못 함 → 무의미. 기각.
- **대안 B: 단일 런 유지(반복측정 안 함)** — 비용 낮음. 그러나 ANE ±8pp 노이즈에서 2pp 차이를 신뢰할 수 없음 → "신뢰성 제일" 목표와 충돌. 기각.
- **대안 C: 엔진 파라미터를 comparability에서 동일성 강제** — "공정 비교"처럼 보임. 그러나 엔진마다 파라미터 체계가 달라(WhisperKit temperature ↔ sherpa 디코딩) 1:1 대응 불가, 동일성 강제는 무의미/불가능. 기록+투명성으로 대체. 기각.
- **대안 D: phantom 무시(CER만)** — 가장 단순. 그러나 과거 T7에서 환각이 CER을 낮춰 우열을 오도한 실증이 있음 → 환각 잘 하는 엔진이 이기는 구조. 기각.
- **대안 E: 수동 검토로 phantom·우열 커버** — 코드 변경 최소. 그러나 반복·다엔진 비교를 사람이 매번 하긴 비현실적이고 "반복 가능한 프레임워크" 목표와 충돌. reference 검증에 한해서만 수동 유지.

## Consequences

### Positive
- 우열 결론이 ANE 노이즈·phantom·SMI 바닥에 오염되지 않아 **신뢰성 있는 채택 근거**가 된다.
- "누가 1등인가"에 직접 답하는 출력(엔진 병렬 순위)이 생긴다.
- 파라미터 기록으로 **재현성**과 사후 공정성 검증이 가능해진다.

### Negative
- 반복 측정으로 **STT 실행 비용 N배**(엔진×N회). Phase 2 재실행 시간 증가.
- decision/regression/metric_summary 스키마 변경 → 기존 산출물·테스트 마이그레이션 필요(646 tests 영향).
- phantom_rate 정의·측정의 정확도 자체가 새로운 검증 대상(비발화 구간 ground truth 필요).

## Migration
- `metric_summary` 스키마에 신규 필드는 **optional + 기본값**으로 추가해 기존 산출물 읽기 호환 유지. 신규 실행만 채움.
- 절대 임계 35%는 즉시 제거하지 않고 **deprecate(sanity 상한으로 강등) → 상대 비교 안정화 후 제거**의 2단계.
- 기존 646 tests는 스키마 optional化로 대부분 유지, 신규 동작은 테스트 추가.

## Rollback
- 각 Phase가 독립 커밋이라 항목별 revert 가능.
- 스키마 신규 필드가 optional이라, 보강 로직을 끄면 기존 단일-런 절대-임계 경로로 복귀 가능(임시).

## Verification
- 테스트: 각 Phase 회귀 테스트 + 전체 `PYTHONPATH=scripts python3 -m pytest Tests/`(현 646 유지·증가).
- benchmark: 동일 엔진을 N회 돌려 cer_std가 알려진 ANE ±8pp 범위와 일치하는지(반복측정 정합성 검증).
- phantom: 비발화 프로브 샘플에서 phantom_rate가 과거 측정(T8 등)과 모순되지 않는지.
- 상대 비교: 의도적으로 열등한 설정의 엔진을 넣었을 때 순위가 올바른지(sanity).
- 관측: decision report에 CI·phantom_rate·순위가 사람이 읽을 수 있게 출력되는지.

## 리뷰 반영 (2026-06-18, critic + Codex 크로스모델)

다중 관점 리뷰(critic=설계, Codex=구현가능성)로 초안의 결함이 드러나 다음을 확정·수정한다.

### 확정된 결정 변경
- **절대 임계: 완전 폐기 → sanity 상한 "유지"로 확정**(critic Critical 1). 상대 비교만 두면 "모든 엔진이 나쁜"(예: CER 80% vs 82%) 경우를 못 거른다. SMI 바닥(40~50%)은 *reference* 문제지 *엔진이 실제 나쁜* 경우를 안 덮는다. 절대값은 "우열 판정 기준"에서 빼되 "이 아래여야 후보 자격"인 sanity 상한으로 남긴다.
- **우선순위 재배치**(critic Major 2 + Codex): phantom을 1순위로 둔 것은 오류. phantom_rate도 ANE 비결정성을 타면 단일 측정은 CER 단일측정과 같은 함정 → **반복측정이 CER·phantom 공통 토대**라 먼저다. 또한 phantom은 데이터 인프라 선행이라 가장 늦다.
- **phantom 억제 파라미터는 정렬**(critic Major 3): R6에서 일반 파라미터는 엔진별 자유(기록만)지만, `no_speech_threshold`/`logprob_threshold` 등 phantom 억제 파라미터는 의미적 등가물끼리 정렬 시도한다. 안 그러면 phantom_rate가 엔진 차이가 아닌 파라미터 차이를 측정한다.
- **phantom_rate는 "classify_stt_skip 재사용"으로 안 됨**(critic Critical 2 + Codex): 그 도구는 phantom의 *반대*(empty count) 개념이고, 비발화 ground-truth 레이블 데이터가 **아예 없다**. phantom_rate는 코드가 아니라 **데이터 수집·레이블링 작업이 선행**이다. operational definition(비발화 구간을 무엇으로 정의·검증)을 데이터 작업 시작 전 확정한다.
- **0.35 이중 의미 분리**(Codex): 0.35가 *판정 기준*과 *진단 샘플링 기준* 두 용도로 혼재 → 구분 없이 교체하면 진단 로직이 깨진다. 두 사용처를 먼저 문서화·분리한 뒤 판정 쪽만 손댄다.

### 확정된 구현 순서 (Codex 의존성 분석 기준)
1. **항목5 디코딩 파라미터 기록** — optional 필드, 테스트 영향 최소, 의존 없음. STT 재실행 전 선행.
2. **항목3 엔진 병렬 랭킹** — lane matrix 위 독립 출력. decision 로직 미변경.
3. **항목4 절대임계→상대비교+sanity 상한** — 0.35 두 의미 분리 후. 테스트 재작성 규모 큼, 별도 브랜치.
4. **항목1 반복측정/분산** — 실행 루프(1회 순회) 자체를 N회로 개조 + 재실행 정책. 항목4 안정 후 CI 판정 얹음.
5. **항목2 phantom_rate** — 비발화 ground-truth 데이터 수집·레이블링 선행. 반복측정 위에 얹음. 가장 마지막.

## 구현 현황 (2026-06-18)

⚠️ codex가 위임 범위(항목①만)를 벗어나 항목①~⑤를 **manifest 스키마 레벨로 한꺼번에** 커밋함(8ce9e6e..3b47328, 6커밋, 676 tests 통과). 검토 결과 전부 **optional 필드 + 타입 검증만**이고 미확정 결정을 강제하지 않아 보존하기로 결정.

**완료(스키마 예약만, 판정 로직 미연결)**:
- `decoding_parameters`(dict, `KNOWN_DECODING_PARAMETER_KEYS` 주석) — `1dc32b7`
- `baseline_cer`, `relative_improvement{cer_improvement_rate, baseline_engine_id}` — `5e89963`, `3b47328`
- `phantom_rate`(ratio) — `9615574` ※ 빈 필드. 채움은 ground-truth 데이터 선행(미정)
- `engine_ranking[{rank, engine_id, weighted_cer}]` — `3e4a360` ※ phantom 차원 누락
- `repeat_index`, `repeat_count`(>=1) — `068d670`

**진행 중/완료 본체**:
- ✅ **항목④ 4a+4b 완료** (`bfbc245`+`5123267`+`ddb4182`, 681 tests): 절대 35% 임계를 우열 판정에서 제거 → sanity 상한 0.70(`--sanity-cer-cap`)으로 강등 + 35% 판정/진단 두 의미 분리(진단용 0.35 보존) + deprecated alias 우선순위. critic Critical 1("모두 나쁜 안전망") 해결. 우열은 regression gate(상대 delta) 담당.
- ✅ **항목③ engine_ranking 생성 완료** (`727695d`+`26a4ac0`, 684 tests): `build_stt_engine_lane_matrix.py`가 lanes를 weighted_cer 오름차순 순위화해 `engine_ranking` 출력("어느 엔진이 1등인가"). 엔진별 최저 cer dedup(엔진 단위 보장)·None/빈 engine_id 제외·동률 정렬. phantom 차원과 lane별 분리는 데이터 확인 후(② 이후). decision 판정 미연결(독립 출력).

**남은 본체(스키마 ≠ 동작)**:
- decision/regression 게이트가 phantom_rate·relative_improvement·engine_ranking을 **판정에 사용**하도록 연결 (현재 미사용)
- 항목④ 4c~4e: relative_improvement/baseline_cer 채움 + decision 상대 delta 판정 — **baseline 엔진 결정(D2) + 반복측정(⑤) 의존**
- 반복측정 실행 루프(1회→N회) + N 역산(D-N)
- phantom ground-truth 데이터 확보(D-phantom-data) → phantom_rate 채움 → ranking에 phantom 차원 추가
- 항목① decoding_parameters 채움: 엔진 전사(Swift 등)가 파라미터를 산출물에 노출하도록 보강 선결(현재 미노출)

### Codex가 짚은 구현 리스크 (구현 시 주의)
- `validate_stt_benchmark_manifest.py` 14,000줄 — unknown 필드 거부 로직 위치 파악 후 필드 추가.
- 3단 gate(decision→regression→release) fixture 연쇄 — 중간 출력 변경이 하위 테스트 연쇄 파괴 가능.

## 남은 결정 (사용자 입력 필요)
- **D-N**: 반복측정 목표 CI 너비(예: ±2pp) → N 역산. (N을 임의 고정하지 않고 목표 정밀도에서 계산. ±8pp 자체로 검증하면 순환논증이라, 첫 N회 실측으로 floor를 재추정.)
- **D-sanity**: sanity 상한 값의 산출 방법(예: 관측된 정상 전사 최악 CER + 여유분).
- **D-phantom-data**: phantom_rate용 비발화 ground-truth를 어떻게 확보할지(기존 7개 샘플에 비발화 구간 수동 레이블 vs 합성 비발화 클립). 비용 큼.
- **D-착수범위**: 즉시 가능한 1~2단계(파라미터 기록·랭킹)부터 시작할지, phantom 데이터 작업을 병행 착수할지.
