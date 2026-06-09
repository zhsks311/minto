# Local LLM Ollama 설치 모델 조회

날짜: 2026-06-09
브랜치: `release/llm-search-export-2026-06-09-rc1`
상태: 완료

## 작업 요약

로컬 LLM 설정에서 endpoint와 모델 ID를 직접 맞춰야 해서 연결 성공 여부를 알기 어려운 문제를 개선했다.
Ollama 런타임은 `/api/tags`로 설치 모델 목록을 조회하고, 설정 화면에서 설치된 모델 picker와 조회 상태를 보여준다.
선택한 모델이 설치 목록에 있으면 로컬 연결 상태를 `설치 모델 확인됨`으로 표시하고, 목록에 없으면 `모델 확인 필요` 상태로 내려서 사용자가 오입력을 바로 알 수 있게 했다.

OpenAI 호환 chat completions 런타임은 표준 설치 모델 목록 API가 없으므로 기존처럼 직접 모델 ID를 입력하게 유지하고, 그 한계를 설정 문구로 명확히 표시한다.

## 변경 파일

- `Sources/Minto/Services/LocalLLMProvider.swift`
  - Ollama `/api/tags` 모델 catalog 조회 추가
  - 설치 모델의 parameter size, quantization, size 정보를 모델 설명에 반영
  - 조회 실패 시 기존 수동 모델 ID fallback 유지
  - 설정 모델이 설치 목록에 없거나 설치 모델이 비어 있을 때 경고 반환
- `Sources/Minto/UI/SettingsView.swift`
  - 로컬 LLM 설정에 `설치된 모델` picker와 `설치 모델 조회/새로고침` 버튼 추가
  - Ollama 모드에서 endpoint 기준으로 모델 목록 자동 조회
  - 선택 모델이 live catalog에 있을 때만 로컬 런타임 상태를 연결됨으로 표시
  - OpenAI 호환 런타임은 직접 입력 모델임을 명시
- `Tests/MintoTests/LLMProviderTests.swift`
  - Ollama 설치 모델 조회 성공 테스트 추가
  - 설정 모델 미설치 경고 테스트 추가
  - `/api/tags` 실패 시 수동 모델 fallback 테스트 추가
  - 기존 local provider route 테스트가 실제 Ollama 상태에 의존하지 않도록 조정

## 검증

- `git diff --check`
- `swift test --disable-sandbox --scratch-path /tmp/minto2-local-llm-model-discovery-test --filter LLMProviderTests`
  - 33 tests passed
- `swift build --disable-sandbox --scratch-path /tmp/minto2-local-llm-model-discovery-build`
- live Ollama `/api/tags`
  - `llama3.1:8b`
  - `qwen2.5:3b`
  - `deepseek-r1:8b`
