# 라이브/저장 전사 화자 라벨 누락 수정 계획

## 문제

`선관위 부실 관리 원인과 선거 신뢰 회복 과제` 회의의 전사 일부 줄에서 화자 라벨이 비어 보인다.

- 저장 JSON 확인 결과 `transcript` 13개 중 2개 segment의 `speaker`가 비어 있다.
- 누락 segment는 30초 단위 chunk다.
- `TranscriptSpeakerMatcher` 기본 기준은 전사 segment duration의 50% 이상 diarization segment와 겹쳐야 한다.
- 긴 전사 chunk에는 침묵과 pause가 포함되므로, 실제 speech diarization 구간이 50% 미만이어도 정상 발화일 수 있다.

## 수정 방향

1. 라이브 표시와 저장 finalize 경로의 matcher는 낮은 speech overlap도 라벨 후보로 인정한다.
2. matcher가 새 라벨을 못 찾은 경우 기존 live label을 `nil`로 덮어쓰지 않는다.
3. matcher의 기본 동작은 유지해 import/eval 경로의 기존 의미를 건드리지 않는다.

## 검증 기준

- [x] sparse speech overlap이어도 live committed segment에 화자 라벨이 붙는다.
- [x] 이후 snapshot이 비어도 기존 live 화자 라벨을 지우지 않는다.
- [x] 저장 finalize에서 VBx가 라벨을 못 붙인 segment는 기존 live label을 유지한다.
- [x] `./scripts/dev.sh test TranscriptionViewModelLiveSpeakerTests`
- [x] `./scripts/dev.sh test LiveDiarizationFinalizeUseCaseTests`
- [x] `./scripts/dev.sh build`
