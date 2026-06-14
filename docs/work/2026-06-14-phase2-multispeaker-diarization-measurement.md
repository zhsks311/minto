# Phase 2 다화자 Diarization 측정 결과 (Fa/threshold 스윕 + exactSpeakerCount)

작성일: 2026-06-14
엔진: FluidAudio 0.15.2 offline diarizer (VBx 클러스터링), Apple M3 Pro / CoreML(ANE)
평가 러너: `DiarizationEvalRunnerTests` (`RUN_DIARIZATION_EVAL=1` 게이트)

## 목표

저장/임포트된 회의 오디오에서 FluidAudio offline diarizer의 화자 수가
파라미터(warm-start Fa, clustering threshold, exactSpeakerCount)에 어떻게
반응하는지 측정하고, 다화자 회의에서 신뢰할 수 있는 제어 방법을 찾는다.

## 대상 코퍼스

| 녹음 | 길이 | 추정 화자 | 비고 |
|------|------|-----------|------|
| 4인 토론 (`4people.wav`) | 30:53 | 4 | 토론, ~90kbps 원본 |
| 5/6인 토론 (`5people.wav`) | 23:22 | 5~6 (불확실) | 선거 토론, ~75kbps, 무음 구간 0 |
| 국회 행안위 (`haengan_20260526_full.wav`) | 2:02:58 | 대규모 위원회 | 16kHz mono |

> 주의: 모든 화자 수 ground-truth는 파일명/맥락 기반 추정이며, 시간동기 전사
> 정답은 없다. "정답 화자 수"는 스윕에서 **가장 넓은 안정 평탄구간**으로 추정.

## 측정 결과

### 1. 기본 설정은 다화자를 심각하게 under-count

기본값 `Fa=0.07, threshold=0.6`에서:
- 4인 → 2명
- 5/6인 → 2명
- 행안위(대규모) → 4명

제품 기본 설정은 다화자 회의를 일관되게 과소 계수한다.

### 2. warm-start Fa 스윕 (threshold=0.6 고정)

| Fa | 4인 | 5/6인 | 행안위 |
|----|-----|-------|--------|
| 0.07 | 2 | 2 | 4 |
| 0.15 | 3 | 2 | — |
| 0.30 | 3 | 2 | 12 |
| 0.35–0.50 | **4 (안정)** | 2 | 13 |
| 0.50 | 4 | 2 | 13 |
| 0.70 | 6 | 2 | 14 |
| ≥1.0 | 6→7 | 2 | — |

- 4인: Fa↑ → 화자↑ 단조. **4가 Fa∈[0.35,0.50]에서 안정 평탄구간**.
- 5/6인: **Fa에 완전 둔감**(전 구간 2 고정). threshold가 지배.
- 행안위: Fa↑ → 화자↑ 단조(4→14).

### 3. clustering threshold 스윕 (Fa=0.07 고정)

| threshold | 4인 | 5/6인 |
|-----------|-----|-------|
| 0.30–0.50 | 1 | 1 |
| 0.60 (기본) | 2 | 2 |
| 0.65–0.90 | 2 | **6 (안정, 최광)** |
| 0.95 | 2 | 5 (단일 전환점) |
| 1.00–1.40 | 2 | 4 (안정) |

- 4인: threshold 거의 무력(1↔2). Fa가 레버.
- 5/6인: threshold가 레버. **6이 th∈[0.65,0.90]에서 가장 넓은 평탄구간** → 추정 정답 6.
- 응답이 **비단조**(1→2→6→4)이며 segment 수도 출렁(85/91/120/115) → VBx warm-start가 threshold마다 다른 국소최적으로 수렴.

### 4. 2D 스윕 (Fa × threshold, 값=화자 수)

4인:
```
th\Fa  0.07  0.30  0.50  0.70
0.50    1     2     3     4
0.60    2     3    [4]    6
0.70    2     3    [4]    6
0.90    5     8    13    16
1.10    4     7    13    21
```
5/6인:
```
th\Fa  0.07  0.30  0.50  0.70
0.50    1     1     1     1
0.60    2     2     2     2
0.70   [6]   [6]    8     8
0.90    6     6    14    23
1.10    4     6    13    24
```
- **th≥0.9는 전부 과분할 폭발**(13~24명) → 사용 불가 영역.
- 의미 있는 구간은 th∈[0.6,0.7]. 각 녹음의 추정 정답이 다른 (th,Fa) 좌표:
  4인 = th0.6~0.7 × Fa0.5 → 4; 6인 = th0.7 × Fa0.07~0.3 → 6.
- **단일 (Fa, threshold)로 두 녹음 정답을 동시에 맞출 수 없음**이 2D로 확정.

### 5. exactSpeakerCount 강제 (기본 Fa/threshold)

| exactN | 4인 | 5/6인 | 행안위 |
|--------|-----|-------|--------|
| 2~6 | 정확히 N | 정확히 N | — |
| 5/10/15/20 | — | — | **정확히 N** |
| 7 | **2 (폴백)** | 7 | — |

- exactSpeakerCount는 기본 파라미터에서 **정확히 N 화자**를 산출(오디오 용량 내).
- **용량 천장 = 실제 화자 다양성에 비례**: 4인은 N=7서 폴백(2로 붕괴), 6인은 7까지, 행안위는 20까지 깔끔.

## 결론

1. **Fa/threshold 튜닝은 막다른 길.** 작동 레버가 녹음마다 다르고(4인=Fa, 6인=threshold),
   응답이 비단조이며, th≥0.9는 과분할 폭발. 런타임에 "어느 레버·어느 값"인지 알 수 없다.
2. **추정 정답 = 파라미터 스윕의 최광 안정 평탄구간** (기본 설정값이 아님). 4인→4, 6인→6.
3. **exactSpeakerCount가 견고한 제어 경로.** 사용자가 회의 인원을 입력하면 결정적으로
   N 화자를 산출. 소규모 토론~대규모 위원회(N=20)까지 일관 작동.

## 제품 권고

- 회의 시작/임포트 시 **사용자가 예상 참석 인원을 입력 → `exactSpeakerCount`로 고정**.
  사용자는 자기 회의 인원을 알고, 입력 마찰이 낮으며, 결과가 결정적.
- 인원 미입력 시 폴백: 기본 파라미터(현재 under-count) 또는 향후 "2D 스윕 후
  최광 평탄구간 자동 선택" 알고리즘.
- 1차 배선은 **파일 임포트 경로**(오프라인 파일 = 오프라인 diarizer와 정합).
  브랜치 `feat/diarization-import-speaker-labels`에 구현, 라이브 QA 후 main 반영.

## 재현 명령

```sh
cd minto2-wt-diar-eval
WAV="$PWD/sample/toron-4/4people.wav"   # 또는 다른 WAV 절대경로
# Fa 스윕
RUN_DIARIZATION_EVAL=1 DIARIZATION_EVAL_WAV="$WAV" \
  DIARIZATION_CLUSTERING_THRESHOLD=0.60 DIARIZATION_WARMSTART_FA=0.50 \
  swift test --skip-build --filter DiarizationEvalRunnerTests
# 화자 수 강제
RUN_DIARIZATION_EVAL=1 DIARIZATION_EVAL_WAV="$WAV" \
  DIARIZATION_EXACT_SPEAKER_COUNT=4 \
  swift test --skip-build --filter DiarizationEvalRunnerTests
```
출력: `[DIAR-EVAL] fa=.. threshold=.. exactN=.. minN=.. maxN=.. diarizedSegments=.. uniqueSpeakers=..`

> mp3 → 16kHz mono WAV: `ffmpeg -y -i in.mp3 -vn -ar 16000 -ac 1 out.wav`
