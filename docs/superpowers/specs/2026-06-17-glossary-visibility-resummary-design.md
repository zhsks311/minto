# 용어집 가시성 + 재요약 용어집 선택 (아이디어 1) — 설계

작성일: 2026-06-17 · 갱신: 2026-06-17 (codex 스펙 리뷰 반영)

## 배경 / 문제

루션/노션 사례: 전사엔 "루션", 요약엔 "노션"으로 정규화됨. 요약은 LLM 의역 단계라 용어집이 anchor가 아니면 희귀 고유명사를 흔한 단어로 바꾼다. 현재 사용자는:

1. 요약이 **어떤 용어집을 참고했는지 확인할 수 없고**,
2. 용어집이 잘못됐어도 **용어집을 바꿔 다시 요약할 방법이 없다**(재요약은 현재 자동 해석된 용어집을 그대로 재사용).

## 목표

- (1a) 회의록에서 요약이 사용한 용어집을 확인한다.
- (1b) 재요약 시 용어집을 다시 선택해 더 정확히 다시 요약한다.

## 비목표 (YAGNI)

- 라이브 진행 중 요약의 용어집 표시 — 저장된 회의에만 적용.
- 과거 용어집 선택값(분류/수동 origin)의 정확 복원 — 재요약은 **현재** 용어집 상태 기준.
- 분류(카테고리) 라벨 저장 — `MeetingContext`가 분류를 들고 있지 않고, 실제 용어 스냅샷이 "무엇을 썼나"를 더 정확히 답하므로 생략.
- 전사 편집 — 아이디어 2(별도 스펙).

## 핵심 통찰

요약에 들어가는 용어 블록은 **글자수 하드 상한 1,200자**(`GlossaryStore.defaultMaxCharacters`)가 걸려 있다. 따라서 "요약 당시 실제 사용된 용어 문자열"은 **≤1.2KB의 고정 스냅샷**이며, 저장해도 부담이 없다(전사 34KB~449KB 대비 <1%). 전역 용어집이 이후 바뀌어도 스냅샷은 불변 → "루션 있었나?"를 정확히 검증.

주의 — **용어 개수 제한은 경로마다 다르다**:
- 자동 후보 경로(`candidates(for:limit:8)`): 관련 top-8.
- 선택 UI 경로(시작/임포트/재요약 다이얼로그): 사용자가 선택한 **분류 전체**의 엔트리(`entries(inCategories:)`) + 수동 용어를 1,200자 cap에 맞춰 사용.

## 데이터 모델

`MeetingRecord`에 optional 필드 1개 추가:

```
public var summaryGlossary: String?
// 요약 생성 시 GlossaryContextResolver가 만든 줄 단위 resolved glossary 문자열(≤1,200자)의 불변 스냅샷.
// 주의: "프롬프트에 최종 렌더링된 문장"이 아니라, 요약에 투입된 resolved glossary 줄 텍스트다.
```

- optional + 기존 `schemaVersion`/tolerant decoder(P1) 덕분에 **하위호환**: 구버전 회의 JSON은 `nil`로 로드. `init(from:)`/`CodingKeys`에 `decodeIfPresent`로 추가.
- **schemaVersion bump 불필요** — additive optional field라 기존 디코더가 그대로 수용.
- **빈 값은 `nil`로 normalize**해서 저장(빈 문자열 저장 금지). UI 표시 분기를 단순화.
- **로그 금지** — 이 문자열(용어 내용)은 `Log`에 남기지 않는다(민감/내용 값). 길이/개수만 기록 가능.

### 스냅샷 캡처 지점 (요약을 만드는 production 저장 경로 — 3개, complete)

1. **라이브 종료 요약** — `AppDelegate.handleStopRecording()` → `viewModel.finalizeMeeting()` 후 `AppDelegate.makeRecord(...)` → `MeetingRecordFactory.makeRecord(...)`로 record 생성 → `MeetingStore.shared.save(record)`. 이 경로에서 `MeetingContext.glossary`(resolved 문자열)를 `summaryGlossary`에 기록.
2. **파일 임포트 요약** — `MeetingFileImportUseCase.importFile(...)`가 `SummaryGenerationContext(glossary:)`로 요약 후 `MeetingRecordFactory.makeRecord(...)`로 저장. `context.glossary`를 기록.
3. **재요약** — `MeetingSummaryRetryUseCase.retry(record:glossary:)`(아래)가 주입된 glossary로 재요약 후 `updated.summary`와 함께 `updated.summaryGlossary = injectedGlossary` 기록.

(`generateIncremental`은 running summary만 갱신하고 `MeetingRecord`를 만들지 않으므로 캡처 대상 아님.)

**스냅샷 갱신 규칙**: 새 스냅샷은 **요약 생성 성공 + store save 성공**일 때만 반영. 실패 시 기존 요약/스냅샷 그대로 유지(fail-soft).

## UI — 1a 표시 (요약 카드 상단 배너)

`MeetingLibraryView` 회의 상세, 요약 섹션 상단:

- **스냅샷 있음**: `📑 요약에 사용된 용어 N개 ▸` (N = 스냅샷 줄 수). `DisclosureGroup`로 평소 접힘, 펼치면 줄 목록 그대로.
- **스냅샷 없음**(구버전/`nil`): 배너 숨김(노이즈 방지).

## UI — 1b 재요약 용어집 다이얼로그

회의 상세의 재요약 동작을 **선택 다이얼로그 경유**로 변경:

- 기존 재요약 진입점은 **2개**(structured summary header의 "다시 요약" 버튼 + plain fallback banner의 버튼) — **둘 다 보존**하고 둘 다 이 다이얼로그를 연다.
- sheet 내용: 기존 `GlossarySetSelectionSection`을 재사용(전역 분류 체크 + 회의별 수동 용어) + **"이전 요약에 사용된 용어"를 read-only로 표시**(현재 선택과 혼동 방지).
- 미리채움: `GlossarySetSelectionPersistence.load`로 **현재 살아있는** 선택 상태. 수동 용어 칸은 빈 채 시작.
- **state 소유권**: sheet가 `selectedCategories`, `manualGlossary`, `isSubmitting`, `error`를 **local draft로 소유**. 기존 시작 화면의 `.onChange → saveSelection` 자동 영속화를 그대로 쓰지 말 것 — **취소 시 전역 `UserDefaults`를 변경하지 않는다**(local draft, confirm 때만 반영 또는 미반영 정책 명시).
- 확인("다시 요약") → 선택(분류 전체 + 수동)을 시작 화면과 동일 로직으로 glossary 문자열 해석 → `MeetingSummaryRetryUseCase.retry(record:glossary:)`에 **명시 주입** → 성공 시 요약 + `summaryGlossary` 동시 갱신·저장.
- 취소 → 아무 변화 없음(요약/스냅샷/전역 선택 모두 불변).
- **fail-soft**: 재요약 실패 시 기존 요약/스냅샷 유지, 기존 `retryError` 패턴으로 에러 표시.

### 재요약 use-case 변경

현재 `MeetingSummaryRetryUseCase.retry(record:)`는 내부에서 resolver를 호출한다. **`retry(record:glossary:)` overload를 추가**해 다이얼로그가 해석한 glossary 문자열을 명시 주입한다(가장 작은 변경). 인자 없는 기존 `retry(record:)`는 자동 해석 동작 유지(하위호환).

## 컴포넌트 경계

- `GlossarySetSelectionSection` — 이미 binding 기반 재사용 가능(`selectedCategories`/`manualGlossary` 바인딩, `GlossaryStore`는 주입 기본값 `.shared`). 추출/리팩터 불필요.
- 재요약 다이얼로그 — 위 섹션 + 이전 스냅샷 read-only 표시를 담는 신규 sheet(예: `ReSummaryGlossarySheet`). 입력: 현재 선택 상태, record(이전 스냅샷 포함). 출력: 확정된 glossary 문자열.
- 배너 — `MeetingLibraryView` 내 소형 뷰(또는 신규 `SummaryGlossaryBanner`).

## 영향 받는 파일 (예상)

- `Models/MeetingRecord.swift` — 필드 추가 + 디코더.
- `App/AppDelegate.swift`(`handleStopRecording`/`makeRecord`), `Services/MeetingRecordFactory.swift` — 라이브 스냅샷 기록.
- `Services/MeetingFileImportUseCase.swift` — 임포트 스냅샷 기록.
- `Services/MeetingSummaryRetryUseCase.swift` — `retry(record:glossary:)` overload + 스냅샷 기록.
- `UI/MeetingLibraryView.swift` — 배너 + 재요약 진입점 2개 → 다이얼로그.
- 신규: `UI/ReSummaryGlossarySheet.swift`(및 필요 시 `UI/SummaryGlossaryBanner.swift`).

## 테스트

- `MeetingRecord` round-trip: 새 필드 보존 + 필드 없는 구버전 JSON 정상 로드(nil) + 빈 값 nil normalize.
- 각 요약 경로(라이브 makeRecord / 임포트 / 재요약)가 `summaryGlossary`를 채우는지.
- `retry(record:glossary:)`가 주입 glossary로 재요약하고, **성공+save 시에만** 스냅샷을 갱신하는지(실패 시 유지).
- UI(배너 표시/숨김, 다이얼로그 흐름, 취소 시 UserDefaults 불변)는 수동 QA + 가능한 부분 스냅샷.

## 엣지 / 리스크

- 구버전 회의: `summaryGlossary == nil` → 배너 숨김.
- 용어집 미사용(빈): nil normalize → 배너 숨김.
- 스키마 변경: optional + tolerant decoder(P1)로 안전, bump 불필요. round-trip 테스트로 회귀 차단.
- 라이브 경로 영향: 저장 시점에 문자열 1개 기록만 추가(동작 변화 없음).
- 재요약 sheet의 전역 선택 오염: local draft 정책으로 차단(위 명시).
