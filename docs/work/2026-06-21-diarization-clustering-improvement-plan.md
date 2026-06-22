# 화자분리 클러스터링 개선 — 검토 & 방향

작성 2026-06-21, 갱신 2026-06-21. 브랜치 `feat/diarization-clustering` (워크트리 minto2-wt-diar-clustering, main 67fc27a). 분류: research/review.

## 배경 (조사 결론)

병목 = 화자 수 추정(클러스터링). 모델·임베딩·설정은 community-1과 동일/충분함이 측정으로 확인됨(`2026-06-21-speaker-embedding-research-review.md`, `2026-06-20-...measurement.md`). 따라서 개선은 community-1 모델을 그대로 두고 **counting 방식**에서 찾는다.

## 지형표 — 화자 수 추정 방법

| 방법 | count 추정 | 비고 |
|------|-----------|------|
| AHC | 거리 임계값 | 약함(정답 ~1/2) |
| **VBx**(우리 것) | 베이즈 + 자기조절 | AHC보다 나음(정답 2/3), 나머지 1/3 + Fa 비단조가 문제 |
| **cVBx** | VBx + 화자수 경계 | 평균 count 오차 0.16 — 경계만 줘도 개선 |
| **NME-SC** | 스펙트럴 eigengap 자동 | 학계 표준(NeMo), 튜닝 불필요 |
| **EEND**(LS-EEND/Sortformer) | 신경망 attractor가 count 직접 추론 + 겹침 | 클러스터링 우회. FluidAudio 0.15.2에 **이미 번들** |

## 사다리 — 우리에게 쓸만한 것 (비용순)

| 순위 | 방법 | 비용 | 상태 |
|------|------|------|------|
| ① | min/max 경계 노출(cVBx) | S | **보류** — provider는 완비됐으나, 기존 "예상 인원"(exact)+자동으로 대부분 커버. "범위"는 한계효용 낮음(사용자 판단 2026-06-21). |
| ② | exactSpeakerCount | — | **유지** — 구현·검증 완료, 사용자가 인원 알면 최강 |
| ③ | **LS-EEND vs VBx 측정** | M | **완료(2026-06-22) → 기각**. LS-EEND가 count는 근접하나 DER(AMI proxy)에서 VBx 12% vs LS-EEND 25.7%로 2배 열위. LS-EEND는 스트리밍용. 오프라인 경로 교체 안 함. 결과: `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md` |
| ✗ | NME-SC 자체 구현 | L | community-1 이탈 + affinity 파이프라인 신설. ②③로 부족할 때만 |

## 권고

- **exactSpeakerCount(사용자 인원 입력)를 1차 답으로 유지.** 자동 추정이 필요한 경우의 개선은 ③(EEND)에서 찾는다.
- **min/max UI는 보류** — 입력창을 더 복잡하게 만드는 비용 대비 이득이 작음(exact/auto 2분기로 충분).
- **③ LS-EEND 측정 완료(2026-06-22) → VBx 체제 확정**: LS-EEND가 count는 근접하나 DER(AMI proxy)에서 VBx 2배 우수. LS-EEND는 스트리밍/저지연용이라 오프라인 정확도엔 부적합. 오프라인 경로 교체 안 함. **결론: VBx + exactSpeakerCount 유지.** (LS-EEND는 향후 라이브 화자분리 과제 시 재검토.)

## 범위 밖

NME-SC 구현, 임베딩 교체(측정으로 반증), community-1 모델 변경, min/max UI(보류).

## Sources
- NME-SC arXiv 2003.02405 / VBx arXiv 2012.14952 / VBx+EEND arXiv 2510.19572 / EEND-EDA overview(emergentmind)
