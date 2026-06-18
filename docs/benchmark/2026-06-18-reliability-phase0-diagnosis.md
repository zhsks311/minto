# Phase 0 — 신뢰성 전제 진단 리포트

작성: 2026-06-18 KST. 계획: `docs/work/2026-06-18-official-stt-benchmark-reliability-followup-plan.md`

## 한 줄 결론

**"지금 비교를 돌리면 결과를 믿을 수 있는가" → 아니오.** (1) 확정된 비교 수치가 아직 없고(STT 재실행 필요), (2) 엔진별 디코딩 파라미터가 기록·비교되지 않아 공정성이 보장되지 않으며(R6), (3) 도메인 특성상 단일 측정·절대 CER로는 우열 판정 자체가 신뢰성이 없다(R5). 단, timing shift(R2)는 무해로 확인됨.

## R1~R6 판정 종합

| 위험 | 판정 | 근거 (요지) |
|---|---|---|
| R1 reference 사람검증 | 부분 실재 (무해 전환·취약점 잔존) | applied manifest 7개 `reviewer=d66hjkxwt9` reviewed. 단 audit evidence는 answer sheet CSV note뿐이고, 검증 코드(`check_stt_reference_review_decisions.py:247-250`, `apply_stt_reference_review.py:134-135`)는 reviewer 비어있음만 확인 → 자동값(`regenerated-manifest`)도 통과하는 구조 취약점 |
| R2 timing shift → CER | **무해** | CER 채점이 순수 텍스트 정렬. timestamp는 오디오 크롭 범위만 결정. global CER은 전 window를 joined해 1회 levenshtein → drift 흡수 설계(`MeetingCorpusTests.swift:121-123,143,187-188`). 모든 엔진 동일 구간·동일 ref → 공정 |
| R3 버전 불일치 | 실재 (프레임워크 자가 차단 중) | preflight=official-reference-draft, decision/regression=seed-smi. 게이트 `release_reference_version_mismatch` 차단. 복구 = STT 5엔진 재실행 필요 |
| R4 comparability | R6에 흡수 | comparability 검사가 파라미터를 비교 안 함(아래) |
| R5 샘플/측정안정성/phantom | **강하게 실재** | SMI 자막 비verbatim(완벽 전사도 CER ~40-50% 바닥) → 절대 CER 무의미. ANE 비결정성 ±8pp → 단일 측정 불신. phantom(환각)이 CER을 *낮춰* 오도(과거 T7). 7개 전부 국회 회의 → Minto 실사용 대표성 약함 (출처: `project_pending_tasks` 메모리·검증된 도메인 지식) |
| R6 파라미터 공정성·기록 | **실재** | 디코딩 파라미터(temperature, beam, no_speech_threshold, logprob_threshold, compression_ratio_threshold, condition_on_previous_text, vad)가 manifest 스키마(`validate_stt_benchmark_manifest.py:698-742`)·comparability 검사(`check_stt_engine_comparability.py:9-13` COMPARABLE_FIELDS) 둘 다에 없음. runner_contract는 `{source, product_path}`뿐. → 엔진마다 임의 파라미터로 돌아도 게이트 통과, phantom 억제 유리 설정 사후검증 불가 |

추가 발견:
- **파이프라인 incomplete**: decision/regression/engine bundle 디렉토리 비어 있음. `operator_evidence_accepted=0`, `decision_state=experimental_flag_only`. **확정 STT 비교 수치가 존재하지 않음.**
- **runner_contract 문자열 비교 역방향 위험**: `comparable_value()`가 JSON 직렬화 문자열 동등 비교(`check_stt_engine_comparability.py:54-56`) → 의미 없는 문자열 차이로 동등한 실행이 false incompatible 차단될 수 있음.

## 비교 방법론 감사 (R5 심화) — 가장 중대한 발견

프레임워크가 "신뢰성 있는 우열 판정"의 통계적/방법론적 핵심을 **코드 자동 게이트에 갖추지 않음**:

| 안전장치 | 현황 | 근거 |
|---|---|---|
| 반복 측정/분산 통제 | 없음 (단일 런) | `run_stt_benchmark_decision_gate.py:9-22` 입력 단일 metric_summary. `metric_summary` 스키마에 std/ci/run_count 없음. regression 임계 2pp(`run_stt_regression_gate.py:57-65`)는 ANE ±8pp 노이즈 floor 아닌 임의값 |
| phantom 탐지 | decision 완전 단절 | `classify_stt_skip`(`run_whisper_empty_probe_matrix.py:289-298`) 존재하나 decision/regression/release 게이트에 phantom/hallucin/non_speech 키워드 0건. empty_final_count는 phantom 반대 개념 |
| 엔진 나란히 비교 | 없음 | `run_stt_engine_run_bundle_workflow.py:70-89`이 candidate 1개(`default_gate_input=True`)만 단독 decision 투입. 병렬 CER 비교 부재 |
| 절대 임계 35% | SMI 바닥 미고려 | `run_stt_benchmark_decision_gate.py:21,125-132` weighted_cer_threshold=35%. SMI 비verbatim 바닥 40-50%보다 낮아 비현실 |
| 메트릭 다양성 | CER 단일 | `build_decision()` 품질 기준은 weighted_cer뿐. macro_cer는 스키마에 있으나 미사용 |

**구조적 함의**: 현 프레임워크는 "이 엔진이 절대 기준을 넘는가(합격/불합격)"를 묻도록 설계됨. 목표("엔진들 중 누가 1등인가")와 어긋난다.

**한계(R5 에이전트 명시)**: `manual_review_manifest`의 수동 검토 기준은 미확인. phantom·우열을 사람이 수동으로 보는 운영 관행이 있으면 코드만으론 안 보임 → "의도(수동 커버) vs 미완" 확인 필요.

## 결정 영향

- **D1 (버전)**: `official-reference-draft-2026-06-12` 권장. applied manifest가 이미 사람(d66hjkxwt9) reviewed로 완성. seed-smi로 되돌리면 사람 검증을 다시 해야 함.
- **D2 (timing)**: R2 무해 판정 → **보정 불필요, 그대로 사용**(note로만 기록). 결정 종료.
- **D4 (파라미터 정책)**: R6 실재 → **STT 재실행 전에 파라미터 정책 확정 + manifest 기록 메커니즘 추가가 필수.** 안 하면 재실행 결과가 불공정·비재현. (a)기본값 vs (b)product_path 실사용 vs (c)엔진별 튜닝 중 택1, 전 엔진 동일 정책.

## 신뢰성을 세우기 위한 선행 작업 (Phase 1·2 사이 삽입)

순수 STT 재실행만으로는 신뢰성이 안 선다. 재실행 *전에*:

1. **R6 해소 (코드)**: engine_run_bundle_manifest 스키마에 디코딩 파라미터 기록 필드 추가 + comparability 검사에 포함(또는 최소한 파라미터를 명시 고정·기록). phantom 억제 파라미터를 엔진 간 정렬.
2. **R5 대응 (설계 확인)**: 비교가 (a) 반복 측정으로 ANE 분산을 통제하는가 (b) phantom 비발화 프로브를 병행하는가 (c) 절대값이 아닌 상대 비교인가 — release workflow가 이를 강제하는지 확인, 없으면 추가.
3. **R1 강화 (선택)**: 검증 코드가 자동값 reviewer를 거부하도록 + 사람 검증 evidence를 audit 가능하게.

## 무해로 확인되어 작업 불필요

- R2(timing shift 보정): 불필요. 텍스트 정렬이라 우열 비교에 영향 없음.
