# 재조정 UX 명세 (Task 0c)

> 실시간 화자분리의 "라이브 임시 라벨 → 저장 시 확정 라벨" 전환을 사용자에게 불신 없이
> 보여주는 화면 명세. Pencil 설계 원본은 `designs/minto-redesign.pen`의 프레임
> `0c-1`~`0c-5`, export 스냅샷은 `Resources/designs/2026-06-24-rtdiar-reconcile-*.png`.
> 알고리즘은 [reconciliation-algorithm-spec.md](reconciliation-algorithm-spec.md), API는
> [lseend-streaming-api-notes.md](lseend-streaming-api-notes.md) 참조.

## 설계 원칙

사용자가 라이브 중 본 임시 화자 이름(예: "화자 1")이 저장 후 다른 이름(예: "김재휘")으로
바뀌면 **"내가 본 게 틀렸나?"** 하는 불신이 생긴다. 이를 막는 세 가지 장치:

1. **예고** — 라이브 중에 "이 이름은 임시"라고 미리 알린다. 바뀌는 게 정상임을 학습시킨다.
2. **설명** — 바꾼 직후 "무엇을 무엇으로 바꿨는지" 명시하고 **되돌리기**를 제공한다.
3. **보호** — 사용자가 직접 고친 이름은 절대 자동으로 덮어쓰지 않는다.

핵심: 라벨 변경을 **숨기지 않고 드러내되, 통제권을 사용자에게 준다**.

## 상태 → 표현 매핑

`TranscriptionViewModel`의 상태(`empty/실시간/저장중/확정/fail-soft`)에 편집 보존을 더한 5개 화면.

| # | 상태 | 트리거 | 헤더 | 화자 라벨 표현 | 안내(hint) 카피 |
|---|------|--------|------|----------------|-----------------|
| 1 | 녹음 중 (임시) | `isRecording` + 라이브 diar 동작 | 🔴 `녹음 중` · 타이머 | 회색(secondary) `화자 N`. **인식 중(pending) 줄에도 임시 화자 표시**(기존엔 없음) | `화자는 임시예요 · 저장할 때 자동으로 정리돼요` |
| 2 | 저장 중 (확정 진행) | `isFinalizingMeeting` (VBx 재실행) | 🔵 스피너 `화자 정리 중…` + 진행바 | 화자 칩을 **shimmer 자리표시**로(재계산 중). 텍스트는 그대로 | `정리가 끝나면 임시 이름이 정확한 이름으로 바뀔 수 있어요` |
| 3 | 저장 후 (확정·실명) | 재조정 완료 | 🟢 `정리 완료` · `N분 · 화자 N명` | 매칭된 보이스프린트 = **파랑 `#1D4ED8` + 연파랑 칩 강조**, 미매칭 = 회색 `화자 N` | (배너) `임시 ‘화자 1’을 ‘김재휘’로 정리했어요` + **`되돌리기`** |
| 4 | 편집됨 (보존) | 사용자가 라이브 중 라벨 수정 | 🟢 `정리 완료` | 편집 라벨 = **진회색 `#111827` + ✏️ 연필 아이콘**, 자동 매칭 = 파랑, 번호 = 회색 | `직접 정한 이름은 자동 정리에서 보호돼요` (🛡️) |
| 5 | Fail-soft (채널) | 라이브 diar throw/과부하 → 강등 | 🟢 `정리 완료` · `마이크 기준` | 마이크 채널 라벨: `나`=파랑, `상대`=회색 | `화자를 자동으로 나누지 못해 마이크 기준으로 표시했어요` (🎤) |

## 트러스트 장치 상세

### (1) 예고 — 라이브 hint (화면 1)
- 전사 패널 헤더 아래 고정 배너. 회색(`#F3F4F6`) 바탕, info 아이콘 + 11pt 회색 텍스트.
- 한 번 보고 익히는 용도라 닫기 버튼은 두지 않는다(공간 절약, 비방해).

### (2) 설명 — 변경 배너 (화면 3) ★ 가장 중요
- 저장 후 라벨이 **실제로 바뀐 경우에만** 표시(안 바뀌면 배너 없음 — 노이즈 방지).
- 연파랑(`#EFF6FF`) 바탕, ✨ 아이콘 + `임시 ‘{이전}’을 ‘{이후}’로 정리했어요` + 우측 **`되돌리기`** 링크.
- 변경이 여러 건이면 `임시 이름 N개를 정확한 이름으로 정리했어요`로 요약, 되돌리기는 일괄.
- **되돌리기 = 재조정 매핑을 취소하고 라이브 임시 라벨로 복귀**(알고리즘 spec의 `mapLabels` 결과 폐기, 원본 `liveLabel` 유지). 사용자 편집(화면 4)은 되돌리기 대상이 아니다.
- 칩 강조: 바뀐 이름은 연파랑 칩 배경으로 첫 표시 시 시선 유도(영구 강조 아님 — 다음 진입 시 일반 파랑 텍스트로).

### (3) 보호 — 편집 라벨 (화면 4)
- 알고리즘 spec의 `resolveFinalLabels`: `edited == true`인 segment는 `liveLabel` 고정.
- ✏️ 연필 아이콘 + 진회색으로 "이건 네가 정한 것"임을 시각적으로 구분.
- 자동 매칭(파랑)·번호(회색)와 색으로 분리돼 한눈에 출처가 보인다.

## 색·아이콘 의미 체계 (구현 시 단일 출처 권장)

| 의미 | 색 | 부가 |
|------|-----|------|
| 임시/번호 화자 (`화자 N`) | `#6B7280` (secondary) | — |
| 자동 매칭 실명 | `#1D4ED8` (blue) | 변경 직후 `#DBEAFE` 칩 |
| 사용자 편집 라벨 | `#111827` | ✏️ `pencil` 아이콘 |
| 채널 라벨 `나` | `#1D4ED8` | fail-soft |
| 채널 라벨 `상대` | `#6B7280` | fail-soft |

> 기존 `TranscriptionOverlayView.committedRow`는 화자를 **10pt semibold secondary 단색**으로만
> 그린다(`SpeakerLabelFormatting`). Phase 3는 이 단색 규칙에 위 의미 체계(색 분기 + 편집 아이콘)를
> 더한다. pending 줄(`pendingRow`)은 현재 화자 라벨이 **없는데**, 라이브 diar 적용 후 임시 화자를
> 표시하도록 바꾼다(화면 1).

## Phase 3 적용 시 주의

- **fail-soft는 조용하게**: 화면 5는 녹음·전사·요약이 정상 저장된 상태다. 빨강 에러·경고 모달
  금지. 헤더는 `정리 완료`(녹색 체크) 유지하고, 강등 사실은 회색 hint로만 알린다(CLAUDE.md fail-soft 원칙).
- **카피 문자열은 위 표 그대로** 쓴다(임의 변형 금지 — 톤 일관성).
- 상태는 empty/loading(저장중)/success(저장후)/edited/disabled(fail-soft 안내)를 모두 가진다
  (CLAUDE.md UI 검증 게이트).

## Phase 3 선행 결정 (게이트 critic 리뷰 반영, 2026-06-24)

게이트 리뷰(critic, REVISE)가 Phase 3 착수 전 결정이 필요하다고 지적한 항목의 확정 답.

### D1 (blocker 해소) — 사용자 편집 여부는 영속하지 않는 라이브 세션 상태다
- **`Segment` 모델을 바꾸지 않는다**(`Meeting.swift:15` — `speaker: String?`, Codable. 필드 추가 시 저장 스키마·하위호환 부담).
- 편집 여부는 **재조정(저장 시 1회)에서만** 소비되고 저장 후엔 라벨이 최종 문자열로 확정돼 "편집이었는지" 기억할 필요가 없다(재조정 재실행 없음).
- 따라서 **ViewModel/UseCase 레이어에 `editedSpeakerSegmentIds: Set<Segment.ID>`**(라이브 중 사용자가 화자를 직접 지정/변경한 segment id)를 들고 있다가, 저장 시 `LiveDiarizationReconciler.resolveFinalLabels`의 `(liveLabel, edited)` 튜플을 `edited = editedSpeakerSegmentIds.contains(segment.id)`로 채운다. 비영속(메모리).
- 라벨 단위 rename(`SpeakerLabelEditing.replacingSpeaker`)은 해당 라벨의 모든 segment id를, 단일 reassign(`reassignSegment`)은 그 segment id만 set에 넣는다.

### D2 — "되돌리기"의 범위
- 되돌리기 = **사용자가 라이브에서 본 임시 라벨로 복귀**(예: `김재휘` → `화자 1`). VBx raw ID(`화자 3` 등)로 되돌리지 않는다 — 사용자가 본 적 없는 표기라 혼란.
- 구현: 재조정 매핑(`mapLabels`)·실명 치환 결과를 폐기하고 라이브 임시 라벨(`liveLabel`)을 그대로 표시. `editedSpeakerSegmentIds`로 보호된 라벨(예: `박팀장`)은 **애초에 자동 변경 대상이 아니므로 되돌리기에 영향받지 않는다**.
- 단위 = **배너에 표시된 변경 전체 일괄**. 부분 되돌리기는 v1 범위 밖(개별 라벨 재편집으로 대체 가능).

### D3 — 저장 중(화면 2) 앱 종료·충돌
- **저장은 VBx 재조정이 끝난 뒤 1회만** `MeetingRecord`를 기록한다. 재조정 전 충돌 시 회의는 **미저장**(부분 저장 금지) → 기존 `MeetingSaveRecovery` 복구 경로 대상.
- `isFinalizingMeeting`은 비영속이라 재시작 시 false로 초기화되는 게 정상(중간 상태가 디스크에 남지 않음).

### D4 — 라이브 diar 정상인데 화자가 없거나 1명
- **발화/화자 0 = 화자 칩 없이 전사 텍스트만**(기존 `pendingRow`/`committedRow` 방식 그대로). fail-soft(화면 5) 아님.
- **화자 1명 = 변경 배너 없이 화면 3**(혼자 말한 회의). 매칭되면 실명, 아니면 `화자 1`.
- **보이스프린트 0 등록 = 화면 3에서 모든 화자 회색 `화자 N`**(파랑 실명 칩 없음). 헤더는 `정리 완료` 유지, 변경 배너 없음.

### D5 — pending 줄 임시 화자 칩 (Minor 5)
- `committedRow`와 **동일 규칙**(`SpeakerLabel.normalized`, 10pt semibold secondary, `maxWidth: 64`). 단 텍스트와 함께 dim 처리(인식 중).
- LS-EEND `tentative` segment의 화자 = pending 줄에 표시, `finalized` = committed 줄. (`lseend-streaming-api-notes.md`)

### D6 — 변경 배너 / 칩 강조 수명 (Minor 6·7)
- 변경 배너: **저장 직후 그 화면 세션에서 1회 표시**. 앱 재시작·다른 회의 전환 시 사라짐. 비영속(UserDefaults 미저장).
- 연파랑(`#DBEAFE`) 칩 강조: 동일하게 비영속. 다음 진입(앱 재시작/회의 전환) 시 일반 파랑 텍스트.

### D7 — fail-soft 헤더 카피 (Skeptic 노트 반영)
- 화면 5 헤더를 `정리 완료`(녹색 체크)에서 **`마이크 기준으로 저장됐어요`**(중립)로 바꾼다. 기능 저하 상태에 "정리 완료"는 과장 — 정직한 중립 표현. 녹음·전사·요약 성공 사실은 hint로 유지.

## 산출물

- `designs/minto-redesign.pen` 프레임 `0c-1`~`0c-5` (원본, 메인 워크트리)
- `Resources/designs/2026-06-24-rtdiar-reconcile-{1..5}-*.png` (export 스냅샷, 이 브랜치)
- 게이트 critic 리뷰: REVISE → 위 D1~D7로 해소(D1 blocker 포함). D2~D7은 Phase 3 구현 중 PR 코멘트 수준.
