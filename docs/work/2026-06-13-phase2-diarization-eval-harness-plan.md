# Phase 2 화자분리 평가 하니스 계획

작성일: 2026-06-13

## 목표

저장된 회의 WAV를 대상으로 FluidAudio offline diarizer를 명시적으로 실행하고,
결과를 기존 `Segment.speaker` 레일에 사후 매칭하는 평가용 하니스를 만든다.
제품 기본 녹음/저장/전사/임포트 경로에는 배선하지 않는다.

## 범위

- `SpeakerDiarizationProvider` 인터페이스와 FluidAudio offline 구현 추가.
- diarization timeline과 transcript segment를 overlap 기반으로 매칭.
- 품질 확인용 metric 계산과 `RUN_DIARIZATION_EVAL=1` 게이트 테스트 추가.
- 작업 로그에 사용법과 평가용 미배선 상태 기록.

## 제외

- 제품 UI/저장 흐름 자동 배선.
- LSEEND/Sortformer 실제 구현.
- 단어 단위 speaker 정렬.
- 모델 디렉터리 강제 변경 또는 dependency 버전 변경.

## 단계별 검증 기준

1. Provider 구현
   - verify: `./scripts/dev.sh build`
   - success: FluidAudio 0.15.2 offline manager로 컴파일되고 제품 경로 변경 없음.

2. Transcript matcher
   - verify: `./scripts/dev.sh test TranscriptSpeakerMatcherTests`
   - success: 단일 화자, 2화자 교대, 겹침 부족, 동률, 안정 번호 테스트 통과.

3. Metric + gate runner
   - verify: `./scripts/dev.sh test Diarization`
   - success: env가 없으면 실제 모델 실행 없이 skip, matcher/metric 테스트는 통과.

4. 작업 로그
   - verify: `git diff --check`, `./scripts/dev.sh build`, `./scripts/dev.sh test`
   - success: 전체 테스트 통과, 4개 커밋 생성, push 없음.

## 진행 상태

- [x] 기준 빌드 통과: `./scripts/dev.sh build`
- [x] 커밋 1: provider 인터페이스 + FluidAudio offline 구현
- [x] 커밋 2: transcript matcher + 단위 테스트
- [x] 커밋 3: quality metrics + env gate runner
- [x] 커밋 4: work-log + index
