# 녹음 오디오 보존 (화자분리 1단계) (2026-06-12, #21)

## 배경

화자분리(사후 diarization)·재전사·구간 듣기의 공통 전제는 원본 오디오인데, 기존에는 녹음 PCM이 전사 후 버려져 사후 처리가 불가능했다. 화자분리 설계(사후 확정 + 실시간 잠정)의 1단계로 보존 계층을 깐다.

계획: `docs/work/2026-06-12-vad-promotion-batching-audio-retention-plan.md` C절.

## 변경

- `RecordingAudioArchiver`: 녹음 중 마이크 샘플(16kHz mono)을 `Application Support/Minto/recordings/<uuid>.wav`로 스트리밍 기록(전용 utility 큐, 16bit PCM). 실패는 fail-soft — 첫 실패 후 쓰기 중단, `.error` 로그만. 빈 파일은 남기지 않음.
- `MeetingRecord.audioFileName: String?`: optional이라 기존 JSON 하위 호환(레거시 디코드 테스트 고정). `MeetingRecordFactory`/`AppDelegate.makeRecord` 전달 경로.
- `TranscriptionViewModel`: 설정이 켜져 있으면 녹음 시작 시 아카이버 생성, onBuffer에서 append, drain 시 `finish()`로 파일명 확정(`lastArchivedAudioFileName`). 테스트 기본은 비보존(factory 미주입).
- 수명 관리: 회의 삭제 시 오디오 동반 삭제(`MeetingStore.delete`), 빈 회의(skippedEmpty)는 즉시 정리, 보관 기간(기본 30일, 7/30/90 선택) 경과분은 앱 시작 시 정리(`cleanupExpired`, 삭제 건수 로그).
- 설정 UI "녹음 오디오": 보관 토글(기본 켬) + 기간 Picker. 문구로 "이 Mac에만 저장, 외부 전송 없음" 명시. onChange 로그.

## 기본값 결정 근거

- 기본 켬: 화자분리 등 후속 기능의 전제라 꺼져 있으면 기능이 시작부터 막힌다. 프라이버시는 ① 로컬 전용 명시, ② 끔 토글, ③ 보관 기간 자동 정리로 담보.
- 보관 기간이 지나 파일이 지워져도 회의록 텍스트는 그대로다(`audioFileName`은 dangling 가능 — 후속 diarizer는 파일 부재를 graceful 처리해야 함).

## 검증

- `./scripts/dev.sh test` 전체 481개(72 suites) 통과 — 신규 8개(아카이버 기록/빈 파일/기간 정리/파일명 삭제 경로 안전/설정 기본값/스키마 하위 호환/왕복/뷰모델 통합).
- SettingsView body 타입체크 타임아웃 발생 → onChange를 Form 체인이 아닌 섹션 내부로 이동해 해결(추후 섹션 추가 시 같은 패턴 권장).

## 남은 것 (화자분리 다음 단계)

- 사후 diarization 패스(pyannote 사이드카 벤치마크 → display gate 비교), 단어 타임스탬프 정렬, "알 수 없음" 라벨 + 클러스터 단위 수정 UI, 임포트 오디오 보존(diarizer 연결 시 결정).
