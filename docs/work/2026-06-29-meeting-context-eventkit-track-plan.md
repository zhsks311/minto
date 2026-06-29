# 회의 전후 + EventKit 트랙 구현 계획

작성일: 2026-06-29
관련 ADR: `docs/adr/0008-eventkit-calendar-reminders.md` (예정)

---

## 0. 브랜치 / 착수 순서

| 브랜치 | 포함 범위 | 착수 조건 |
|--------|-----------|-----------|
| `feat/talk-time-analyzer` | Phase 0 (발화 분석) | 즉시 착수. EventKit·ADR 무관. 독립 출시 가능. |
| `feat/meeting-eventkit-track` | Phase 1~5 (EventKit 전체 트랙) | ADR 0008 Accepted 후 착수. |

Phase 0은 EventKit 트랙과 완전히 독립적이므로 `feat/talk-time-analyzer` 브랜치에서 먼저 진행한다. EventKit 트랙(Phase 1~5)은 ADR 리뷰 완료를 확인한 뒤 별도 브랜치에서 시작한다.

---

## 1. 개요 / 목표

| 기능 | 가치 |
|------|------|
| **① 캘린더 연동 (EventKit)** | 다가오는 회의를 자동 감지해 제목·참석자·시각을 회의 시작 시 프리필하고, 저장된 회의와 캘린더 일정을 매칭한다. |
| **② 할일 → 미리알림 내보내기 + 완료 추적 + 미결 할일 뷰** | 요약의 ActionItem을 macOS 미리알림으로 push하고, 앱 안에서 완료 상태를 추적하며, 여러 회의에 걸친 미결 할일을 모아 본다. |
| **③ Talk-time / 발화 분석** | 기존 화자분리 세그먼트(`DiarizedSpeakerSegment`) 타임스탬프를 집계해 화자별 발화시간·비율을 회의 상세에 표시한다. |

세 기능 모두 **새 외부 의존성 0**, **온디바이스 처리**, **기존 회의 JSON 비파괴**를 공통 제약으로 갖는다.

---

## 2. RALPLAN-DR 요약

### Principles

1. **온디바이스·프라이버시 우선**: EventKit은 로컬 캘린더 DB만 접근. 참석자 이름·일정 제목은 로그에 남기지 않는다.
2. **fail-soft**: 권한 거부·캘린더 없음·이름 충돌 시 기능 비활성화. 녹음·전사·저장을 방해하지 않는다.
3. **schema backward-compat**: 새 필드는 모두 `Optional` + `decodeIfPresent`. 기존 JSON은 nil로 로드.
4. **아키텍처 경계 준수**: Domain은 IO 없는 순수 함수. Application이 workflow·매칭·push를 소유. Infrastructure(EventKit 어댑터)는 Domain/Application에 의존 역전.
5. **점진적 커밋**: 기능변경과 리팩터링을 같은 커밋에 섞지 않는다.

### Decision Drivers

1. **개인정보 범위 확장**: 캘린더 + 미리알림 접근 권한이 신규 추가된다 → ADR·Pre-mortem 필수.
2. **기존 저장 데이터 비파괴**: `MeetingRecord` JSON 역직렬화가 깨지면 전체 회의 목록이 소실된다.
3. **EventKit 권한 런타임 요청의 UX**: 권한 거부 시 기능만 숨기고 앱 흐름은 유지해야 한다.

### Viable Options (핵심 결정별)

#### 결정 A: 캘린더 연동 — EventKit 자동 감지 vs 수동 입력 유지

| | EventKit 자동 감지 | 수동 입력 유지 |
|--|--|--|
| 장점 | 마찰 0. 제목·시각·참석자 자동 프리필. | 권한 불필요. 복잡도 0. |
| 단점 | 권한 요청 UX 추가. 캘린더 없으면 무력. | 사용자가 매번 직접 입력. |
| 선택 | **EventKit 자동 감지** — 단, 권한 거부 시 기존 수동 입력 폼을 그대로 유지(fail-soft). |

#### 결정 B: 할일 내보내기 — EKReminder vs 자체 Task 모델

| | EKReminder | 자체 Task 모델 (앱 내부) |
|--|--|--|
| 장점 | macOS 미리알림과 통합. 시스템 알림 활용. | 의존성 0. 권한 불필요. |
| 단점 | 권한 필요. EKReminder는 별도 권한(reminders). | 다른 앱/시스템과 단절. 검색·알림 직접 구현 필요. |
| 선택 | **EKReminder** — 이미 EventKit을 캘린더로 도입한 이상 동일 프레임워크 추가 비용이 작음. 단, EKReminder 권한은 캘린더 권한과 독립. 권한 거부 시 내보내기 버튼만 숨긴다. |

#### 결정 C: 발화 분석 — Domain 순수 함수 vs ViewModel 직접 집계

| | Domain 순수 함수 | ViewModel 직접 집계 |
|--|--|--|
| 장점 | 테스트 용이. 경계 명확. | 추가 파일 0. |
| 단점 | 파일 1개 추가. | 테스트 어려움. ViewModel 비대화. |
| 선택 | **Domain 순수 함수** — `SpeakerTalkTime` 값 타입 + `TalkTimeAnalyzer.analyze(segments:)` 정적 함수. `Segment.duration`(TimeInterval) 합산만으로 충분하며 meetingStart는 불필요. ViewModel에서 `Segment.speaker` + `Segment.duration` 집계를 직접 하지 않는다. nil speaker는 **"알 수 없음"으로 별도 집계**한다(정책 확정). |

#### 결정 D: 캘린더 ↔ 회의 매칭 식별자 저장 — MeetingRecord에 옵셔널 필드 추가

- `calendarEventIdentifier: String?` — `EKEvent.calendarItemIdentifier` (영속 ID). `decodeIfPresent`. 기존 JSON nil 로드.
- 대안(외부 매핑 테이블): 별도 파일 관리 비용 큼. 단일 레코드 내 자급자족이 단순하다.

---

## 3. Pre-mortem (3 시나리오)

### 시나리오 1: 권한 거부로 기능 전체 비활성 → 오히려 앱 UX가 나빠짐

**실패 형태**: 사용자가 캘린더·미리알림 권한을 모두 거부했을 때, 프리필·미리알림 내보내기가 사라지는 건 맞지만 "왜 아무것도 안 되느냐"는 혼란이 발생.

**완화책**:
- `MeetingSetupView`에 프리필 섹션을 권한 상태에 따라 `"캘린더 권한이 없어요 — 설정에서 허용하세요"` 배너로 대체 (기존 수동 입력 폼은 그대로 노출).
- 미리알림 내보내기 버튼은 권한 거부 시 숨김(disabled + 툴팁). 삭제 아님.
- 권한 요청은 기능 진입 시점(캘린더 섹션 처음 표시 시, 내보내기 버튼 첫 탭 시)에 지연 요청 — 앱 시작 시 선제 팝업 금지.

### 시나리오 2: 캘린더 매칭 오탐으로 엉뚱한 일정 제목이 프리필됨

**실패 형태**: 회의 시작 시각 ±30분 창 안에 일정이 여러 개 있을 때 잘못된 일정이 프리필되거나, 시각이 크게 틀린 일정이 매칭됨.

**완화책**:
- 매칭 창은 ±15분(조정 가능 상수). 복수 일정이면 가장 가까운 일정 1개만 제안하되, "이 일정이 맞나요?" 확인 UI를 거쳐 사용자가 수락/거부.
- 프리필은 덮어쓰기가 아니라 빈 필드에만 채움(사용자가 이미 입력한 내용 보호).
- 매칭 실패·거부 시 기존 빈 폼 유지. 오류 없음.

### 시나리오 3: `ActionItem.isDone` 추가 후 기존 저장 JSON 역직렬화 실패

**실패 형태**: 새 필드를 `Bool`(non-optional)로 추가하면 `CodingKeys`에 해당 키가 없는 기존 JSON에서 `throw`가 발생하고 회의 로드 실패.

**완화책**:
- `isDone: Bool` 대신 `isDone: Bool?`(초기) — `decodeIfPresent`로 기존 JSON은 nil → `false` 처리.
- 또는 `ActionItem.init(from:)`에서 `(try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false` 패턴 적용(기존 lenient 디코딩 스타일, `MeetingSummary.swift:51-57` 참조).
- `MeetingRecord`의 `calendarEventIdentifier`도 동일하게 `decodeIfPresent`.
- 통합 테스트: 필드 없는 JSON fixture를 로드해 nil/false 기본값 확인.

---

## 4. Phase 분해

> 각 Phase는 독립 커밋. 기능변경·리팩터링 혼합 금지. 다음 Phase는 이전 Phase 검증 통과 후.

### Phase 0 — 발화 분석 (독립, 의존성 최소)

**범위**: `Segment.speaker` + `Segment.duration` 기반 화자별 발화시간 집계. EventKit 무관.

**새 파일**:
- `Sources/Minto/Models/TalkTimeAnalyzer.swift` (Domain — IO 없음)
  - `struct SpeakerTalkTime: Equatable { speakerLabel: String; seconds: TimeInterval; ratio: Double }`
  - `static func analyze(segments: [Segment]) -> [SpeakerTalkTime]` — `Segment.duration` 합산. meetingStart 파라미터 없음.
  - `speaker == nil`인 Segment는 **"알 수 없음"(정책 확정)** 라벨로 별도 집계한다. 단위 테스트 기대값도 이 정책 기준.

**변경 파일**:
- `Sources/Minto/UI/MeetingSummaryView.swift` — `resultView` 안에 화자 발화 카드 추가. `DiarizedSpeakerSegment`가 아닌 `Segment.speaker` + `Segment.duration`으로 집계 (`Meeting.swift:20-22` 기준).
  - 상태: 화자분리 데이터 없음(speaker nil) → 섹션 숨김. 화자 1명 → 표시하되 비율 의미 없음 안내.
- `Sources/Minto/Services/Log.swift` — `calendar`, `reminders` 카테고리 추가 (Phase 1 선행 준비).

**검증**:
- `swift test --filter TalkTimeAnalyzerTests` — 0명·1명·다화자·nil speaker("알 수 없음" 집계 확인)·0초 세그먼트·ratio 합산=1.0 픽스처.
- `./scripts/dev.sh run`: 화자분리 결과 있는 회의 상세에서 발화 카드 표시.
- 화자분리 없는 회의 → 카드 숨김.

### Phase 1 — EventKit 인프라 + 권한 관리 (EventKit 첫 진입, ADR 0008 필요)

**범위**: `CalendarService` 어댑터 구현. 권한 요청·상태 관리. Info.plist 추가.

**전제**: ADR 0008 Accepted 확인 후 착수.

**새 파일**:
- `Sources/Minto/Services/CalendarService.swift` (Infrastructure)
  - `protocol CalendarServiceProtocol: Sendable { func requestAccess() async -> Bool; func upcomingEvents(within: TimeInterval) async -> [CalendarEvent] }`
  - `struct CalendarEvent: Sendable { identifier: String; title: String; startDate: Date; endDate: Date; attendeeNames: [String] }`
  - `actor CalendarService: CalendarServiceProtocol` — Swift 6 strict concurrency 대응: `CalendarService`를 `actor`로 설계해 `EKEventStore` 접근을 단일 격리에 둔다. `swift build`에서 Sendable 경고 0건을 검증 항목으로 둔다. **CalendarService는 자체 `EKEventStore` 인스턴스를 소유한다**(RemindersService와 store 공유 없음 — 권한 타입 독립·생명주기 결합 회피).
  - `final class CalendarServiceStub: CalendarServiceProtocol` — 테스트용 주입 가능 stub.

**변경 파일**:
- `Minto.entitlements` 또는 Info.plist — `NSCalendarsUsageDescription` 추가.
- `Sources/Minto/Services/Log.swift` — `calendar` 카테고리 확인(Phase 0에서 추가했으면 스킵).

**로그**: `Log.calendar.info("calendar access granted=\(...)")`, 실패 `.error`.

**검증**:
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build` 통과. Sendable 경고 0건.
- `./scripts/dev.sh run`: 권한 팝업 표시 확인.
- 권한 거부 시 `upcomingEvents` 빈 배열 반환(throw 아님) 확인.
- stub 주입으로 EventKit 없이 단위 테스트 가능 확인.

### Phase 2 — 캘린더 프리필 (MeetingSetupView 통합)

**범위**: 회의 시작 시트에 "다음 일정" 섹션 추가. 캘린더 ↔ MeetingContext 연결.

**변경 파일**:
- `Sources/Minto/UI/MeetingSetupView.swift`
  - `onStart` 시그니처에 `String?`(eventIdentifier) 파라미터 추가: `(String, String, String, AudioInputMode, String?) -> Void` — 캘린더 이벤트 식별자를 저장까지 흘리기 위한 연쇄 변경 시작점.
  - `@State private var suggestedEvent: CalendarEvent?` — Phase 1 `CalendarService` 조회 결과.
  - 섹션: 권한 있음 + 이벤트 있음 → "다음 일정: [제목] [시각]" + 수락/무시 버튼.
  - 권한 없음 → 배너("캘린더 권한이 없어요"). 기존 수동 입력 폼 유지.
  - 이벤트 없음 → 섹션 숨김.
  - 수락 시 `topic` 필드를 이벤트 제목으로 프리필(`topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`일 때만 — 공백 전용 입력 포함 보호).
  - 참석자: topic 하단 "참석자: ..." 보조 텍스트 표시. **참석자 이름은 로그 금지**.
- `Sources/Minto/UI/MeetingSetupWindowManager.swift`
  - `onStart` 시그니처 동일하게 변경: `(String, String, String, AudioInputMode, String?) -> Void`.
  - 내부 클로저에서 `eventIdentifier` 파라미터를 받아 상위 콜백으로 전달.
- `Sources/Minto/App/AppDelegate.swift`
  - `onStart` 콜백 시그니처 변경 반영. `calendarEventIdentifier`를 `MeetingContext.shared`에 보관하거나 세션 시작 시 `TranscriptionViewModel`에 전달.
  - **녹음 세션 동안 identifier 보관 위치**: `MeetingContext.shared`에 `calendarEventIdentifier: String?` 프로퍼티 추가(기존 topic/glossary/document와 동일 패턴). 세션 종료 후 `MeetingRecordFactory.makeRecord` 호출 시 전달.

**새 파일**:
- `Sources/Minto/Services/CalendarPrefillUseCase.swift` (Services — 기존 UseCase 배치 패턴)
  - `func findBestMatch(events: [CalendarEvent], relativeTo: Date, window: TimeInterval) -> CalendarEvent?`
  - window 기본값: 900초(±15분). 복수 후보는 시각 거리 최소 기준 정렬.

**검증**:
- UI 설계 게이트: 프리필 섹션 5상태(권한없음/권한있음+이벤트없음/권한있음+이벤트있음/수락/거부) Pencil 선설계 → `Resources/designs/` 저장. 게이트 통과 후 구현.
- `swift test --filter CalendarPrefillUseCaseTests` — 복수 이벤트, 창 밖 이벤트, 빈 배열.
- `./scripts/dev.sh run`: 다음 15분 이내 캘린더 일정 있을 때 → 프리필 제안 표시.
- 이미 주제 입력(공백 포함) 후 수락 → 주제 필드 덮어쓰지 않음.
- 권한 거부 시 → 배너, 수동 입력 가능.

### Phase 3 — 캘린더 매칭 식별자 저장 (schema 변경)

**범위**: `MeetingRecord`에 `calendarEventIdentifier` 추가. 저장된 회의 ↔ 캘린더 일정 매칭.

**변경 파일**:
- `Sources/Minto/Models/MeetingRecord.swift`
  - `public var calendarEventIdentifier: String?` 추가.
  - `CodingKeys`에 `.calendarEventIdentifier` 추가.
  - `init(from:)`: `try c.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)`.
  - `init(...)` 파라미터 기본값 `nil`.
- `Sources/Minto/Services/MeetingRecordFactory.swift`
  - `makeRecord(... calendarEventIdentifier: String? = nil)` 파라미터 추가.
  - 호출부(`AppDelegate.swift:156`, `MeetingFileImportUseCase.swift:313`)에서 `calendarEventIdentifier` 전달.
- `Sources/Minto/UI/MeetingLibraryView.swift` — 회의 목록에서 캘린더 아이콘 배지 표시(매칭된 경우).

**선행 작업**: `Tests/MintoTests/Fixtures/` 디렉터리 생성(현재 미존재). 아래 fixture 파일들을 여기에 배치한다.

**검증**:
- `swift test --filter MeetingRecordCodingTests` — `Tests/MintoTests/Fixtures/`의 기존 JSON fixture(calendarEventIdentifier 키 없음) 로드 → nil 정상 확인.
- 새 JSON fixture(키 있음) → 식별자 복원 확인.
- `swift build --disable-sandbox --scratch-path /tmp/minto2-build` 통과.

### Phase 4 — RemindersService + ActionItem.isDone (schema 변경 + EKReminder)

**범위**: `RemindersService` 어댑터 구현. `ActionItem.isDone` 추가. 미리알림 내보내기 버튼.

**전제**: Phase 1 CalendarService 패턴 확립 후.

**새 파일**:
- `Sources/Minto/Services/RemindersService.swift` (Infrastructure)
  - `protocol RemindersServiceProtocol` — `requestAccess()`, `addReminder(title:dueDate:notes:) async throws`. 완료 상태 수신 API 없음(단방향 push만 — Out of Scope).
  - `actor RemindersService` — Swift 6 strict concurrency 대응: `actor`로 설계. **자체 `EKEventStore` 인스턴스 소유**(CalendarService와 store 공유 없음 — 권한 타입 독립·생명주기 결합 회피).
  - `final class RemindersServiceStub` — 테스트용.
  - notes 필드에 넣는 내용: ActionItem 원문 텍스트(사용자가 회의 상세에서 이미 보는 내용). **notes 내용은 로그에 남기지 않는다**.
- `Sources/Minto/Services/ActionItemReminderUseCase.swift` (Services — 기존 UseCase 배치 패턴)
  - `func export(items: [ActionItem], meetingTitle: String) async -> [ActionItemExportResult]`
  - `due` 문자열 → `Date?` 파싱(lenient, 실패 시 nil → 미리알림 마감일 없음).

**변경 파일**:
- `Sources/Minto/Models/MeetingSummary.swift` — `ActionItem`에 `isDone: Bool` 추가.
  - `CodingKeys`에 `.isDone` 추가.
  - `init(from:)`: `(try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false` (기존 lenient 패턴, `:51-57` 참조).
  - `init(...)`: `isDone: Bool = false` 기본값.
- `Sources/Minto/UI/MeetingSummaryView.swift` — ActionItem 카드에 완료 체크박스. 내보내기 버튼(권한 있을 때만 표시).
- Info.plist — `NSRemindersUsageDescription` 추가.
- `Sources/Minto/Services/Log.swift` — `reminders` 카테고리 확인.

**로그**: `Log.reminders.info("reminder export count=\(...)")`, `.error` on failure.

**검증**:
- `swift test --filter ActionItemReminderUseCaseTests` — due 파싱, 빈 목록, 권한 거부 stub.
- `swift test --filter MeetingSummaryTests` — isDone backward-compat (`Tests/MintoTests/Fixtures/`의 기존 JSON fixture).
- `./scripts/dev.sh run`: ActionItem 내보내기 → macOS 미리알림 앱에서 항목 확인.
- 권한 거부 → 내보내기 버튼 숨김(disabled).
- QA 시나리오: 미리알림 앱에서 항목을 완료 처리해도 Minto `isDone`이 바뀌지 않는 것이 **의도된 동작**임을 확인. 앱 내 체크박스 완료만 반영됨을 사용자에게 안내하는 문구 노출 확인.

### Phase 5 — 미결 할일 모아보기 뷰

**범위**: 여러 회의에 걸친 `isDone == false` ActionItem을 모아보는 화면. `MeetingLibraryView` 또는 별도 패널.

**설계 게이트**: 3개 이상 상태(`empty/loading/items/done-all`) → Pencil 선설계 필요. `Resources/designs/`에 `.pen` + export 저장.

**새 파일**:
- `Sources/Minto/Services/PendingActionItemsUseCase.swift` (Services — 기존 UseCase 배치 패턴)
  - `MeetingStore`에서 전체 회의 조회 → `ActionItem.isDone == false` 필터 → 회의별 그룹.
- `Sources/Minto/UI/PendingActionItemsView.swift` (UI)
  - 상태: empty("모든 할일이 완료됐어요"), loading, 목록(회의별 섹션), disabled(요약 없는 회의).

**검증**:
- `swift test --filter PendingActionItemsUseCaseTests` — `MeetingStore` 다건 조회 → `isDone == false` 필터 로직 단위 테스트.
- `./scripts/dev.sh run`: 다수 회의 ActionItem 중 일부 완료 → 미결만 목록에 표시.
- 전체 완료 → empty 상태 표시.

---

## 5. 확장 테스트 계획

### Unit

| 대상 | 테스트 내용 |
|------|------------|
| `TalkTimeAnalyzer` | 0명·1명·다화자·nil speaker("알 수 없음" 별도 집계)·0초 세그먼트·ratio 합산=1.0 |
| `CalendarPrefillUseCase` | 창 안/밖 이벤트, 복수 이벤트 최근접 선택, 빈 배열 |
| `ActionItemReminderUseCase` | due 파싱(정상·불완전·빈 문자열), 권한 거부 stub 경로 |
| `PendingActionItemsUseCase` | `MeetingStore` 다건 조회 → `isDone == false` 필터, 전체 완료 시 빈 결과 |
| `ActionItem` schema backward-compat | isDone 키 없는 JSON → false |
| `MeetingRecord` schema backward-compat | calendarEventIdentifier 키 없는 JSON → nil |

### Integration (EventKit stub)

- `CalendarServiceProtocol` stub 구현체로 EventKit 없이 테스트 가능 설계.
- 권한 거부 stub → `upcomingEvents` 빈 배열, UI 배너 표시 확인.
- `RemindersServiceProtocol` stub → export 결과 배열 검증.

### E2E (수동 QA — `./scripts/dev.sh run`)

- 캘린더 권한 허용 + 15분 이내 일정 있음 → 프리필 제안 표시.
- 프리필 수락 → `topic` 채워짐. 거부 → 빈 폼 유지.
- ActionItem 내보내기 → macOS 미리알림 앱 확인.
- 미리알림 권한 거부 → 내보내기 버튼 숨김.
- 화자분리 결과 있는 회의 → 발화 분석 카드 표시.

### Observability (로그)

- `Log.calendar`: 권한 결과, 이벤트 수 (제목·참석자 금지).
- `Log.reminders`: 내보내기 성공 개수, 실패 사유.
- `Log.app`: 프리필 수락/거부 이벤트 (제목 금지, "accepted=true/false" 등 enum).
- `Log.diarization`: 이미 존재. 발화 분석 집계 결과(`speakerCount=`, `totalSeconds=`)는 `.info`.

---

## 6. 아키텍처 배치

```
Domain/Core (IO 없음)
  Sources/Minto/Models/TalkTimeAnalyzer.swift          ← Phase 0
  Sources/Minto/Models/MeetingSummary.swift (isDone)   ← Phase 4
  Sources/Minto/Models/MeetingRecord.swift (calId)     ← Phase 3

Services (UseCase + Infrastructure 단층 — 현행 구조 유지)
  Sources/Minto/Services/CalendarPrefillUseCase.swift       ← Phase 2
  Sources/Minto/Services/ActionItemReminderUseCase.swift    ← Phase 4
  Sources/Minto/Services/PendingActionItemsUseCase.swift    ← Phase 5
  Sources/Minto/Services/CalendarService.swift              ← Phase 1
  Sources/Minto/Services/RemindersService.swift             ← Phase 4
```
> **배치 근거**: 코드베이스에 `Application/` 디렉터리가 없고 기존 UseCase(LiveSpeakerAssignmentUseCase, LiveDiarizationFinalizeUseCase 등)가 전부 `Services/`에 있다. 신규 UseCase도 기존 패턴대로 `Services/`에 배치한다. Services가 Application 역할을 겸하는 현행 단층 구조를 유지한다. 레이어 신설은 별도 리팩터링·ADR 비용이 크고 이 트랙의 목적이 아니다.

```
UI
  Sources/Minto/UI/MeetingSetupView.swift (프리필 섹션)   ← Phase 2
  Sources/Minto/UI/MeetingSummaryView.swift (발화·완료)   ← Phase 0, 4
  Sources/Minto/UI/MeetingLibraryView.swift (캘린더 배지) ← Phase 3
  Sources/Minto/UI/PendingActionItemsView.swift           ← Phase 5
```

---

## 7. 저장 Schema 마이그레이션 노트

### 변경 필드 목록

| 파일 | 필드 | 타입 | 기본값 | backward-compat 전략 |
|------|------|------|--------|----------------------|
| `MeetingRecord` | `calendarEventIdentifier` | `String?` | `nil` | `decodeIfPresent` |
| `ActionItem` (MeetingSummary) | `isDone` | `Bool` | `false` | `(try? c.decodeIfPresent(Bool.self, ...)) ?? false` (lenient 패턴) |

### 규칙

- `schemaVersion`은 현재 1. 두 필드 모두 additive optional이므로 bump 불필요 (기존 `summaryGlossary`, `document`, `speakerEmbeddings` 전례 — `MeetingRecord.swift:33-44`).
- 기존 JSON에서 키가 없으면 `decodeIfPresent` → nil/false. 키가 있으나 손상된 경우는 throw → quarantine (기존 정책 유지, `:96-100`).
- `MeetingRecord`의 `init(from:)` 추가 라인은 반드시 기존 `decodeIfPresent` 블록 패턴 그대로 따른다.
- Fixture 테스트: 기존 JSON(새 키 없음)을 `Tests/MintoTests/Fixtures/`에 두고 로드 → 기본값 확인. (**Phase 3 선행 작업**: 해당 디렉터리 현재 미존재 — Phase 3 착수 전 생성.)

---

## 8. ADR 초안 (docs/adr/0008)

### ADR 0008: EventKit 캘린더·미리알림 권한 도입

**상태**: Proposed
**작성일**: 2026-06-29

#### Context

Minto2는 현재 마이크·화면 캡처(systemAudio) 권한만 사용한다. "회의 전후 EventKit 트랙"은 `EKEventStore`로 캘린더 이벤트 조회와 미리알림 생성을 추가한다. 이는 **개인정보 접근 범위 변경**에 해당한다(CLAUDE.md ADR 필요 조건: "개인정보가 외부 provider로 나가는 범위 변경"). 단, EventKit은 온디바이스 로컬 접근이므로 **클라우드 전송은 없다**.

#### Decision Drivers

1. 캘린더 이벤트 제목·참석자는 민감 개인정보 — 로그 금지, 외부 전송 금지.
2. 권한 거부 시 앱 핵심 흐름(녹음·전사·저장)이 영향받으면 안 된다.
3. macOS App Store 또는 직접 배포 모두 Info.plist usage description이 필수.

#### Decision

- **EventKit 네이티브 사용** (캘린더: `EKEntityType.event`, 미리알림: `EKEntityType.reminder`).
- 새 SPM 의존성 없음.
- 모든 EventKit 접근은 `CalendarService` / `RemindersService` Infrastructure 어댑터로 격리. Domain·Application은 `protocol`만 참조.
- 권한 요청: 기능 진입 지연 요청 (앱 시작 팝업 금지).
- 로그: 권한 결과(granted/denied bool) 기록. 이벤트 제목·참석자·미리알림 내용 기록 금지.

#### Alternatives Considered

- **수동 입력 유지**: 마찰 크고 자동화 가치 없음.
- **Calendars.app URL scheme**: 읽기 불가. 조회 목적에 맞지 않음.
- **외부 캘린더 API (Google Calendar 등)**: 클라우드 전송 발생 → 프라이버시 원칙 위반.

#### Why Chosen

온디바이스 EventKit은 새 의존성 없이 macOS 표준 UX(미리알림 앱 통합)를 제공하는 유일한 경로. 권한 거부 시 fail-soft로 앱 흐름 보호.

#### Consequences

**Positive**
- 캘린더 프리필로 회의 시작 마찰 감소.
- ActionItem을 미리알림으로 연결해 후속 관리 가능.
- 발화 분석은 EventKit 무관(세 기능 중 독립).

**Negative**
- 캘린더·미리알림 권한 팝업 2개 추가.
- EKEventStore 접근 실패(권한 거부·캘린더 없음)에 대한 방어 코드 필요.
- 캘린더 매칭은 시각 기반 휴리스틱 → 오탐 가능성(Pre-mortem 시나리오 2).

#### Follow-ups

- 캘린더 매칭 오탐률 측정 후 창(window) 조정.
- EKReminder 완료 상태를 앱 `isDone`과 양방향 동기화할지 별도 검토.

---

## 9. 범위 밖 (Out of Scope)

- Slack / 이메일 / 메시지 연동
- Notion publish / Confluence 게시
- 감정 분석 / 회의 품질 점수
- Google Calendar / Outlook API (클라우드 전송 발생)
- EKReminder ↔ `ActionItem.isDone` 양방향 동기화 (단방향 push만). `RemindersServiceProtocol`에 완료 수신 API 없음 — 미리알림 앱에서 완료 처리해도 Minto isDone은 미변경이 의도된 동작.
- 캘린더 일정 생성·수정 (읽기 전용)
- macOS 14 미만 호환
- 발화 분석 기반 자동 화자 식별 개선 (별도 트랙)
