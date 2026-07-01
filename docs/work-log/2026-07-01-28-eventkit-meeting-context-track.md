# 2026-07-01 · 28 · 회의 전후 EventKit 트랙 (캘린더·미리알림·발화 분석)

## 배경

경쟁 제품(Granola/Otter/Fireflies/Jamie/Alter) 대비 공백 조사에서 "회의 전후 워크플로우"가 비어 있음을 확인. 계획을 ralplan 합의(Planner→Architect→Critic APPROVE)로 수렴한 뒤 병렬 Wave로 구현했다.

- 계획: `docs/work/2026-06-29-meeting-context-eventkit-track-plan.md`
- ADR: `docs/adr/0008-eventkit-calendar-reminders.md` (Accepted)
- Pencil: `Resources/designs/meeting-setup-calendar-prefill.{pen,png}`, `pending-action-items.{pen,png}`

## 구현 (Phase / 커밋)

- **P0 발화 분석** (`d27ce7a`): `TalkTimeAnalyzer`(Domain 순수 함수) + `MeetingSummaryView` 화자별 발화 카드. 화자 미상은 "알 수 없음" 별도 집계.
- **공유 스캐폴딩** (`c474c11`): `Log.calendar`/`Log.reminders` + Info.plist `NSCalendarsUsageDescription`/`NSRemindersUsageDescription`. P1·P4 병렬 구현의 공유 파일 충돌 선제거.
- **P1 CalendarService** (`9796273`): `actor CalendarService`(EventKit, 자체 `EKEventStore`) + `CalendarServiceStub`. 권한 거부/오류는 빈 배열 fail-soft.
- **P3 매칭 식별자** (`ad0f9de`): `MeetingRecord.calendarEventIdentifier` backward-compatible optional + `MeetingContext`~`MeetingRecordFactory` nil-safe 전달 경로. 공백은 nil 정규화.
- **P4 미리알림/isDone** (`aa54771`): `ActionItem.isDone`(lenient decode), `actor RemindersService`, `ActionItemReminderUseCase`(빈 task 제외·due lenient 파싱·권한 거부 fail-soft). 단방향 push.
- **P2 캘린더 프리필** (`2bd90a0`): `CalendarPrefillUseCase`(±window 최근접) + `MeetingSetupView` 프리필 섹션(권한없음/이벤트없음/발견/수락/무시). 수락 시 빈 주제만 채우고 event identifier를 저장 경로로 전달.
- **P5 미완료 할일 뷰** (`ae898bb`): `PendingActionItemsUseCase`(순수 변환) + `PendingActionItemsView`(empty/loading/items/disabled, 읽기 전용) + `MeetingLibraryView` 진입점.

## 리뷰 (크로스모델)

- P0 code-reviewer COMMENT: 정규화 이중구현은 Domain↔UI 경계상 의도적(주석 명시), tie-break 테스트·조사 회피·ForEach id 반영.
- P1 COMMENT: interval ≤ 0 fail-soft 가드 추가.
- P3 COMMENT: `calendarEventIdentifier` 공백 정규화 추가.
- P4 COMMENT: 빈 task 내보내기 제외, `RemindersServiceStub` 접근 범위 축소(internal).
- **P2 REQUEST CHANGES**: `±window`의 과거 절반이 UI 경로에서 누락(이미 시작한 회의 미프리필). `CalendarServiceProtocol.events(around:window:)` 추가로 `now-window...now+window` 조회하도록 수정 후 재검증.
- P5 COMMENT: 읽기 전용인데 체크박스가 토글로 오인 → "미완료" 배지로 교체, empty 문구를 "미완료 할일이 없어요"로 정정.

## 검증

- 통합 브랜치 `feat/meeting-eventkit-track`
- `git diff --check` 통과
- `swift build --disable-sandbox --scratch-path /tmp/minto2-eventkit-final` 통과
- 관련 테스트 31 tests / 7 suites 통과
- **전체 `swift test` 809 tests / 119 suites 통과**

## 제약 / 원칙 준수

- 새 외부 SPM 의존성 0 (EventKit은 macOS 네이티브).
- schema 변경(`calendarEventIdentifier`, `isDone`) 모두 additive optional → `schemaVersion` bump 없음, 기존 JSON 비파괴.
- 로그에 일정 제목·참석자·할 일 원문 금지(count/status/bool만).
- 아키텍처: 신규 UseCase는 기존 패턴대로 `Services/` 배치(`Application/` 신설 안 함 → 경계 변경 ADR 불필요).

## 남은 과제

- [ ] EventKit 권한 팝업·프리필·미리알림 내보내기 실제 앱 GUI QA (`./scripts/dev.sh run`, 헤드리스 불가)
- [ ] 캘린더 매칭 오탐률 측정 후 window 상수 조정 (ADR 0008 Follow-up)
- [ ] EKReminder 완료 ↔ 앱 `isDone` 양방향 동기화 여부 별도 검토
