# 화자 임베딩 연구 지형 & 실사용 가능성 검토

작성 2026-06-21. 분류: research/review. 목적: "더 나은 임베딩으로 바꿀 가치가 있나"를 우리 제약(온디바이스 CoreML · community-1 파이프라인 · 한국어 회의)에 비춰 판단.

## 배경 (선행 측정으로 좁혀진 상태)

- 우리 화자분리 = pyannote community-1(powerset seg + WeSpeaker v2 embedding + VBx) CoreML 변환본. (메타데이터 확정)
- 클러스터링 설정(threshold 0.6 / Fa 0.07 / Fb 0.8)이 pyannote community-1 `config.yaml`과 **글자 그대로 일치** → 설정·알고리즘은 우리 잘못 아님(2026-06-21 대조 완료).
- Phase 2: 임베딩 변별력 gap 0.40(충분), 병목은 counting(클러스터링). 단 사용자가 한국어 임베딩 약점 가능성 제기.

## 1. 연구 지형 (대략 성능순, VoxCeleb 기준)

| 모델 | 계열 | 비고 |
|------|------|------|
| x-vector | TDNN | 고전 |
| ResNet34 | CNN | wespeaker 기본 |
| ECAPA-TDNN | TDNN+attn | 광범위 표준 — **우리 WeSpeaker v2가 이 변형** |
| CAM++ | D-TDNN+masking | 빠름, 중국어 강함 (senko 사용) |
| **ERes2NetV2** | multi-scale Res2Net | 2024, **CAM++ 능가**, 파라미터 적고 빠름, 단발화 강함, 200k 화자 학습 |
| **ReDimNet** | reshape-dim | 2024 SOTA, 저연산 |
| WavLM (SSL) | self-supervised 대형 | diarization SOTA지만 ~300M, 온디바이스 비현실적 |

→ 우리 임베딩은 2024 기준 **중상위**. 위에 ERes2NetV2·ReDimNet·CAM++ 존재 = EER 헤드룸 있음. 단 EER↑가 counting↑로 이어진다는 보장은 약함.

## 2. 한국어/다국어 현실

- 한국어 전용 SOTA 임베딩 사실상 없음. 표준 전략 = Vox+CN-Celeb+VoxBlink 다국어 robust 학습.
- 모든 모델에 한국어는 out-of-domain. 다국어 학습 모델(3D-Speaker CAM++/ERes2NetV2)이 VoxCeleb 편중 wespeaker보다 한국어에 약간 더 일반화할 **가능성**(검증 필요).

## 3. 온디바이스 필터

- WavLM SSL: 정확도 최상위지만 대형 → CoreML/ANE 비현실적. 탈락.
- ERes2NetV2 / CAM++: 효율 설계 → 온디바이스 후보 생존.

## 4. 실사용 3경로 & 비용

파이프라인이 임베딩→PLDA→VBx로 묶여 임베딩만 바꾸면 뒷단이 깨진다.

| 경로 | 비용 | 함정 |
|------|------|------|
| **A. FluidAudio/pyannote 신모델 대기** | ~0 | 통제 불가, 자동 수혜 |
| **B. ERes2NetV2/CAM++ 교체** | L | CoreML 변환 + 차원 불일치 + **PLDA 재학습** + VBx 재튜닝 + **community-1 이탈** |
| **C. WavLM SSL** | XL | B + 대형 변환난 |

핵심: 임베딩 교체 = 오프라인 파이프라인 뒷단 절반 재구축 + pyannote 생태계 이탈.

## 5. 추천 — "병목인지" 먼저 (싸게)

1. **(싸다) 한국어 화자쌍 변별력 측정**: WeSpeaker v2로 한국어 코퍼스의 화자쌍별 거리 분포. 평균 gap이 아니라 **최악 화자쌍(비슷한 목소리) 분리도**를 본다. 이게 임베딩 병목 여부를 가르는 결정적 싼 실험.
2. 변별력 충분 → 교체는 비용만, 효과 없음. A 대기 + exactSpeakerCount 유지.
3. 변별력 약함 → **ERes2NetV2**가 1순위(2024 최상위·효율·다국어·오픈웨이트). 단 B 풀비용 + ADR(뒷단 재구축·community-1 이탈).
4. 상시: FluidAudio/pyannote 후속 임베딩 CoreML 추적(A, 무료).

## 6. 측정 결과 (2026-06-21) — 임베딩 가설 대체로 반증

한국어 토론 코퍼스에서 화자쌍별 cosine 측정(`VoiceprintFeasibilityTests`에 worstPair 추가, exactN 강제).

| 파일 | exactN | intra | worstPairInter | worstGap | 비고 |
|------|--------|-------|----------------|----------|------|
| 4people | 4 | 0.861 | 0.613 | **0.248** | S1:24청크(발화 적음→centroid 노이즈) |
| 5people | 5(정답) | 0.860 | 0.413 | **0.447** | perSpeaker 132~171 균형 |
| 5people | 6(과다) | 0.861 | 0.557 | 0.304 | S2:1청크 허위분할(과다강제 아티팩트) |

**결론**: 모든 케이스 worst-pair margin 양수(0.25~0.45) = 임베딩이 정답 화자수에서 최악쌍도 갈라냄. 결정타는 5people — 임베딩 변별력 최상(0.45)인데도 Phase 2 자동 counting은 2로 붕괴 → **병목은 임베딩이 아니라 counting(클러스터링)**. 4people worstGap 0.25는 S1 소표본 아티팩트 가능성 큼.

→ **임베딩 교체(경로 B/C)는 핵심 병목 미해결.** 더 나은 임베딩은 빠듯한 worst-pair 여유를 넓히는 부수효과뿐. counting을 고치려면 클러스터링 쪽인데 community-1과 동일해 여지 작음. **exactSpeakerCount(사용자 인원 입력)가 정답** 재확인.

**한계**: intra-recording·토론 음질(깨끗)·소표본. 크로스세션·잡음 회의 미측정(보이스프린트 재식별엔 더 어려울 수 있음).

## 상태

- [x] 연구 지형 검토
- [x] 한국어 화자쌍 변별력 측정 → 임베딩 가설 대체로 반증, counting이 병목 재확인
- [x] ERes2NetV2 PoC 결정: **보류** — 임베딩이 병목 아님이 측정으로 확인됨. 임베딩 교체는 비용 대비 핵심 문제 미해결. (크로스세션 재식별이 과제가 되면 그때 재검토)

## Sources
- ERes2NetV2 arXiv 2406.02167 / 3D-Speaker github.com/modelscope/3D-Speaker / SSL diarization arXiv 2409.09408 / VoxSRC retrospective arXiv 2408.14886
