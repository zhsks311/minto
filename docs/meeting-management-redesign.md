# 회의록 관리 · UX 전면 개편 (에픽)

> 목표(2026-06-04, 사용자): 이전 회의를 열람·관리·export 하고, 요약을 언제든 다시 보고,
> 회의 중 전사를 잘 보이게 하며, 문서를 주면 기록·요약 품질에 활용하고, 설정에서 provider별
> 모델을 고르며, (향후) 전사 기반으로 위키/Notion/Confluence를 조회해 정보를 제공한다.
> UI는 Pencil로 처음 쓰는 사람도 쉬운 "UX 고수" 디자인. export는 최소 MD, 가능하면
> Notion/Confluence 인식 스타일. 인증은 나중, 지금은 구현 집중.

## 현재 상태 (출발점)
- 메뉴바 앱(LSUIElement). 녹음 시작=시트(topic/glossary) → FloatingWindow 전사 → 종료 시
  `handleStopRecording`이 구조화 요약 생성 + result 창 표시 + ReportService가 `~/Documents/Minto/{date}.md`에 스트리밍.
- **이전 회의를 앱에서 다시 볼 수 없음**(파일만 남음, 목록·상세 UI 없음). ← 핵심 페인.
- `MeetingSummary`(계층형, Codable) 완비. `Segment`는 Codable 아님. `Meeting`/`Report` 모델은 거의 미사용.
- SettingsView: Whisper 모델 선택 + LLM provider 로그인. **provider별 LLM 모델 선택 없음**.
- OAuth 서비스 모델: 상수화됨(kCorrectionModelDefault/Paid, kGeminiModel, kCopilotModel) — @AppStorage 연결 안 됨.

## 아키텍처 결정
- **MeetingRecord**(Codable): id, title, startedAt, durationSeconds, topic, summary: MeetingSummary,
  transcript: [Segment], hasDocument. → JSON으로 `~/Library/Application Support/Minto/meetings/{id}.json` 저장.
- **MeetingStore**(@MainActor ObservableObject): list(메타) / save / load / delete / export. `@Published meetings`.
- `Segment`에 Codable 추가.
- 종료 시 handleStopRecording → MeetingRecord 구성 → store.save + .md export.
- **메인 윈도우 신설**(메뉴바 보조 유지): 좌측 회의 목록 + 우측 상세(요약/전사 탭 = 기존 MeetingSummaryView 재사용) + export 버튼 + "새 회의".
- **Export**: `MeetingSummary.markdown()` 기반. Notion/Confluence는 표준 Markdown(헤딩·불릿·체크박스·코드)을 인식 → 표준 MD 유지 + 파일 저장/클립보드 복사. (인증 연동은 후속.)
- **문서 활용**: `MeetingContext.document` 추가 → CorrectionPrompt/SummaryPrompt에 참고자료로 주입(전사·요약 품질↑).
- **관련 정보 패널(향후)**: 회의 중 뷰에 사이드 패널 슬롯. 데이터 소스(위키/Notion/Confluence)는 후속(MCP), 지금은 UI 슬롯 + 스텁.
- **설정 모델 선택**: provider별 @AppStorage(codexModel/geminiModel/copilotModel) + SettingsView Picker. OAuth 서비스가 이 값을 읽도록.

## 단계 (각 단계 빌드·테스트·커밋, 단계 후 code-reviewer 에이전트 리뷰)
1. **영속화 foundation**: Segment Codable, MeetingRecord, MeetingStore(save/list/load/delete), handleStopRecording에서 save. (UI 없이 백본)
2. **Pencil 디자인**: 메인 윈도우(목록+상세), 새 회의(문서 첨부), 회의 중(전사+관련정보 패널), 설정(모델 선택). UX 고수 톤.
3. **메인 윈도우 UI**: 회의 목록 + 상세(요약/전사 재사용) + 새 회의 진입. 메뉴바 → 메인 윈도우 열기.
4. **Export**: MD 저장/복사(Notion/Confluence 친화). 상세에 export 버튼.
5. **설정 provider별 모델 Picker** + OAuth 서비스 @AppStorage 연동.
6. **문서 활용**: 회의 시작 시 문서 첨부/붙여넣기 → MeetingContext.document → 교정/요약 프롬프트 주입.
7. **회의 중 전사 개선 + 관련정보 패널 스텁**(데이터 소스는 후속).
8. **병렬 에이전트 리뷰 + 엣지케이스 보강**(provider none, 빈 회의, 대량 회의 목록, export 실패, 동시성 등).

## 엣지 케이스 체크리스트
- provider none/미로그인 → 요약 없이도 회의(전사) 저장·열람 가능해야.
- 빈 회의(0 segment) 저장 안 함 또는 "내용 없음"으로.
- 회의 목록 대량(수백) → 메타만 로드(lazy), 본문은 열 때.
- 저장/로드 실패(디스크·JSON 손상) → fail-soft, 목록에서 손상 항목 skip.
- 동시성: 저장은 @MainActor, 파일 IO는 백그라운드 큐.
- export 파일명 충돌·특수문자 → sanitize.
- 세션 간 상태 누수(이미 MeetingContext.clear로 처리) 유지.
- 마이그레이션: 기존 ~/Documents/Minto/*.md는 그대로 두고 신규는 store에.

## 제약 (고정)
- push 보류, 커밋 Co-Authored-By 금지, 한국어 응답, surgical, sample/ gitignore.
- 키체인 접근 테스트는 `./scripts/dev.sh test`로(adhoc 재프롬프트 방지). 앱 실행은 `./scripts/dev.sh run`.
- 병렬은 worktree 격리 또는 비충돌 파일만. codex 위임 후 고아 프로세스 확인.
