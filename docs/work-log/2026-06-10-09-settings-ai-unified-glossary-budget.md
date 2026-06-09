# Settings AI 통합과 용어집 예산 표시

날짜: 2026-06-10
브랜치: `release/llm-search-export-2026-06-09-rc1`
상태: 완료

## 작업 요약

검색 답변 AI를 별도 provider처럼 보이게 만들던 설정을 정리했다.
검색 답변은 전사 다듬기와 회의록 정리에 쓰는 `AI 연결` 설정을 함께 사용하며, 검색 답변 토글이 켜져 있으면 같은 provider로 자동 동기화된다.
Codex, Gemini 계정, GitHub Copilot 계정도 text generation adapter가 있으므로 검색 답변 capability를 열었다.
계정 로그인 provider에는 공식 API 키 방식이 아니며 검색 근거가 해당 계정 서비스로 전송되고, 데이터 사용과 학습 여부는 각 앱의 프라이버시 설정에서 제어해야 한다는 안내를 추가했다.

로컬 LLM 설정은 일반 사용자가 숫자 문맥 창을 직접 판단하지 않도록 `소 / 중 / 대` 프리셋으로 바꿨다.
기본값은 `중 · 4,608 tokens`이고, endpoint와 런타임 상세 설정은 고급 설정으로 접었다.
endpoint 확인은 Ollama `/api/tags`와 OpenAI 호환 `/v1/models`를 순서대로 확인해 런타임 형식을 판별한다.

용어집은 단일 입력 폼이 아니라 `개발 / 인프라 / 제품 / 조직 / 기타` 묶음으로 관리하게 바꿨다.
AI에는 전체 용어집이 아니라 선택한 용어와 직접 입력한 용어만 전달되며, resolver는 항목 수 12개 제한을 제거하고 1,200자 예산 안에서 가능한 용어를 포함한다.
프롬프트용 용어는 후보/선택 순서를 보존해 앞쪽 우선순위가 유지되도록 했다.

메인 라이브러리 헤더는 좁은 폭에서 `새 회의` 버튼이 사라지지 않도록 `ViewThatFits` 기반 2줄 레이아웃 fallback을 추가했다.

## 변경 파일

- `Sources/Minto/UI/SettingsView.swift`
  - 검색 답변 AI 선택을 기본 AI 연결과 동기화
  - 계정 로그인 provider 프라이버시 안내 추가
  - 로컬 LLM 문맥 창을 `소 / 중 / 대` 프리셋으로 변경
  - endpoint 자동 판별과 고급 설정 접기 추가
  - 용어집을 묶음 기반 UI와 1,200자 예산 안내로 변경
- `Sources/Minto/UI/MeetingSetupView.swift`
  - 회의 시작 시 용어집 후보 수와 1,200자 전달 제한 안내 강화
- `Sources/Minto/UI/MeetingLibraryView.swift`
  - 좁은 폭에서도 `새 회의` 버튼을 유지하는 responsive header 적용
- `Sources/Minto/Services/GlossaryStore.swift`
  - resolver의 12개 제한 제거
  - 1,200자 문자 예산 기반 병합 적용
  - 프롬프트 용어 생성 시 선택 순서 보존
- `Sources/Minto/Services/LLMProviderRegistry.swift`
  - 계정 로그인 provider의 검색 답변 capability 추가
- `Sources/Minto/Services/LegacyAccountLLMTextProvider.swift`
  - 계정 로그인 모델 catalog에 answer capability 추가
- `Sources/Minto/Services/LocalLLMProvider.swift`
  - 기본 문맥 창을 4,608로 변경
  - OpenAI 호환 런타임 라벨을 고급 사용자용 표현으로 정리
- `Sources/Minto/Services/MeetingSearchAnswerController.swift`
  - 검색 답변 readiness 문구를 통합 AI 연결 기준으로 정리
- `Tests/MintoTests/GlossaryStoreTests.swift`
  - resolver 문자 예산 테스트 추가/수정
- `Tests/MintoTests/LLMProviderTests.swift`
  - 계정 로그인 provider answer capability와 로컬 LLM 기본 문맥 창 테스트 추가

## 검증

- `git diff --check`
- `swift build --disable-sandbox --scratch-path /tmp/minto2-settings-test`
- `SWIFT_INDEX_STORE_ENABLE=NO swift test --disable-sandbox --scratch-path /tmp/minto2-settings-test --filter GlossaryStoreTests`
  - 10 tests passed
- `SWIFT_INDEX_STORE_ENABLE=NO swift test --disable-sandbox --scratch-path /tmp/minto2-settings-test --filter LLMProviderTests`
  - 34 tests passed
- `SWIFT_INDEX_STORE_ENABLE=NO swift test --disable-sandbox --scratch-path /tmp/minto2-settings-test --filter MeetingSearchAnswerServiceTests`
  - 13 tests passed

참고: 처음에는 세 테스트를 병렬 scratch path로 실행해 `/tmp` 용량 부족이 발생했다.
이번 작업에서 만든 scratch 디렉터리만 정리한 뒤 같은 scratch path를 재사용해 순차 검증했다.
