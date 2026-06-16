# 용어집 가시성 + 재요약 용어집 선택 (아이디어 1) — 설계

작성일: 2026-06-17

## 배경 / 문제

루션/노션 사례: 전사엔 "루션", 요약엔 "노션"으로 정규화됨. 요약은 LLM 의역 단계라 용어집이 anchor가 아니면 희귀 고유명사를 흔한 단어로 바꾼다. 현재 사용자는:

1. 요약이 **어떤 용어집을 참고했는지 확인할 수 없고**,
2. 용어집이 잘못됐어도 **용어집을 바꿔 다시 요약할 방법이 없다**(재요약은 현재 자동 해석된 용어집을 그대로 재사용).

## 목표

- (1a) 회의록에서 요약이 사용한 용어집을 확인한다.
- (1b) 재요약 시 용어집을 다시 선택해 더 정확히 다시 요약한다.

## 비목표 (YAGNI)

- 라이브 진행 중 요약의 용어집 표시 — 저장된 회의에만 적용.
- 과거 용어집 선택값의 정확 복원 — 재요약은 **현재** 용어집 상태 기준.
- 분류(카테고리) 라벨 저장 — `MeetingContext`가 분류를 들고 있지 않고, 실제 용어 스냅샷이 "무엇을 썼나"를 더 정확히 답하므로 생략.
- 전사 편집 — 아이디어 2(별도 스펙).

## 핵심 통찰

요약에 들어가는 용어 블록은 이미 **하드 상한(1,200자 / 관련 top-8 + 수동)**이 걸려 있다(`GlossaryStore.defaultMaxCharacters`, `candidates(limit:8)`). 따라서 "요약 당시 실제 투입된 용어 문자열"은 **≤1.2KB의 고정 스냅샷**이며, 이를 저장하면:
- 전역 용어집이 이후 바뀌어도 "그때 무엇을 썼나"는 불변 → "루션 있었나?"를 정확히 검증.
- 데이터 부담 없음(전사 34KB~449KB 대비 <1%).

## 데이터 모델

`MeetingRecord`에 optional 필드 1개 추가:

```
public var summaryGlossary: String?   // 요약 생성 시 프롬프트에 실제 들어간 용어 블록(줄 단위, ≤1,200자). 불변 스냅샷.
```

- optional + 기존 `schemaVersion`/tolerant decoder(P1) 덕분에 **하위호환**: 구버전 회의 JSON은 `nil`로 로드.
- `init(from:)`/`CodingKeys`에 `decodeIfPresent`로 추가.

### 스냅샷 캡처 지점 (요약을 만드는 모든 경로)

요약 문자열을 생성하는 곳마다 그때 사용한 glossary 문자열을 결과 `MeetingRecord.summaryGlossary`에 기록한다:

1. **라이브 종료 요약** — 회의 저장 시 `MeetingRecord`를 만드는 지점(`MeetingRecordFactory` 및/또는 `TranscriptionViewModel` 종료 저장 경로)에서 `MeetingContext.glossary`를 기록.
2. **파일 임포트 요약** — `MeetingFileImportUseCase`가 `SummaryGenerationContext.glossary`를 결과 기록에 기록.
3. **재요약** — `MeetingSummaryRetryUseCase`가 이번에 사용한 glossary(다이얼로그에서 해석된 값)를 갱신 기록에 기록.

## UI — 1a 표시 (요약 카드 상단 배너)

`MeetingLibraryView` 회의 상세, 요약 섹션 상단:

- **스냅샷 있음**: `📑 요약에 사용된 용어 N개 ▸` (N = 스냅샷 줄 수). `DisclosureGroup`로 평소 접힘, 펼치면 줄 목록 그대로 표시.
- **스냅샷 없음**(구버전 또는 용어집 미사용): 배너를 숨긴다(노이즈 방지). `summaryGlossary == nil || isEmpty` → 비표시.

## UI — 1b 재요약 용어집 다이얼로그

회의 상세의 "다시 요약" 동작을 **선택 다이얼로그 경유**로 변경:

- "다시 요약" → sheet 표시.
- sheet 내용: 기존 `GlossarySetSelectionSection`을 **그대로 재사용**(전역 분류 체크 + 회의별 수동 용어).
- 미리채움: `GlossarySetSelectionPersistence.load`로 **현재 살아있는** 선택 상태(과거 복원 아님). 수동 용어 칸은 비어서 시작(사용자가 누락 용어 추가).
- 확인("다시 요약") → 선택(분류 + 수동)을 회의 시작 화면과 **동일한 로직**으로 glossary 문자열로 해석 → 그 문자열을 `MeetingSummaryRetryUseCase`에 주입해 재요약 → 성공 시 요약 + `summaryGlossary` 스냅샷 동시 갱신·저장.
- 취소 → 아무 변화 없음.
- **fail-soft**: 재요약 실패 시 기존 요약/스냅샷 유지, 기존 `retryError` 패턴으로 에러 표시.

### 재요약 use-case 변경

`MeetingSummaryRetryUseCase`는 현재 `glossaryResolver`로 자동 해석한다. 다이얼로그가 만든 glossary 문자열을 **명시 주입**할 수 있도록 retry 진입점에 glossary 파라미터(또는 미리 해석된 컨텍스트)를 받는 경로를 추가한다. 인자 미지정 시 기존 자동 해석 동작 유지(하위호환).

## 컴포넌트 경계

- `GlossarySetSelectionSection` — 이미 재사용 가능한 형태(바인딩 기반). 시작 화면·재요약 다이얼로그 공용. 추출/리팩터 불필요.
- 재요약 다이얼로그 — 위 섹션을 담는 신규 sheet view(예: `ReSummaryGlossarySheet`). 입력: 현재 선택 상태·회의 record. 출력: 사용자가 확정한 glossary 선택.
- 배너 — `MeetingLibraryView` 내 소형 뷰(또는 신규 `SummaryGlossaryBanner`).

## 영향 받는 파일 (예상)

- `Models/MeetingRecord.swift` — 필드 추가 + 디코더.
- `Services/MeetingSummaryRetryUseCase.swift` — glossary 명시 주입 경로 + 스냅샷 기록.
- `Services/MeetingFileImportUseCase.swift`, `Services/MeetingRecordFactory.swift`(및 종료 저장 경로) — 스냅샷 기록.
- `UI/MeetingLibraryView.swift` — 배너 + "다시 요약" → 다이얼로그 진입.
- 신규: `UI/ReSummaryGlossarySheet.swift`(및 필요 시 `UI/SummaryGlossaryBanner.swift`).

## 테스트

- `MeetingRecord` round-trip: 새 필드 보존 + 필드 없는 구버전 JSON 정상 로드(nil).
- 각 요약 경로(라이브 저장/임포트/재요약)가 `summaryGlossary`를 채우는지 단위 테스트.
- `MeetingSummaryRetryUseCase`가 **주입된 glossary**로 재요약하고 스냅샷을 갱신하는지.
- UI(배너 표시/숨김, 다이얼로그 흐름)는 수동 QA + 가능한 부분 스냅샷.

## 엣지 / 리스크

- 구버전 회의: `summaryGlossary == nil` → 배너 숨김.
- 용어집 미사용(빈 문자열): 배너 숨김.
- 스키마 변경: optional + tolerant decoder(P1 패턴)로 안전. round-trip 테스트로 회귀 차단.
- 라이브 경로 영향 없음(저장 시점에 문자열 1개 기록만 추가).
