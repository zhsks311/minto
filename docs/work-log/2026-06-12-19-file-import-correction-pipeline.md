# 파일 임포트 교정 병렬 파이프라인 (2026-06-12, #19)

## 배경

파일 임포트가 "청크 추출 → STT → LLM 교정 완료 대기 → 다음 청크" 완전 직렬이라, 교정이 켜진 임포트는 wall-clock의 절반 이상이 네트워크 교정 대기였다. 1시간 오디오(30초 청크 120개) 기준 청크마다 STT(~2-4초) + 교정(~3-8초)이 순차로 쌓였다.

계획: `docs/work/2026-06-12-file-import-correction-pipeline-plan.md` (Phase 1 구현, Phase 2 배치화는 보류 조건부)

## 변경

`Sources/Minto/Services/MeetingFileImportUseCase.swift`

- STT는 직렬 유지(ANE-bound — 병렬화해도 총 처리량 불변, 부하만 증가), LLM 교정만 동시 상한 3의 백그라운드 Task로 분리.
- 신규 `ImportCorrectionPipeline`(@MainActor): segment 순서를 추가 시점 index로 고정(교정 완료 순서와 무관), slot 양도형 동시 상한 limiter, corrected/fallback 카운트.
- 교정 문맥을 직전 교정문 5개 → 직전 원문 5개로 변경해 교정 간 직렬 의존성 제거. (트레이드오프: 문맥에 오인식 포함 가능 — 품질 회귀 의심 시 벤치마크 하니스로 측정)
- 추출 완료 후 `.correcting` 단계에서 drain("전사 다듬는 중 k/n"), 그 뒤 요약·저장. 교정 실패/nil/취소는 해당 청크 원문 유지(fail-soft).
- 로그: drain 시작(pending 수), 완료(corrected/fallback 수) — 카운트만, 원문 없음.

## 리뷰 (opus critic) 및 반영

판정 ACCEPT-WITH-RESERVATIONS, Critical 0 / Major 2 / minor 5.

- **M1 반영**: `cancelPendingCorrections()`가 slot 대기자를 깨우지 않아 취소가 실행 중 task의 해제까지 지연되는 잠재 결함 → `acquireSlot()`을 Bool 반환으로 바꾸고 취소 시 대기자를 `false`로 즉시 resume(slot 미보유로 fallback 종료). drain에도 취소 조기 탈출 추가.
- **M2 반영**: limiter를 통합 테스트로만 간접 검증 → `ImportCorrectionPipelineTests` 신설. 게이트 스텁(continuation)으로 ① 동시 진입 상한·slot 양도, ② 취소 시 대기자 wake(서비스 미진입 fallback)를 suspension 경계에서 직접 검증.
- minor: Task 생명주기([weak self]=순환참조 방지, guard let 후 강참조로 pipeline 유지) 주석 명시. 나머지(진행률 역행 없음, 중복 cancel 멱등, emptyTranscript 경로, 요약 전 drain 보장, 로깅 컨벤션)는 "확인됨".
- **미반영(관찰 항목)**: `LLMCorrectionService.activeCorrections` 전역 카운터가 임포트 병렬 교정으로 최대 3까지 올라감 — 녹음 UI 인디케이터와 공유되는 기존 구조로, 동시 사용 시 표시 의미를 다음 UI 작업에서 점검.

## 검증

- `./scripts/dev.sh build` 통과
- `./scripts/dev.sh test` 전체 458개(64+1 suites) 통과 — 신규 8개(순서 보존, 동시 상한, fail-soft, 원문 문맥, drain 취소, 단계 계약 갱신, limiter 상한, 취소 wake)
- `git diff --check` 클린

## 효과/한계

- 교정 시간이 STT 뒤에 숨어 임포트 wall-clock이 STT 시간으로 수렴(교정 켜진 긴 파일 기준 체감 ~2배). 실파일 측정은 다음 임포트에서 `import correction drain` 로그로 확인 가능.
- Phase 2(교정 배치화: 호출 수 1/3~1/5, rate limit 보호)는 보류 — 트리거: 긴 파일 임포트에서 429 관측 또는 추가 단축 필요. 선행 조건은 계획 문서 참조(출력 천장 900토큰 상향 + 번호 파싱 fail-soft).
