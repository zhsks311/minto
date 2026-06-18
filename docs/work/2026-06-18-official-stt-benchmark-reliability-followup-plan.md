# 공식 STT 벤치마크 — 신뢰성 우선 후속 계획

작성: 2026-06-18 KST

## 1. 진짜 목표

Minto(회의 기록 앱)에 **어떤 STT 엔진/모델을 채택할지**를, 한국어 실제 회의 녹음에서 **신뢰성 있게·반복 가능하게** 비교해 결정한다. 새 모델이 나올 때마다 같은 절차로 재현할 수 있어야 한다.

대상 엔진(현재 release workflow 슬롯 기준): whisper_accurate(offline final), speech_analyzer(offline final), sf_speech_on_device(offline final), nemotron(sidecar final), sherpa(true streaming), product_path(whisper_accurate / speech_analyzer / sf_speech_on_device).

## 2. 최우선 가치

> **신뢰성 > 속도.** 엔진 우열을 빨리 보는 것보다, 비교가 공정·재현 가능·검증된 상태에서 결과를 내는 것이 우선이다.

이 가치가 계획 순서를 결정한다: "STT 재실행으로 숫자부터 내기"가 아니라 **"비교가 왜 신뢰할 만한지를 먼저 세운다"**.

## 3. 현재 상태 (2026-06-17 세션 종료 시점)

worktree: `minto2-official-stt-benchmark-framework` (branch `experiment/official-stt-benchmark-framework`, HEAD `8ce9e6e`, 646 tests passing)

달성:
- reference review gate 통과: 7개 reviewed(gold=본회의_20260423), `eligible_for_default_gate: True`.
- operator-evidence fill 단계 코드 드리프트 버그 2건 수정(`3fc1412`, `04a5720`).
- 공식화: timing shift warning(`5843c4c`), review_helper.py → `scripts/run_stt_reference_review_answer_sheet.py` 정식 승격(`44b9a9f`, `8ce9e6e`), /tmp→env var(작업팩 파일).

막힌 곳(정상 중단):
- `run_after_human_review.sh`가 ②batch → submission status regen → ③fill 까지 통과 후, ④ preflight resume에서 `official_comparison_preflight_workflow_report.json` 부재로 멈춤. 이 파일은 STT 엔진 비교를 실제 실행해야 생성된다.

## 4. 신뢰성을 깨뜨릴 수 있는 위험 요소

후속 비교 결과를 믿으려면 아래가 먼저 해소돼야 한다. 각 항목은 Phase 0에서 진단한다.

| # | 위험 | 신뢰성에 미치는 영향 | 확인 방법 |
|---|---|---|---|
| R1 | reference가 사람 검증이 아닌 자동값(`reviewer=regenerated-manifest`)일 수 있음. 코드(`build_stt_reference_manifest.py:93-97`)가 reviewer 문자열 존재만 확인하고 내용 무검증 | 기준 자체가 안 믿기면 모든 비교가 무의미 | manifest의 reviewer/reviewed_at 실제 값 + answer sheet 사람 판단과의 연결 추적 |
| R2 | 7개 전부 timing shift("N초 밀림") | reference와 STT 출력의 시간 정렬 오차가 CER을 오염 → 우열 판정 왜곡 | shift 크기 분포 + CER 채점이 시간정렬을 어떻게 다루는지(텍스트 정렬 vs 시간 정렬) 코드 확인 |
| R3 | 버전 불일치: reference=`official-reference-draft-2026-06-12`, 기존 decision/regression/engine=`seed-smi-2026-06-12` | 다른 기준으로 잰 비교는 무효(신뢰성 최소 전제 위반) | 각 산출물의 reference_version 대조 |
| R4 | comparability: 엔진이 같은 오디오·슬라이싱·boundary 조건에서 돌았는가 | 조건이 다르면 공정 비교 아님 | engine_run_bundle_manifest의 입력 조건 대조 |
| R5 | 샘플 대표성 + phantom(환각) | 7개(국회 회의)가 Minto 실사용 회의를 대표하는가, phantom이 점수에 섞이는가 | 샘플 도메인 분포 + 기존 phantom 측정 결과 참조 |
| R6 | 엔진별 디코딩 파라미터의 공정성·기록 | (1) 엔진마다 다른 파라미터로 돌면 불공정 비교, (2) 파라미터가 `engine_run_bundle_manifest`에 기록 안 되면 재현 불가, (3) phantom 억제 파라미터(`compression_ratio_threshold`, `logprob_threshold`, `no_speech_threshold`, `condition_on_previous_text`, temperature fallback, `language=ko` 강제)가 엔진마다 다르게 설정되면 CER 왜곡 | 각 engine bundle manifest / runner_contract의 파라미터 필드 기록 여부와 값 대조 |

## 5. 단계별 계획

### Phase 0 — 신뢰성 전제 진단 (STT 재실행 전, 필수)
- 목적: "지금 비교를 돌리면 결과를 믿을 수 있는가?"에 답한다.
- 작업: R1~R6을 코드/데이터로 확정. 특히 (a) reference 검증의 실제 상태, (b) timing shift가 CER 채점에 영향을 주는지(채점이 시간정렬 기반인지 텍스트정렬 기반인지), (c) 버전 정합 현황 전수 대조, (d) engine bundle manifest/runner_contract에 디코딩 파라미터가 기록되는지와 엔진 간 값 차이(R6).
- 산출: 신뢰성 진단 리포트(어떤 위험이 실재하고 어떤 건 무해한지). `docs/benchmark/` 또는 HTML/MD.
- 검증 기준: R1~R6 각각에 "실재/무해" 판정과 근거가 달릴 것.
- 위임: 진단(측정/조사)은 main이 직접 + scientist 에이전트. 코드 수정 없음.

### Phase 1 — 기준 확정 (결정 + 사람 검증)
- 결정 D1: 공식 reference 버전을 하나로 확정(`official-reference-draft` vs `seed-smi`).
- 작업: timing shift가 R2에서 유해로 판정되면 보정(시간 오프셋 정렬) 또는 reference 재생성. reference 사람 검증을 audit 가능한 형태로 남김(R1 해소).
- 검증 기준: reference manifest가 단일 버전 + 사람 검증 evidence 보유.
- 위임: 코드 변경은 codex, 검증은 리뷰 에이전트.

### Phase 2 — STT 엔진 재실행 (동일 조건)
- 작업: 확정 reference로 모든 엔진을 comparable하게 재실행 → engine_run_bundle_manifest 생성. **이 단계가 사용자 환경(WhisperKit 등 모델 구동)을 요구**한다.
- 검증 기준: 모든 엔진이 같은 버전·같은 입력 조건. R4 해소.
- 주의: 엔진 실행 절차/명령은 Phase 0~1에서 미리 조사해 둔다.

### Phase 3 — release workflow 완주
- 작업: preflight → decision → regression → release. `official_release_workflow_report.json`이 default gate 통과.
- 산출: 실제 엔진 우열 결과(CER 등).

### Phase 4 — 결과 신뢰성 검증 (적대적)
- 작업: 나온 숫자가 timing/phantom/편향에 오염되지 않았는지 적대적 검증(R2, R5). 가능하면 독립 lens 다수.
- 검증 기준: 우열 결론이 검증을 통과해야 "공식 채택 근거"로 인정.

## 6. 지금 필요한 결정

- **D1 (버전)**: 공식 reference를 `official-reference-draft-2026-06-12`로 갈지, `seed-smi-2026-06-12`로 되돌릴지, 새로 만들지. → Phase 0 진단 후 확정 권장.
- **D2 (timing 정책)**: timing shift를 (a) 보정해서 쓸지 (b) 무해하다고 판정되면 그대로 쓸지 (c) 해당 샘플 제외할지. → Phase 0의 R2 결과에 의존.
- **D3 (엔진 실행 환경)**: Phase 2의 STT 재실행을 어디서/어떻게 돌릴지(시간·환경).
- **D4 (파라미터 정책)**: 비교 기준 파라미터를 (a) 각 엔진 기본값(out-of-box) vs (b) Minto 실사용 설정(product_path) vs (c) 엔진별 튜닝 최선 중 무엇으로 고정할지. phantom 억제 파라미터를 엔진 간 어떻게 정렬할지. → Phase 0에서 현재 기록 상태(R6)를 본 뒤 확정.

## 7. 작업 방식 (이번 세션과 동일)
- 사전 검토: 병렬 다각도 에이전트.
- 코드 작업: codex 위임(자세한 작업서) + git/테스트로 실제 변경 검증.
- 품질: code-reviewer 리뷰 + main이 직접 불변식/QA 독립 검증.
- 불변식: `run_after_human_review.sh`가 최소 ③fill까지 통과 유지. `reference_review_decisions.to_fill.csv`(7 reviewed) 보존. STT 임의 재실행 금지(Phase 2에서 명시 합의 후).

## 8. 미해결/메모
- `~/.codex/config.toml`에 API 키 평문 노출 — 별도 보안 점검 필요(이 작업과 무관).
- codex sandbox writable_roots를 config에 추가함(framework worktree 작업용). 백업: `~/.codex/config.toml.bak-minto2-*`.
