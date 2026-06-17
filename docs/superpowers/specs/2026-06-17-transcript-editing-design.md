# 전사 편집 (회의 후) — 아이디어 2 설계

작성일: 2026-06-17 · 갱신: 2026-06-18 (codex 스펙 리뷰 반영)

## 배경 / 문제

전사 오류(예: 루션→노션)가 요약·검색·내보내기에 그대로 전파된다. 아이디어 1(용어집 anchor)은 완화책이지만, **원천 전사를 직접 고치는 것**이 더 근본적이다. 현재 저장된 회의의 전사는 읽기 전용이라 사용자가 교정할 수 없다.

## 목표

저장된(회의 후) 회의의 전사를 **줄 단위 텍스트로 편집**해, 요약·검색·내보내기에 더 정확한 원천을 제공한다.

## 비목표 (YAGNI)

- **회의 중(라이브) 편집** — `committedSegments`가 STT 파이프라인에 의해 실시간 append·교정 flush(80)·evict(100캡)되므로 편집과 레이스/덮어쓰기 위험. 제외.
- **화자(speaker) 편집** — 별도 기능(`feat/speaker-label-edit-ui`). 본 기능의 text 편집 모드에서는 기존 speaker 편집 UI를 **숨김/비활성**한다(충돌 방지).
- **타임스탬프/오디오 정렬 편집** — 텍스트만.
- **merged 줄 분할/병합** — 편집 단위는 저장된 Segment 1개의 텍스트. 한 Segment를 여러 줄로 쪼개거나 합치는 건 v1 범위 밖.
- **편집 시 자동 재요약** — 수동(아이디어 1 "다시 요약")으로 갱신.

## 편집 단위 — 저장된 normalized Segment (중요)

저장 회의 화면(`transcriptBlock(record.transcript, ..., record:)`, `MeetingLibraryView.swift:1249`)은 `record.transcript`를 표시 단계 변환 없이 그대로 렌더한다(`Text(segment.text)`). **단, record 생성 시 이미 `TranscriptNormalizer.normalize`가 적용**되어 있다(`MeetingRecordFactory.swift:16`). 따라서:

- 편집 단위 = **저장된(이미 normalize/merge된) Segment의 `text`**. raw STT chunk가 아니다.
- 사용자가 보는 줄 ↔ 저장 Segment는 **1:1**이므로 화면 그대로 편집 가능.
- `Segment.text`는 `let`(불변) → 편집 = 같은 `id`/`timestamp`/`duration`/`speaker`로 새 Segment를 만드는 **public init**(`Meeting.swift:15`)으로 교체. (멤버와이즈가 아니라 명시적 public init.)
- 편집된 세그먼트의 `words`는 **`nil`로 비운다**(텍스트 변경 시 단어 매핑이 어긋남). 변경 없는 세그먼트의 `words`는 보존.
- 저장 시 **텍스트가 공백만인 세그먼트는 제거**.
- `MeetingRecord` 스키마 변경 없음.

## 저장 — 최신 record에 transcript만 병합

편집 캡처 시점의 `record`를 통째로 저장하면, 편집하는 동안 일어난 재요약/화자 변경 등 최신 필드를 덮어쓸 수 있다. 따라서 **기존 speaker 편집과 동일하게**(`MeetingLibraryView.swift:2128`, `2164` 참조) 저장 시 `store.meetings`에서 해당 id의 **최신 record를 다시 가져와 `transcript`만 교체**한 뒤 `MeetingStore.save` 한다.

`MeetingStore.save`는 upsert + `rebuildSearchIndex`(`MeetingStore.swift:92-95`)이므로 저장 후:

1. 검색 인덱스 **자동 재생성**(save 내부).
2. 내보내기: `MeetingResult.from(record)`가 `record.transcript`를 다시 읽으므로 **자동 반영**.
3. 오디오: timestamp/duration 보존 → 재생 정렬 유지.

## 자동 갱신되지 않는 것 (명시)

- **요약**: 자동 재생성 안 함. 저장 후 "전사를 수정했어요 — 다시 요약하면 반영돼요" 힌트 표시(휘발성 UI 플래그, 그 화면 세션 동안). 사용자가 아이디어 1 "다시 요약"으로 갱신.
- **관련 문서(related docs)**: 쿼리가 summary/keywords/outcomes를 우선하고 transcript는 fallback이라(`MeetingLibraryView.swift:2607`), 요약이 남아 있으면 편집 직후 결과가 항상 바뀌지는 않는다.
- **기존 보고서 산출물**: `ReportService`가 만든 `Documents/Minto` 보고서 파일은 재작성되지 않는다.

## UI

- **진입**: 전사 탭(`detailTab == .transcript`, 저장 회의 경로)에 "편집" 버튼. 라이브 회의 진행 중엔 비활성.
- **편집 모드 레이아웃**: 현재 `meetingPreview`는 전체가 하나의 `ScrollView`다(`MeetingLibraryView.swift:1227`). sticky bar가 함께 스크롤되지 않도록, 편집 모드는 **`transcriptBlock` 내부가 아니라** 저장 전사 레이아웃을 **`스크롤 영역 + 하단 고정 바`로 분리**한다.
- **줄 편집**: 각 세그먼트 줄이 편집 가능한 멀티라인 입력으로 전환. 타임스탬프는 읽기 전용으로 함께 표시. 현재 읽기 전용 전사는 `VStack + ForEach`(`MeetingLibraryView.swift:1828`)로 lazy가 아니므로, **편집 모드는 `LazyVStack`로 전환하거나 100+ TextEditor 성능을 측정**한다.
- **하단 고정(sticky) 액션 바**: 스크롤 무관 항상 보이는 `[취소]` `[저장]`.
- **단축키**: ⌘S = 저장, Esc = 취소.
- **저장**: 배치 1회. 변경 없으면 비활성/즉시 종료.
- **상태**: empty(전사 없음 → 진입 비활성) / editing / saving / success / error / disabled(라이브 진행 중).

## 저장 실패 / Empty Edge

- **저장 실패**: `MeetingStore.save`는 **recovery 파일을 만들지 않는다**(recovery는 녹음 종료 저장 실패에서 `AppDelegate`만 호출, `MeetingSaveRecovery.swift:142`). 따라서 편집 저장 실패 시 **편집 draft를 메모리에 유지하고 재시도** UX를 제공한다(편집 모드 유지 + 에러 표시). 무음 손실 금지.
- **빈 회의 가드**: `record.isEmpty == transcript.isEmpty && summary.isEmpty`(`MeetingRecord.swift:107`). 전사를 전부 지워도 요약이 있으면 저장됨. 요약도 비었으면 `.skippedEmpty`(저장 안 됨) → "내용이 없어 저장할 수 없어요" 안내.

## 컴포넌트 경계

- 편집 UI: 신규 `TranscriptEditView`(스크롤 영역 + 하단 고정 바 + 단축키). 입력: 편집 시작 시점 `record.transcript`. 출력: 편집된 `[Segment]`(취소 시 폐기).
- 저장: 최신 record 병합 후 `MeetingStore.save`에 위임.

## 영향 받는 파일 (예상)

- `UI/MeetingLibraryView.swift` — 전사 탭 편집 진입 + 편집 모드 레이아웃 분리 + speaker 편집 UI 숨김/비활성 + "전사 수정됨" 힌트.
- 신규 `UI/TranscriptEditView.swift` — 줄 편집 + 하단 고정 바 + ⌘S/Esc.
- (모델/스토어 변경 없음 — Segment public init·MeetingStore.save 재사용.)

## 테스트

- 세그먼트 교체: text 변경, id/timestamp/duration/speaker 보존, **편집된 것만 words=nil·미변경은 보존**.
- 공백 세그먼트 제거.
- 저장 시 **최신 store.meetings record에 transcript만 병합**(다른 필드 보존) 확인.
- 저장 후 검색 인덱스·내보내기가 편집 내용 반영.
- 저장 실패 시 draft 유지 + 에러(무음 손실 없음).
- 전사 전부 삭제 + 요약 없음 → `.skippedEmpty` 안내.
- UI(편집 모드/고정 바/⌘S·Esc/힌트/speaker UI 숨김)는 수동 QA.

## 엣지 / 리스크

- **편집 중 화면 이탈/앱 종료**: v1은 미저장 draft 손실(단순). 추후 가드 검토.
- **동시성**: 저장 회의만 편집 + 저장 시 최신 record 병합 → 라이브/재요약/화자변경과 충돌 회피.
- **성능**: 100+ 세그먼트 편집 모드는 LazyVStack/측정 필요.
