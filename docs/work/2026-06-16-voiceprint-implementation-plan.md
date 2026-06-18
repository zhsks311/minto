# 보이스프린트(반복 참석자 화자 식별) 풀 구현 계획 — Phase 3

작성일: 2026-06-16
근거: PoC 2단계 GREEN — 변별력 gap 0.40~0.47, 등록→식별 정확도 1.00(intra-recording), θ=0.65 reject 5.2%. (브랜치 feat/voiceprint-poc, 커밋 e3c77fa·dfa932c)

## 한 줄 요약
화자 임베딩 모델(`Embedding.mlmodelc`, 이미 사용 중)로 사람별 보이스프린트(임베딩 centroid)를 등록·저장하고, 임포트 diarization 후 각 화자 클러스터를 등록 템플릿과 cosine 매칭해 **실명**을 부여한다.

## 의존성 / 기반
- `diarizeWithEmbeddings`(PoC에서 추가, feat/voiceprint-poc)를 제품 코드로 가져와야 함. main엔 base diarization(provider/matcher/quality)은 있으나 이 메서드는 없음.
- 임베딩 모델 = 화자분리와 공유(`Embedding.mlmodelc`). 새 ML 모델 0.

## ⚠️ 핵심 안전장치 — 임베딩 모델 버전 태그
보이스프린트는 임베딩 모델의 좌표 공간에 종속. 모델 교체 시 저장값 무효.
- 각 보이스프린트에 `embeddingModelID`(+ `dimensions`) 저장.
- 매칭 시 현재 모델 ID ≠ 저장 ID면 매칭 제외(미등록 취급) + 재등록 안내.
- (검색 임베딩 인덱스의 modelID/schemaVersion 패턴과 동일.)

## 컴포넌트 & 순서 (각각 Codex 구현 → 빌드 → Opus 리뷰 → QA)

### C1. 데이터 모델 + 스토어 (S, 기반)
- `Voiceprint { id, displayName, embedding: [Float], embeddingModelID, dimensions, enrolledAt, sampleCount }` (Codable).
- `VoiceprintStore`: 로컬 JSON(~/Library/Application Support/Minto/voiceprints/), CRUD + 삭제 + 모델ID 불일치 필터. schemaVersion.
- 순수 로직(매칭: 임베딩 → 최근접 보이스프린트, θ) 분리 + 단위 테스트.

### C2. 임베딩 추출 통로 정리 (S)
- PoC `diarizeWithEmbeddings`를 제품용으로 정리(이 브랜치에 포함). 클러스터별 centroid 임베딩 추출 헬퍼.

### C3. 등록(enrollment) (M)
- 등록 방법 2안: (a) 기존 회의에서 한 화자 구간을 골라 그 임베딩 평균을 이름과 저장(데이터 재활용, 마이크 불필요) — 권장 1차. (b) 짧은 음성 녹음 → 임베딩. 
- UX: 설정 또는 별도 "화자 등록" 화면. 이름 입력 + 샘플 선택.

### C4. 식별 통합 (M)
- importFile diarization 후: 각 화자 클러스터 centroid를 VoiceprintStore와 매칭(θ=0.65, 모델ID 일치). 매칭되면 Segment.speaker를 실명으로, 아니면 기존 "화자 N"/auto 라벨 유지.
- 교정 UX(이름변경·병합·재배정)와 공존 — 자동 식별이 틀려도 사람이 수정.

### C5. 프라이버시 (S)
- 보이스프린트 로컬 저장만, 삭제 수단(설정에서 목록·삭제). 음성 원본 미저장(임베딩만).

## 순서
C1 → C2 → C3 → C4 → C5. C1·C2는 기반(테스트 가능). C3·C4가 사용자 가치. 각 단계 QA 브랜치.

## 브랜치
main(87e7841, diarization 머지됨) 기준 신규 `feat/voiceprint`. C2에서 feat/voiceprint-poc의 diarizeWithEmbeddings를 cherry-pick/이식.

## 검증 / 한계
- 단위: 매칭 로직·스토어·모델ID 불일치 처리.
- 측정: PoC는 intra-recording 100%. **크로스-세션(다른 날/마이크) 정확도는 실사용에서 θ 튜닝하며 확인** — 같은 사람 별도 녹음 확보 시 평가 하니스로 측정.
- 라이브 mic 경로는 오프라인 diarization 없어 별개(임포트 경로부터).

## 수락 기준
- C1: 스토어 CRUD + 모델ID 불일치 필터 단위 테스트.
- C3: 회의 한 화자 → 이름 등록 → 스토어에 저장 확인.
- C4: 등록된 사람이 임포트에서 실명으로 라벨됨(QA). 미등록은 기존 동작.
