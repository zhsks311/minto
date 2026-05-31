# 세션 5 — 회의 맥락 기반 후교정

_2026-06-01_

## 프롬프트 → 작업 내용

### "교정은 문맥에 맞는 단어와 문장인지 확인하고 교정하게 하는 게 어때? ... 회의 정보를 입력할 수 있게"

과교정의 본질이 **지시 문구**("동음이의어를 맥락에 맞게 고쳐라" → 무조건 교정)임을 파악. 회의 맥락을 받아 "확신할 때만 교정"하도록 전환.

**브레인스토밍으로 결정한 사항**
- 입력: 회의 **주제(자유 텍스트) + 용어집(고유명사)**, 회의마다 새로 입력(영구 저장 아님)
- 입력 위치: **"녹음 시작" 시 뜨는 회의 시작 시트** (Settings 아님)
- 교정 규칙 3중 중복을 한 곳으로 통합

**신규 파일**

| 파일 | 내용 |
|------|------|
| `MeetingContext.swift` | 세션 단위 ObservableObject(주제/용어집) |
| `CorrectionPrompt.swift` | 순수 빌더 `build()` + 보수적 교정 규칙 (한 곳에 집중) |
| `MeetingSetupView.swift` | 회의 시작 시트 (pencil.dev로 디자인) |
| `MeetingSetupWindowManager.swift` | 시트 창 관리(`NSWindowDelegate`로 닫힘 시 상태 초기화) |
| `CorrectionPromptTests.swift` | 순수 빌더 단위 테스트 6개 (CI 실행) |

**수정 파일**
- `LLMCorrectionService`: MeetingContext 읽어 `CorrectionPrompt.build` 후 provider 위임
- provider 3종: 시그니처 `correct(instructions:userContent:)`로 통일, 각자 API 형태에만 책임 (Codex=instructions/input, Gemini=연결, Copilot=system/user)
- `MenuBarView`/`AppDelegate`/`MintoApp`: "녹음 시작" → 시트 → "시작" 시 맥락 설정 후 녹음

**보수적 교정 규칙(과교정 억제)**
- 띄어쓰기·문장부호는 항상 교정
- 고유명사는 용어집 표기로, 없으면 원문 유지
- 동음이의어는 맥락으로 확실할 때만, 애매하면 원문 유지

**codex 리뷰 반영**
- 창 X 닫기 시 입력 초기화(`windowWillClose`)
- 프롬프트 인젝션 방어: 사용자 입력(주제/용어집)을 instructions(정책)가 아닌 userContent(참고 데이터)로 분리
- UI 디자인: pencil.dev 목업 → `designs/meeting-setup.png`
