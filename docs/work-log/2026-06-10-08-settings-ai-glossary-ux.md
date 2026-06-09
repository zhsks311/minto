# Settings AI/Glossary UX 정리

날짜: 2026-06-10
브랜치: `release/llm-search-export-2026-06-09-rc1`
상태: 완료

## 작업 요약

설정 화면에서 검색 답변 AI 선택과 검색 답변 연결 설정이 멀리 떨어져 보여 같은 기능인지 알기 어려운 문제를 정리했다.
검색 답변 provider 선택, 전송 안내, 로컬/API 연결 설정을 `검색 답변` 토글 바로 아래에 함께 배치했다.
전사 다듬기나 회의록 정리에서 사용하는 일반 AI 연결은 별도 `AI 연결` 섹션으로 유지하되, 검색 답변이 같은 provider를 쓰는 경우에는 중복 설정 대신 공유 안내만 보여준다.

검색 답변 provider가 과거 저장값으로 Codex/Copilot/Gemini 계정 로그인 계열에 남아 있으면 설정 진입 시 answer 지원 provider로 정규화한다.
로컬 LLM이 설정되어 있으면 로컬 LLM을 우선 fallback으로 선택하고, 없으면 GPT API로 fallback한다.

용어집 추가 폼은 긴 placeholder가 실제 입력과 겹쳐 보이는 문제를 줄이기 위해 각 필드를 `라벨 + 입력칸 + 도움말` 구조로 분리했다.
macOS Form의 2열 자동 배치가 입력칸을 좁게 만드는 문제는 용어집 필드만 직접 그려 전체 폭 입력칸으로 정리했다.

## 변경 파일

- `Sources/Minto/UI/SettingsView.swift`
  - 검색 답변 provider와 연결 설정을 같은 위치에 배치
  - 검색 답변은 로컬 LLM/API provider만 지원한다는 안내 추가
  - 검색 답변 provider 저장값 정규화 추가
  - 용어집 추가 폼을 라벨, 전체 폭 입력칸, 도움말 단위로 재구성
- `Sources/Minto/Services/MeetingSearchAnswerController.swift`
  - 검색 답변 설정 안내 문구에 로컬 LLM을 포함

## 검증

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-settings-glossary-ux-build-2`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-settings-glossary-ux-test-2 --filter GlossaryStoreTests`
  - 10 tests passed
- `swift test --disable-sandbox --scratch-path /tmp/minto2-settings-search-answer-ux-test --filter MeetingSearchAnswerServiceTests`
  - 13 tests passed
- `./scripts/dev.sh run`
  - 설정 화면에서 용어집 추가 폼의 입력칸 겹침 없음 확인
  - 검색 답변 ON 상태에서 provider와 연결 설정이 같은 블록에 표시됨 확인
