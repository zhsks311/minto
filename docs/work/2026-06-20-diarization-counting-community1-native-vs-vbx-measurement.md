# 화자 수 추정: pyannote community-1 네이티브 클러스터링 vs FluidAudio VBx 비교 측정

작성 2026-06-20, 갱신 2026-06-21. 상태: **선행 점검(config 대조) 완료 → 동일. 풀 측정은 후순위로 격하**. 분류: benchmark/measurement.

## 결과 업데이트 (2026-06-21) — 선행 점검 완료

**FluidAudio 기본값과 pyannote community-1 `config.yaml`이 글자 그대로 일치한다.** → "설정 불일치" 가설 기각.

| 파라미터 | 우리(FluidAudio) | community-1 config.yaml | 일치 |
|---|---|---|---|
| 클러스터링 | VBx(+AHC warm-start) | VBxClustering | ✅ |
| threshold | 0.6 | 0.6 | ✅ |
| Fa | 0.07 | 0.07 | ✅ |
| Fb | 0.8 | 0.8 | ✅ |
| embedding exclude_overlap | true | true | ✅ |
| min_duration_off | 0.0 | 0.0 | ✅ |
| maxIterations | 20 | (미명시) | ⚠️ 유일 미확인 |

PLDA 파라미터(`plda-parameters.json`·`xvector-transform.json`)도 `version: pyannote-speaker-diarization-community-1` source `plda/*.npz` — pyannote 것 그대로.

**함정 정정**: 초기 웹검색의 "AgglomerativeClustering threshold 0.7045 / centroid / min_cluster_size=12"는 **옛 pyannote 3.1** 설정이다. community-1은 3.1의 AHC를 버리고 **VBxClustering(0.6/0.07/0.8)으로 전환**했고, FluidAudio가 이를 정확히 mirror했다. "FluidAudio가 네이티브 클러스터링을 VBx로 대체했다"는 가설도 함께 기각 — VBx가 곧 community-1의 네이티브다.

**함의**: (1) 우리는 community-1 공개 레시피를 글자 그대로 실행 중 → 맞춰볼 값이 없다. (2) pyannote 네이티브 비교(아래 풀 측정)는 설정 동일하니 **구현 충실도 차이만** 남아 기대값 급락 → **후순위**. (3) Phase 2의 "counting은 community-1 고유 한계, exactSpeakerCount 우회가 정답"이 재확인됨. (4) 남은 레버는 **임베딩 변별력(한국어)·segmentation 적합도** → 다음 측정 대상으로 이동.

---

## (이하 원래 설계 — 풀 측정은 후순위 보류)

## 배경 (확정된 사실)

- 우리 화자분리(FluidAudio offline)는 **pyannote community-1** segmentation + WeSpeaker embedding의 **CoreML 변환본**을 쓴다. 모델 메타데이터로 확정: `version=pyannote-speaker-diarization-community-1`, 변환일 2025-10-13(릴리스 2025-09-29 이후). HF base = `pyannote/speaker-diarization-community-1`.
- 단 **클러스터링은 pyannote 네이티브가 아니라 FluidAudio 자체 VBx**(PLDA 기반)를 쓴다.
- community-1의 헤드라인 개선은 **"speaker counting & assignment 향상 + exclusive single-speaker"**다 — 이는 Phase 2에서 측정한 우리 병목(화자 수 추정 불안정)과 정확히 같은 축이다.

## 풀려는 질문 (단서 2)

> community-1의 counting 개선이 **모델(segmentation)에 내재**한 것이라 우리도 이미 받고 있는가, 아니면 **pyannote 네이티브 파이프라인의 클러스터링/할당 로직**에 있어서 FluidAudio가 VBx로 대체하며 **놓쳤는가**?

이 답이 diarization 로드맵을 가른다:
- **모델에 내재** → 우리는 이미 최선. Phase 2 결론(사용자 인원 입력→exactSpeakerCount) 유지가 정답.
- **네이티브 클러스터링에 있음** → 기회 존재. pyannote 네이티브 클러스터링 경로(Python 사이드카 또는 FluidAudio가 노출하길 기대)를 검토할 가치.

## 가설

H1: Phase 2의 counting 불안정(Fa/threshold 비단조·under-count)은 **모델 한계가 아니라 VBx 클러스터링 ≠ pyannote 네이티브**여서다. → pyannote 네이티브는 같은 코퍼스에서 화자 수를 더 정확히 맞춘다.

H0(귀무): 둘 다 비슷하게 어렵다. counting은 클러스터링 방식 무관하게 본질적으로 어렵다. → Phase 2 결론 유지.

## 방법

### 대상 코퍼스 (Phase 2 재사용 — 정답 화자 수 알려짐)
- 4인 토론 (30:53)
- 5/6인 선거토론 (23:22)
- 국회 행안위 (2:02:58)

(경로·정답 라벨은 Phase 2 측정 문서 `docs/work/2026-06-14-phase2-multispeaker-diarization-measurement.md` 참조.)

### 비교 대상
- **A. pyannote community-1 네이티브** (pyannote.audio 4.0, Python): 기본 파라미터 + `num_speakers` 미지정(=자동 counting).
- **B. FluidAudio offline (현행)**: community-1 seg/embed + VBx, 기본 파라미터, exactSpeakerCount 미지정(=자동).

두 경우 모두 **자동 counting**으로 비교한다(질문이 "자동으로 몇 명을 맞추나"이므로). 보조로 `min/max_speakers`(A)·`minSpeakers/maxSpeakers`(B) 경계를 준 경우도 측정해 "경계가 양쪽을 얼마나 돕나" 본다.

### 지표
1. **predicted speaker count vs 정답** (핵심 축 — counting 정확도). 파일별 |예측−정답|.
2. **DER** (참조 RTTM이 있으면). 한국어 코퍼스는 정밀 RTTM이 없을 수 있으니 최소 counting은 확보, DER은 가능 범위에서.
3. 정성: 과분할/under-count 방향.

### 실행 순서
1. pyannote.audio 4.0 설치 + community-1 모델 접근(HF 토큰 + 라이선스 수락 — gated).
2. Python 하니스로 3개 파일 × {A, B} × {자동, min/max 경계} 실행.
3. predicted count 표 + (가능시) DER 표 작성.
4. 결정 규칙 적용.

### 결정 규칙
- A가 B보다 화자 수를 유의하게 정확히 맞춤(특히 B가 under-count하는 다화자에서) → **H1 채택**. 후속: pyannote 네이티브 클러스터링 경로 ADR 검토(Python 사이드카 비용 vs 온디바이스 이점 손실 trade-off).
- A·B 모두 비슷하게 틀림 → **H0 채택**. Phase 2 결론(exactSpeakerCount/사용자 인원 입력) 유지 확정. min/max 경계 효과만 제품에 반영(이미 배선됨).

## 리스크 / 한계
- **community-1 gated 모델**: HF 토큰 + 라이선스 수락 필요. 접근 막히면 측정 불가.
- **참조 RTTM 부재**: 한국어 코퍼스에 정밀 정답 세그먼트가 없으면 DER 정량화 제한 → counting 정확도 중심으로 결론.
- **환경**: 이 머신에 pyannote.audio 4.0(PyTorch) 설치 필요. 온디바이스 제품 경로와 무관한 측정 전용 환경.
- **교란**: A는 pyannote 네이티브 segmentation도 PyTorch로 돌고 B는 CoreML 변환본 → segmentation 미세 차이가 섞일 수 있음. 단 같은 community-1이라 클러스터링 차이가 지배적이라고 가정(검증 대상).

## 범위 밖 (하지 않음)
- 운영 클러스터링 교체. 이건 측정만이다.
- 임베딩 모델 교체(CAM++ 등) — 별도 분석에서 "병목 아님"으로 결론.

## 산출물
- 결과: `docs/benchmark/2026-06-20-diarization-counting-community1-vs-vbx.md`
- 결론에 따라 ADR(`docs/adr/`) 또는 Phase 2 결론 재확인 메모.
