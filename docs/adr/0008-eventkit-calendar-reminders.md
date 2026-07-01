# ADR 0008: EventKit 캘린더·미리알림 권한 도입

상태: Accepted
작성일: 2026-06-29
승인일: 2026-06-29 (사용자 "진행하자" 승인)
검토: ralplan 합의(Planner → Architect → Critic, Critic APPROVE) 통과.
관련 계획: `docs/work/2026-06-29-meeting-context-eventkit-track-plan.md`

## Context

Minto2는 현재 마이크·화면 캡처(systemAudio) 권한만 사용한다. "회의 전후 EventKit 트랙"은 macOS 네이티브 `EKEventStore`로 다음 두 가지를 추가한다.

- **캘린더 이벤트 조회**(`EKEntityType.event`): 다가오는 회의를 감지해 회의 시작 시 제목·참석자·시각을 프리필하고, 저장된 회의를 캘린더 일정과 매칭한다.
- **미리알림 생성**(`EKEntityType.reminder`): 회의 요약의 ActionItem을 macOS 미리알림 앱으로 내보낸다.

이는 **개인정보 접근 범위 변경**에 해당한다(CLAUDE.md ADR 필요 조건: "개인정보가 외부 provider로 나가는 범위 변경", "domain/application/infrastructure/UI 책임 경계 변경"는 해당 없음 — 아래 Consequences 참조). 단, EventKit은 **온디바이스 로컬 접근**이므로 클라우드 전송은 없다. 외부 캘린더 API(Google/Outlook)와 달리 데이터가 기기를 떠나지 않는다.

## Decision Drivers

1. 캘린더 이벤트 제목·참석자는 민감 개인정보 — 로그 금지, 외부 전송 금지.
2. 권한 거부 시 앱 핵심 흐름(녹음·전사·저장)이 영향받으면 안 된다(fail-soft).
3. macOS App Store 또는 직접 배포 모두 Info.plist usage description이 필수.
4. Swift 6 strict concurrency: EventKit 접근은 `Sendable` 안전하게 격리되어야 한다.

## Decision

- **EventKit 네이티브 사용**. 새 SPM 의존성 없음.
- 모든 EventKit 접근은 `CalendarService` / `RemindersService` **Infrastructure 어댑터**로 격리. Domain·Application(UseCase)은 `protocol`만 참조.
- 두 서비스는 각각 `actor`로 설계하고 **자체 `EKEventStore` 인스턴스를 소유**한다(공유 없음 — 권한 타입 독립·생명주기 결합 회피). `swift build`에서 `Sendable` 경고 0건을 검증 게이트로 둔다.
- 권한 요청: **기능 진입 지연 요청**(캘린더 섹션 처음 표시 시, 내보내기 버튼 첫 탭 시). 앱 시작 시 선제 팝업 금지.
- 캘린더 권한과 미리알림 권한은 **독립**. 한쪽 거부가 다른 쪽을 막지 않는다.
- 로그: 권한 결과(granted/denied bool), 이벤트 개수만 기록(`Log.calendar`, `Log.reminders`). **이벤트 제목·참석자·미리알림 내용 기록 금지**.
- Info.plist: `NSCalendarsUsageDescription`, `NSRemindersUsageDescription` 추가.

## Alternatives Considered

- **수동 입력 유지**: 권한 불필요·복잡도 0이지만 자동화 가치가 없고 회의 시작 마찰이 그대로다.
- **Calendars.app URL scheme**: 읽기 불가. 조회 목적에 맞지 않음.
- **외부 캘린더 API(Google Calendar / Outlook)**: 클라우드 전송 발생 → 로컬 우선·프라이버시 원칙 위반. 기각.
- **할일 내보내기를 자체 Task 모델로**: 의존성·권한 0이지만 macOS 미리알림 앱·시스템 알림과 단절되고 검색·알림을 직접 구현해야 한다. EventKit을 캘린더로 이미 도입하므로 미리알림 추가 비용이 작아 EKReminder 채택.

## Why Chosen

온디바이스 EventKit은 **새 의존성 없이** macOS 표준 UX(미리알림 앱 통합·시스템 캘린더 연동)를 제공하는 유일한 경로다. 권한 거부 시 fail-soft로 앱 핵심 흐름을 보호하고, 클라우드 전송이 없어 로컬 우선 정체성과 일치한다.

## Consequences

**Positive**
- 캘린더 프리필로 회의 시작 마찰 감소(제목·시각·참석자 자동).
- ActionItem을 미리알림으로 연결해 회의 후 실행 루프 완성.
- 발화 분석(Phase 0)은 EventKit과 무관하게 독립 출시 가능.
- 새 외부 의존성 0, 모든 처리 온디바이스.

**Negative**
- 캘린더·미리알림 권한 팝업 2개 추가(지연 요청으로 완화).
- EKEventStore 접근 실패(권한 거부·캘린더 없음)에 대한 방어 코드 필요.
- 캘린더 ↔ 회의 매칭은 시각 기반 휴리스틱(±15분 창) → 오탐 가능성(계획 Pre-mortem 시나리오 2에서 완화: 단일 후보 제안 + 사용자 확인 + 빈 필드에만 프리필).
- 미리알림은 **단방향 push만** — 미리알림 앱에서 완료 처리해도 앱 `isDone`은 미변경. 양방향 동기화는 범위 밖(Follow-up).

**아키텍처 경계 영향 없음**: 신규 UseCase는 기존 패턴대로 `Sources/Minto/Services/`에 배치한다(`Application/` 디렉터리 신설 안 함 — 코드베이스에 없고 기존 UseCase가 전부 `Services/`에 있다). 따라서 책임 경계 변경 ADR은 불필요하며 본 ADR은 권한 범위 변경만 다룬다.

## Follow-ups

- 캘린더 매칭 오탐률 측정 후 창(window) 상수 조정.
- EKReminder 완료 상태를 앱 `isDone`과 양방향 동기화할지 별도 검토(`RemindersServiceProtocol`에 완료 수신 API 추가 필요).
- 미리알림 단방향 push의 stale 상태를 사용자에게 안내하는 문구 확정.
