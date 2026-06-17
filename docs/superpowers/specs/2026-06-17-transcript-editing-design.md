# 전사 편집 (회의 후) — 아이디어 2 설계

작성일: 2026-06-17

## 배경 / 문제

전사 오류(예: 루션→노션)가 요약·검색·내보내기에 그대로 전파된다. 아이디어 1(용어집 anchor)은 완화책이지만, **원천 전사를 직접 고치는 것**이 더 근본적이다. 현재 저장된 회의의 전사는 읽기 전용이라 사용자가 교정할 수 없다.

## 목표

저장된(회의 후) 회의의 전사를 **줄 단위 텍스트로 편집**해, 요약·검색·내보내기에 더 정확한 원천을 제공한다.

## 비목표 (YAGNI)

- **회의 중(라이브) 편집** — `committedSegments`가 STT 파이프라인에 의해 실시간 append·교정 flush(80)·evict(100캡)되므로 편집과 레이스/덮어쓰기 위험. 가치 대비 위험이 커 제외(회의 후 고치면 됨).
- **화자(speaker) 편집** — 별도 기능(`feat/speaker-label-edit-ui`)에서 다룸.
- **타임스탬프/오디오 정렬 편집** — 텍스트만 편집(시간 구조 보존).
- **편집 시 자동 재요약** — 수동(아이디어 1 "다시 요약")으로 갱신.

## 데이터 모델

`Segment.text`는 `let`(불변). 편집 = **같은 `id`/`timestamp`/`duration`/`speaker`로 `text`만 바꾼 새 Segment로 교체**(`Segment(id:text:timestamp:duration:speaker:words:)` 멤버와이즈 init 사용).

- 편집된 세그먼트의 `words`(단어 타임스탬프)는 **`nil`로 비운다**(텍스트가 바뀌면 단어 매핑이 어긋남 — 어긋난 매핑보다 없는 게 안전).
- 저장 시 **텍스트가 공백만인 세그먼트는 제거**한다(사용자가 줄을 지운 의도).
- `MeetingRecord` 스키마 변경 없음(`transcript: [Segment]` 그대로, 내용만 교체). schemaVersion 무관.

## 편집 후 파급 (저장 시점)

`MeetingStore.save`가 이미 **upsert + `rebuildSearchIndex`**(`MeetingStore.swift:92-95`)를 수행하므로, 편집된 record를 `save`하면 아래가 자동 처리된다:

1. record.transcript를 편집된 세그먼트로 교체 → `save`(파일 atomic write, fail-soft).
2. **검색 인덱스 자동 재생성**(save 내부 `rebuildSearchIndex`).
3. 편집된 세그먼트 `words = nil`.
4. **요약: 자동 재생성 안 함.** 저장 후 "전사를 수정했어요 — 다시 요약하면 반영돼요" 힌트를 요약 영역에 표시. 사용자가 아이디어 1 "다시 요약"으로 갱신.
5. 내보내기: 저장된 전사를 읽으므로 자동 반영. 오디오: timestamp/duration 보존 → 재생 정렬 유지.

**"전사 수정됨" 힌트 상태**: v1은 **휘발성 UI 플래그**(편집 저장 후 그 화면 세션 동안만 표시). 영속 플래그는 스키마 추가가 필요하므로 v1 제외(YAGNI).

## UI

- **진입**: 전사 탭(`detailTab == .transcript`, 저장 회의 `transcriptBlock(record:)` 경로, `MeetingLibraryView.swift:1249`)에 "편집" 버튼.
- **편집 모드**: 각 세그먼트 줄이 편집 가능한 멀티라인 텍스트 입력으로 전환. 타임스탬프/화자는 읽기 전용으로 함께 표시(맥락 유지).
- **하단 고정(sticky) 액션 바**: 스크롤과 무관하게 항상 보이는 `[취소]` `[저장]`. 긴 전사에서 상단 왕복 불필요.
- **단축키**: ⌘S = 저장, Esc = 취소.
- **저장**: 배치 1회(부분 저장 꼬임 없음). 변경 없으면 저장 비활성 또는 즉시 종료.
- **상태**(CLAUDE.md UI 요구): empty(전사 없음 → 편집 진입 비활성) / editing / saving / success / error(fail-soft 에러 표시) / disabled(라이브 회의 진행 중엔 편집 비활성).
- 긴 전사 성능: 평소엔 읽기 전용 lazy 리스트, **편집 모드에서만** 입력 필드로 전환.

## 컴포넌트 경계

- 편집 UI: 신규 `TranscriptEditView`(또는 전사 탭의 편집 모드 분기). 입력: `record.transcript`. 출력: 편집된 `[Segment]`(취소 시 폐기).
- 저장+재인덱싱: `MeetingStore.save`에 위임(이미 upsert + rebuildSearchIndex).
- 하단 고정 바: 편집 모드 전용 뷰.

## 영향 받는 파일 (예상)

- `UI/MeetingLibraryView.swift` — 전사 탭 편집 진입 + "전사 수정됨" 힌트 + 편집 모드 분기.
- 신규 `UI/TranscriptEditView.swift` — 줄 단위 편집 + 하단 고정 액션 바 + 단축키.
- (모델/스토어 변경 없음 — Segment init·MeetingStore.save 재사용.)

## 테스트

- 세그먼트 교체: text 변경, id/timestamp/duration/speaker 보존, words=nil.
- 공백 세그먼트 제거.
- 저장 후 검색 인덱스가 편집 내용 반영(save → rebuildSearchIndex).
- 내보내기가 편집 텍스트 반영.
- 저장 실패 시 fail-soft(기존 transcript 유지, 에러 표시).
- 전사 전부 삭제 + 요약 없음 → `save`가 `.skippedEmpty`(저장 생략) 처리 확인.
- UI(편집 모드/고정 바/⌘S·Esc/힌트)는 수동 QA.

## 엣지 / 리스크

- **빈 회의 가드**: 전사를 전부 지웠는데 요약도 없으면 `record.isEmpty`로 `save`가 `.skippedEmpty` 반환(저장 안 됨). 이 경우 사용자에게 "내용이 없어 저장할 수 없어요" 안내.
- **편집 중 화면 이탈/앱 종료**: v1은 미저장 편집 손실(단순). 추후 종료/이탈 가드 검토.
- **동시성**: 저장된 회의만 편집 → 라이브 STT 경로 무관(설계상 안전).
- **요약-전사 불일치 창**: 편집 후 요약이 옛 전사 기준일 수 있음 → "전사 수정됨" 힌트로 명확히 알림(명확한 상태).
