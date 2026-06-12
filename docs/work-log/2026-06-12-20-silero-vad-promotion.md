# Silero VAD + 빈 구간 복구 설정 기반 승격 (2026-06-12, #20)

## 배경

experiment/stt-engine-poc 벤치마크(국회 회의 7샘플)에서 Silero VAD는 Energy 대비 weighted CER −10%p, empty final −199개였고, empty repair(pad 1.0s)와 결합하면 short3 기준 empty 75→9로 떨어졌다. 코드는 main에 이미 있었지만 환경변수(`MINTO_VAD_ENGINE`, `MINTO_EMPTY_FINAL_REPAIR`)로만 켤 수 있었고 모델 경로가 `/private/tmp`(휘발성)였다.

계획: `docs/work/2026-06-12-vad-promotion-batching-audio-retention-plan.md` A절.

## 변경

- `VADEnginePreferences`(key `selectedVADEngine`, **기본 silero**) + factory 설정 분기. env는 벤치마크용으로 설정보다 우선 유지.
- `EmptyFinalRepairPolicy.resolve()`: env > 설정 토글(key `emptyFinalRepairEnabled`, **기본 켬**) > 검증 조합 고정값(pad 1.0s/min chunk 2.0s/min audio −35dB).
- 모델 경로 → `~/Library/Application Support/Minto/models/fluidaudio`. `SileroVADModelStore`가 FluidAudio `VadManager`의 자동 다운로드(~1MB)로 준비, `ModelState`로 진행률 노출, 앱 시작 시 백그라운드 prepare. 미준비·실패 시 Energy fail-soft.
- `TranscriptionViewModel`: 녹음 시작마다 `VoiceActivityDetectorFactory.makeNext(current:)`로 설정 재해석 — 같은 엔진이면 인스턴스 재사용(모델 워밍업 유지), 바뀌면 교체. repair 정책은 사용 시점 resolve, 버퍼는 상수 45초 상시 유지.
- 설정 UI "음성 구간 감지": 엔진 선택(Silero 권장/Energy), 모델 상태(다운로드 %/준비됨/실패+재시도), 빈 구간 복구 토글, 변경 onChange 로그. 녹음 시작 시 적용 엔진·repair 여부 `.info` 로그.

## 회의 중 설정 변경 UX (사용자 요청 검토)

- **VAD 엔진**: 상태 파괴적(버퍼·청크) → **다음 녹음부터 적용**, 녹음 중에는 안내 캡션 표시.
- **빈 구간 복구**: 상태 비파괴 → **회의 중 변경 즉시 반영**(사용 시점 정책 해석 + 버퍼 상시 유지).
- 원칙: 즉시 적용 가능 여부는 설정이 상태를 파괴하는지로 갈리고, UI 캡션이 그 차이를 드러낸다.

## 리뷰 (opus critic) 및 반영

ACCEPT-WITH-RESERVATIONS, Critical 0 / Major 2.

- **M2 반영**: 녹음마다 VAD 재생성 → 워밍업된 Silero 모델 폐기(첫 청크 지연). `makeNext(current:)`로 같은 엔진이면 재사용.
- **M1 반영**: 모델 다운로드 진행 콜백(백그라운드 스레드)의 상태 갱신 Task에 `[weak self]` 명시.
- Open question(기록): 오프라인에서 VadManager init의 네트워크 타임아웃 길이(다운로드 상태가 길게 유지될 수 있음 — UI는 비블로킹), FluidAudio가 같은 모델 디렉터리 로드를 내부 캐싱하는지.

## 검증

- `./scripts/dev.sh build`/`test` — 전체 473개(69 suites) 통과. 신규 15개(설정/팩토리/resolve/재생성/makeNext).
- 관찰: `MeetingSearchAnswerServiceTests`의 "같은 검색어 재생성 중..." 테스트가 병렬 실행에서 1회 flaky(단독 통과) — 이번 변경과 무관한 기존 타이밍 레이스, 후속 점검 대상.

## 동작 변화 (사용자 영향)

- 첫 실행 시 Silero 모델(~1MB) 자동 다운로드 → 준비 전 녹음은 Energy로 동작, 준비 후 다음 녹음부터 Silero.
- empty repair 기본 켬 → 녹음 종료 시 빈 구간 재시도로 STT 호출이 소폭 증가(벤치마크상 empty 대폭 감소와 교환).
