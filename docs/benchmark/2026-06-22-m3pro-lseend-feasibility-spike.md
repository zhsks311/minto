# M3 Pro feasibility 스파이크 — LS-EEND CPU RTFx

측정 2026-06-22. 하드웨어 **Apple M3 Pro (Mac15,6)** — 타깃 기기 직접 측정. ADR 0005 수락 게이트.

## 질문

"녹음 중 STT(ANE) + LS-EEND 화자분리(CPU)를 동시에 실시간으로 돌릴 수 있나?" — 가장 싼 첫 데이터로 **LS-EEND가 M3 Pro CPU에서 얼마나 빠른가**를 잰다.

## 방법

`Tests/MintoTests/LSEENDCountFeasibilityTests.swift`에 `processComplete` 순수 처리시간 instrumentation 추가(audioSec/procSec/rtfx). `LSEENDVariant.ami`, `computeUnits: .cpuOnly`(LS-EEND 기본). 한국어 토론 코퍼스.

## 결과

| 파일 | 오디오 길이 | 처리시간(CPU) | **RTFx** | 검출 화자 |
|------|-----------|-------------|---------|----------|
| 4people | 1853.0s (30:53) | 33.37s | **55.5×** | 2 |
| 5people | 1402.1s (23:22) | 21.94s | **63.9×** | 4 |

→ LS-EEND는 M3 Pro **CPU만으로 실시간의 55~64배** 속도. ADR Verification 기준 `RTFx > 1.0`을 압도적으로 통과.

## 해석 (컴퓨트 헤드룸 = PASS)

- STT(WhisperKit)는 **이미 이 셋업에서 라이브 실시간으로 동작**(앱이 녹음 중 전사). STT=ANE.
- LS-EEND=CPU, STT=ANE → **다른 연산 유닛**. LS-EEND가 CPU에서 55× 여유.
- 따라서 "이미 도는 실시간 STT(ANE) + 55× 여유의 CPU 작업 추가" → **동시 실시간 가능(높은 확신)**.
- LS-EEND CPU 정확도 = 측정값 그대로(기본이 `.cpuOnly`라 우리가 잰 게 곧 CPU 정확도) → critic M4(CPU vs ANE) 부분 해소: 우리는 어차피 CPU로 쓴다.

## 잔여 (직접 측정 안 함 — 헤드룸이 커 블로커 아님, 구현 시 스모크)

- **스트리밍 모드 RTFx**: 측정은 batch(`processComplete`). 라이브는 streaming `process()` 청크 단위 → per-chunk 오버헤드 다름. 단 모델 컴퓨트(지배적 비용)가 55× 여유라 streaming도 실시간 여유 충분 예상.
- **실제 동시 실행**: STT+LS-EEND 동시 구동 직접 측정 안 함(다른 유닛+55× 여유로 추정 강함).
- **장시간 발열·배터리**: 1~2시간 회의 지속 부하 미측정.

## 결론

**컴퓨트 헤드룸 기준 PASS.** ADR 0005의 핵심 feasibility 의문(LS-EEND가 M3 Pro에서 도는가)은 해소. 잔여(스트리밍 RTFx·동시 실행·지속 발열)는 구현 단계 스모크 테스트로 확인하되 설계를 막지 않는다. → ADR 0005를 구현 단계로 진행 가능(잔여를 구현 verification에 포함).

## 재현
`RUN_LSEEND_POC=1 DIARIZATION_EVAL_WAV=<wav> LSEEND_VARIANT=ami swift test --disable-sandbox --scratch-path /tmp/minto2-diar-clustering --filter LSEENDCountFeasibility` → `[LSEEND-POC] ... rtfx=` 확인.
