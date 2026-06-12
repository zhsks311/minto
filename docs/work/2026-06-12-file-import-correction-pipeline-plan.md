# 파일 임포트 교정 파이프라인 속도 개선 계획

작성일: 2026-06-12

## 문제

`MeetingFileImportUseCase.importChunk`가 완전 직렬이다: 청크 추출 → STT → **LLM 교정 완료 대기** → 다음 청크. 1시간 오디오(30초 청크 120개) 기준 청크마다 STT(~2-4초) 뒤에 LLM 교정(네트워크, ~3-8초)이 끼어 wall-clock의 절반 이상이 교정 대기다.

- STT는 ANE-bound라 병렬화해도 총 처리량이 늘지 않는다(시스템 부하만 증가).
- LLM 교정은 네트워크 대기라 CPU/ANE를 거의 쓰지 않는다 — STT 뒤에 숨길 수 있는 시간이다.
- 직렬화의 원인은 교정 문맥 `previousContext`가 **직전 교정문 5개**를 요구하는 데이터 의존성이다(`MeetingFileImportUseCase.swift:347`).

## 목표

임포트 wall-clock을 STT 시간 수준으로 수렴시킨다(교정 켜진 임포트 기준 체감 2배 내외). 시스템 부하는 늘리지 않는다(STT 직렬 유지, 동시 교정 호출 상한).

## Phase 1 — 교정 병렬화 (이번 구현)

### 설계

- STT는 extractor의 backpressure 안에서 **직렬 유지**(청크 순서 = segment 순서 보존).
- STT 완료 즉시 원문 segment를 순서 보존 누적기에 추가하고, 교정을 **백그라운드 Task로 디스패치**(동시 상한 3, slot 양도형 limiter).
- 교정 문맥을 직전 **교정문** 5개 → 직전 **원문(STT 출력)** 5개로 변경해 의존성을 제거한다.
  - 트레이드오프: 문맥에 오인식이 섞일 수 있음. 문맥은 지시가 아니라 참고자료로 들어가며, 교정 대상 텍스트 자체는 동일하므로 영향은 제한적이라고 판단. 품질 회귀 의심 시 기존 벤치마크 하니스로 측정한다.
- 추출 완료 후 `.correcting` 단계에서 미완료 교정을 drain(진행 표시 "전사 다듬는 중 k/n") → 요약 → 저장.
- fail-soft 유지: 교정 nil/실패/취소 → 해당 segment는 원문 유지.
- 취소: 임포트 실패·취소 시 대기 중 교정 Task 전부 cancel. drain 후 `Task.checkCancellation`.

### 구현 단위

- `MeetingFileImportUseCase` 내 `@MainActor` 보조 타입 `ImportCorrectionPipeline`(가칭): segments 누적, 원문 문맥 스냅샷, 동시 상한 limiter, 교정 Task 보관, corrected/fallback 카운트.
- `Segment`는 전 필드 `let` → 교정 반영은 같은 id/timestamp/duration으로 새 Segment 교체.
- 동시 상한 limiter는 release 시 대기자에게 slot을 **양도**하는 방식(decrement 후 resume 사이의 초과 진입 방지).
- 로그(이벤트 로깅 컨벤션): drain 시작 `info`(pending 수), 완료 `info`(corrected/fallback 수). 교정 호출 자체의 실패 로그는 기존 LLMCorrectionService 경로 유지.

### 동작 계약 변경

- UI 단계: 기존 "청크마다 transcribing↔correcting 교차" → "추출 중 transcribing 유지, 추출 후 correcting drain". `exposesCorrectionAndSummaryStagesDuringImport` 테스트를 새 계약으로 갱신한다.
- 교정 문맥: 직전 원문 5개(위 트레이드오프 참조).

### 테스트

1. 순서 보존: 교정이 순서 뒤바뀌어 완료돼도 transcript 순서는 청크 순서.
2. 동시 상한: 상한 2 주입 + 지연 스텁으로 최대 동시 교정 == 2.
3. fail-soft: 일부 교정 nil → 해당 청크만 원문, 나머지는 교정문.
4. 문맥 내용: n번째 교정 호출의 previousText == 직전 원문들.
5. 취소: drain 중 취소 → cancelled 상태, 저장 없음.
6. 기존 테스트 갱신: 단계 노출 계약, 교정 적용 경로.

## Phase 2 — 교정 배치화 (Phase 1 검증 후)

- 청크 3~5개를 한 호출로 묶어 호출 수 1/3~1/5 (rate limit 보호 + 고정비용 절감 ~20-25%).
- 선행 조건: ① 배치용 프롬프트 + 번호 기반 응답 파싱(파싱 실패 시 배치 단위 원문 fail-soft), ② API key 경로 correction 출력 천장(900토큰, `LLMAPIKeyTextProvider`)을 배치 크기에 맞춰 상향.
- 트리거: Phase 1 머지 후 긴 파일 임포트에서 429/rate limit 관측 또는 추가 단축 필요 시.

## 변경하지 않는 것

- STT 직렬 실행, extractor backpressure 계약, 청크 크기(30초), 녹음 경로의 교정 흐름, 화자분리(별도 계획).

## 검증 게이트

- `git diff --check`
- `./scripts/dev.sh build`
- `./scripts/dev.sh test` (전체)
- 로그에 전사/프롬프트 원문 미포함 확인
