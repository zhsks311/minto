# Settings 모델 선택 안내 정리

날짜: 2026-06-10
브랜치: `release/llm-search-export-2026-06-09-rc1`
상태: 완료

## 작업 요약

로컬 LLM 설정에서 `AI 모델` 직접 입력칸과 `설치된 모델` 선택이 동시에 보여 같은 값을 두 번 설정해야 하는 것처럼 보이던 문제를 정리했다.
Ollama 설치 모델을 정상 조회한 경우에는 `사용할 모델` 선택만 보여주고, 모델명 직접 입력칸은 숨긴다.
설치 모델을 조회할 수 없거나 OpenAI 호환 서버를 쓰는 경우에만 `모델 ID` 직접 입력칸을 보여준다.

`고급 설정`은 작은 disclosure 화살표만 누르는 구조에서 벗어나, 텍스트를 포함한 행 전체가 클릭 가능한 버튼이 되도록 바꿨다.
오른쪽에는 `endpoint, 런타임` 보조 설명을 붙여 접힌 영역에 무엇이 있는지도 알 수 있게 했다.

API provider와 계정 로그인 provider의 모델 선택도 `AI 모델` 대신 `사용할 모델`로 바꿨다.
기본 추천 모델을 그대로 써도 된다는 안내를 붙이고, 직접 모델 ID 입력은 `목록에 없는 모델 ID 직접 입력` 접힘 영역으로 내렸다.

## 변경 파일

- `Sources/Minto/UI/SettingsView.swift`
  - 로컬 LLM 설치 모델 조회 성공 시 직접 입력칸 숨김
  - 로컬 LLM 직접 입력 안내를 Ollama/OpenAI 호환 서버별로 분리
  - 고급 설정을 전체 행 클릭 버튼으로 변경
  - API provider 모델 선택 안내와 직접 입력 접힘 영역 추가
  - 계정 로그인 provider 모델 선택 설명 추가

## 검증

- `swift build --disable-sandbox --scratch-path /tmp/minto2-settings-test`
- `git diff --check`
- `./scripts/dev.sh run`
  - Claude API 화면에서 `사용할 모델` 안내와 직접 입력 접힘 영역 확인
  - 로컬 LLM 화면에서 설치 모델 조회 성공 시 모델 ID 입력칸이 사라지고 `사용할 모델` 선택만 표시되는 것 확인
  - `고급 설정` 행이 텍스트 포함 큰 클릭 영역으로 표시되는 것 확인

참고: 로컬 LLM 화면 확인을 위해 `com.minto.app`의 provider 값을 잠시 `local`로 바꿨고, 검증 후 기존 `claude_api` 값으로 되돌렸다.
