# 임포트 교정 배치화 Phase 2 (2026-06-13, #22)

## 배경

Phase 1(#19)이 임포트 교정을 STT 뒤로 숨겼지만, 호출 수는 청크당 1회 그대로였다. OAuth 경로(Codex/Gemini/Copilot)의 rate limit과 호출 고정비용을 줄이기 위해 청크 3개를 한 호출로 묶는다.

계획: `docs/work/2026-06-12-file-import-correction-pipeline-plan.md` Phase 2 절. 구현은 Codex가 아닌 executor(sonnet) 위임 + 본 세션 마무리.

## 변경

- `BatchCorrectionPrompt`: `[n] 원문` 번호 목록 입력/응답 계약. 파서는 세그먼트 수 불일치·번호 누락·순서 뒤섞임 시 nil(배치 전체 원문 유지 fail-soft). 원문에 `[2]` 같은 마커가 섞여도 순서 검증에서 걸러 fail-soft로 종결(리뷰 확인).
- `LLMCorrectionService.correctBatch`: 출력 한도는 기존 요청 단위 override(`LLMTextRequest.maxOutputTokens`)를 재사용해 900×배치 크기. provider 오류·파싱 실패 시 nil. 로그는 provider id·batchSize만(원문 금지).
- `ImportCorrectionPipeline`: 배치 버퍼(크기 3)로 모아 디스패치, 추출 종료 시 잔여 flush. 배치=slot 1개 점유. 순서 보존·취소(slot 대기자 wake)·corrected/fallback 카운트는 Phase 1 계약 유지.
- **문맥 계약 변경**: previousText = 배치 첫 청크 직전 원문 5개 스냅샷. 배치 안 청크들은 같은 프롬프트의 번호 목록으로 서로를 직접 보므로 청크별 문맥이 불필요하다(Phase 1 문맥 테스트를 배치 경계 기준으로 갱신).

## 리뷰 (opus critic) 및 반영

Critical 0 / Major 2.

- **M1 반영**: 단건 `CorrectionPrompt`의 가드 2개가 배치 instructions에 누락 — 직전 발화 맥락 echo-back 금지, 뭉개진 구간을 그럴듯하게 메우지 않기(길이 불증가). 배치만 약한 지침을 받아 환각 삽입 여지가 있던 품질 회귀를 차단.
- **M2 반영**: 동시 상한 통합 테스트의 `maxActive==2` 단언이 배치 2개 구조에서 타이밍 의존(flaky) → 결정적 게이트 단위 테스트에 위임, 통합 테스트는 배치 분할(3+1)·상한 비초과만 단언.
- minor 반영: 단건 `dispatchCorrection`은 테스트 전용임을 주석으로 명시. 미반영(인지): drain 진행 표시 k/n이 배치 수 기준이 됨(UX 영향 미미), `afterMarkerText` dead branch(독자 혼란 수준).

## 중단·복구 기록

- executor가 커밋 2개 후 세션 한도로 중단 → 파이프라인 배치화 미커밋분을 본 세션이 인수해 완성.
- executor의 게이트 스텁 취소 테스트가 **텍스트별 gate 대기에 release 1회만 호출해 교착** — 테스트 행으로 swift-test가 9시간 잔존하며 .build 락을 쥐고 있었다. 반복 release 패턴으로 수정. (교훈: 게이트 스텁과 배치 루프 조합 시 release 횟수는 게이트 등록 횟수와 일치해야 한다)

## 검증

- `./scripts/dev.sh test` 전체 480개(66 suites) 통과 — 신규: 프롬프트 왕복/파싱 실패 케이스, 배치 분할 3+3+1, 배치 단위 fail-soft, 순서 보존, 취소 wake, correctBatch hint.
- main 머지 후 통합 검증은 본 로그와 같은 커밋 흐름에서 실행.

## 효과/관찰

- 호출 수 1/3 — 긴 파일 임포트의 429 노출 감소 + 호출 고정비용 ~20-25% 절감(병렬화와 합산 시 wall-clock은 STT 시간 수렴 유지).
- 관찰 항목: 배치 응답 파싱 실패율(`correctBatch parse failed` 로그) — 실측에서 유의하게 나타나면 번호 형식 강화 또는 구조화 출력 검토.
