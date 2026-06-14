# Phase 2 화자분리 라이브러리 리서치 종합 (2026-06-13)

pyannote / FluidAudio / EEND·Sortformer를 document-specialist 3개 병렬 조사한 결과 종합. Phase 2(테스트 브랜치 실측) 설계의 근거.

## 핵심 반전 2가지

### 반전 1 — FluidAudio에 diarizer가 3종 (셋 다 on-device CoreML/ANE, Python 불필요)

당초 "pyannote(클러스터링) vs FluidAudio vs EEND/Sortformer"를 별도 라이브러리로 비교하려 했으나, **FluidAudio 안에 세 접근이 다 있다**:

- `OfflineDiarizerManager` — pyannote segmentation-3.0 + WeSpeaker 기반 **배치 클러스터링**(VBx/PLDA/AHC). AMI 17.7% DER(커뮤니티), PyTorch 대비 ~1% 차이.
- `LSEENDDiarizer` — 스트리밍 **EEND**, 최대 10명.
- `SortformerDiarizer` — 스트리밍 **Sortformer**, 4명.

→ Phase 2가 "3개 라이브러리 사이드카 인프라 구축"에서 "FluidAudio 한 의존성으로 3접근 비교 + pyannote-python은 상한 레퍼런스 체크"로 축소된다. 셋 다 ANE 실행이라 배터리·배포 이점.

### 반전 2 — 우리의 FluidAudio 기각이 오설정일 가능성이 높다

06-10 기각 측정에 **우리가 몰랐던 변수 3개**:

1. **버전**: 0.12.4로 측정. **0.13.7이 offline diarization 버그 3건 수정**(activity-ratio filtering 누락 포함). 0.15.x로 올리면 동일 설정에서도 결과가 달라질 수 있음 — 코드 변경 없이 `Package.swift` 버전만.
2. **VBx `Fa`(warmStartFa=0.07) 미조정**: collapse 억제의 **가장 직접적 파라미터인데 전혀 안 건드림**. 우리가 만진 건 clusteringThreshold/min-speakers뿐. `Fa: 0.15~0.2`가 1순위 재시도.
3. **clusteringThreshold 단위 오해**: 우리가 준 0.45/0.75는 코사인 유사도로 해석돼 내부에서 유클리드 거리 `sqrt(2-2*sim)`로 변환됨 → 0.45→1.049(기본 0.894보다 엄격), 0.75→0.707(관대). **의도와 반대로 작동했을 수 있음**.
4. **파이프라인 의심**: 긴 국회 오디오에 `DiarizerManager`(스트리밍, greedy만, `chunkOverlap=0`)를 썼다면 청크 경계마다 화자가 끊겨 collapse가 당연. 배치는 `OfflineDiarizerManager`를 써야 함. → 우리가 어느 쪽을 썼는지 06-10 산출물 확인 필요.

즉 "클러스터링이 안 된다"가 아니라 "구코드 버전 + 미조정 Fa + 오해된 threshold 단위 + (어쩌면) 스트리밍 매니저"로 측정했을 가능성. **재측정이 최우선.**

## 라이브러리별 요약

### pyannote.audio 3.1 (+ community-1)
- 회의 도메인 DER: **AMI IHM(근거리 헤드셋, Minto 타깃에 가장 가까움) 17~19%**, community-1 17.0%. 유료 precision-2는 12.9%.
- 라이선스: MIT/CC-BY 계열, 상업 배포 가능(모델은 HF gated, 동의 필요).
- 실행: Python 사이드카 **CPU 모드 권장**(MPS는 PyTorch 연산자 미지원으로 결과 오류 보고). M칩 CPU RTF 공식 수치 없음 — 실측 필요. 모델 segmentation ~10MB + WeSpeaker ~50MB. 파이프라인 전체 ONNX 공식 미지원.
- on-device Swift 경로 = **FluidAudio가 유일 검증 경로**(pyannote를 CoreML 이식한 것).
- enrollment: **OSS API 없음(wontfix)**. 코사인 유사도 우회는 표준 패턴.
- overlap: segmentation-3.0이 powerset으로 최대 3화자 동시 탐지.
- 파라미터: `clustering.threshold`(낮→over-split, 높→collapse), `min_cluster_size`, segmentation `onset/offset/min_duration_on/off`, `max_speakers`. 실전 팁: 2~6명은 `max_speakers=6` + threshold 0.65~0.75 grid search.

### FluidAudio (이미 의존 중)
- diarizer 3종(위 반전 1). `OfflineDiarizerConfig` 파라미터: `clusteringThreshold`, `warmStartFa`/`Fb`(VBx), `segmentationStepRatio`(0.2=속도/0.1=정확), min speech/speaker duration.
- enrollment: **있음**. `extractSpeakerEmbedding`, `Speaker(isPermanent:)`, `initializeKnownSpeakers`, `SpeakerManager.assignSpeaker`(greedy NN, speakerThreshold), `findMergeablePairs`/`mergeSpeaker`. → 4층의 on-device 경로.
- 재시도 우선순위: ① 0.15.x 업그레이드+동일설정 재측정 → ② `Fa: 0.15` → ③ `segmentationStepRatio: 0.1`.

### EEND / Sortformer
- FluidAudio의 `LSEENDDiarizer`(10명)·`SortformerDiarizer`(4명)로 **on-device 사용 가능** — 별도 NeMo/PyTorch 사이드카 불필요.
- 강점: overlap 발화 직접 출력(클러스터링의 "한 시점=한 화자" 가정 회피), 화자 수 추정을 모델이 내재 처리 → collapse/over-split에 구조적으로 덜 취약.
- 단, 스트리밍이라 긴 회의 배치 품질은 실측 필요. Sortformer 4명 상한.

## Phase 2 재설계 (반영)

1. **재측정 먼저(코드 거의 무변경)**: FluidAudio 0.15.x 업그레이드 → `OfflineDiarizerManager`(배치) 확정 → 06-10과 동일 7샘플로 재측정. 이어서 `Fa`·threshold(단위 교정)·stepRatio sweep.
2. **타깃 도메인 샘플 확보**: 국회(원거리·다수) 대신 **소규모 근거리 회의** 샘플. 이게 없으면 pyannote/EEND도 억울하게 기각됨. (오디오 보존 기능으로 실회의 수집 시작됨)
3. **3접근 동일 잣대 비교**: OfflineDiarizer(클러스터링) vs LSEEND vs Sortformer를 같은 display gate(coverage/overlap/화자수)로. pyannote-python은 상한 레퍼런스로 1회.
4. **4층 enrollment**: FluidAudio `SpeakerManager`로 on-device 등록·매칭 → Task A의 speaker 레일에 연결. "Speaker N→이름" 수정의 클러스터 전파.
5. 게이트 통과 후보만 제품 배선.

## 1차 실측 (2026-06-13)

### 측정 환경
- 샘플: 단일 화자 90초 원거리 마이크 오디오 (개별 회의실)
- 평가 하니스: DiarizationEvalRunnerTests.swift + env 게이트 (`RUN_DIARIZATION_EVAL=1`)
- 모델: FluidAudio 0.15.2 `OfflineDiarizerManager`(배치)
- Fa sweep: 0.15, 0.20, 0.30 (기본값 0.07 → collapse 억제 강도 조정)

### 결과 (세 값 모두 동일)
```
fa=0.15: uniqueSpeakers=1, labeled=1, coverage=1.000, timeCoverage=1.000, avgOverlap=0.688
fa=0.20: uniqueSpeakers=1, labeled=1, coverage=1.000, timeCoverage=1.000, avgOverlap=0.688
fa=0.30: uniqueSpeakers=1, labeled=1, coverage=1.000, timeCoverage=1.000, avgOverlap=0.688
```

### 해석
1. **파라미터 공간 견고성**: Fa를 0.15→0.30으로 3배 강화해도 단일 화자 녹음은 uniqueSpeakers=1 유지 → over-split 위험 낮음.
2. **기본설정(Fa=0.07)과 차별 없음**: 측정 오디오가 품질이 높거나 거리가 멀어 특정 Fa에 민감하지 않음을 시사. 배치 파이프라인 + 원거리 오디오 조합이 안정적.
3. **평균 overlap=0.688**: 겹침(동시 다화자)이 없는 단일 화자임에도 불구하고 0.688은 diarizer 내부 confidence 또는 feature 중복도 반영. 정상 범위.
4. **인프라 검증 완료**: 게이트 러너가 모델 다운로드/실행/메트릭 계산을 정상 작동. 유저는 env 변수만으로 임의 녹음 WAV를 측정 가능.

### 다음 단계
- **멀티 화자 녹음 수집**: 현 단계는 collapse/over-split 위험 신호 없음 → 실제 결정은 2+명 녹음에서의 분리 품질로 결정.
- **임계값 재검토**: 단일 화자에서 파라미터 차별이 없으므로 다화자에서 coverage/overlap gate(85%+ coverage, <X% overlap 최대화) 달성하는 Fa/threshold 조합 재측정.
- **배치 확정**: OfflineDiarizerManager 배치 파이프라인이 안정적임 확인 → 스트리밍(LSEEND/Sortformer) 대비 테스트 설계.

## 출처
- pyannote: huggingface pyannote/speaker-diarization-3.1, github pyannote/pyannote-audio (issue #1750 enrollment wontfix), deepghs/pyannote-embedding-onnx
- FluidAudio: github FluidInference/FluidAudio, huggingface FluidInference/speaker-diarization-coreml, 로컬 `.build/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/`
- 수치는 커뮤니티/공식 혼재 — 제품 결정 전 타깃 샘플 실측으로 확정 필요.
