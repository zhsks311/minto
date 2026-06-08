# LLM/Search/Export 확장 구현 시작

날짜: 2026-06-09
브랜치: `feature/llm-correction-search-export`
상태: 진행 중

## 작업 요약

대규모 기능 확장을 바로 코드에 넣기 전에, 구현 기준이 되는 기능 정의와 프로젝트 컨벤션을 정리했다.
이후 첫 코드 슬라이스로 LLM 공급자 공통 계약을 추가해 로컬 LLM, GPT, Gemini, Claude, OpenRouter, Copilot을 같은 방식으로 붙일 수 있는 기반을 만들었다.

## 변경 파일

- `docs/service-definition.md`
  - 서비스 목적, 현재 기능, 확장 예정 기능, 데이터/UX/아키텍처 원칙 정의
- `AGENTS.md`
  - Codex/agent용 프로젝트 작업 기준
- `CLAUDE.md`
  - Claude/Codex 공유 프로젝트 컨벤션
- `docs/adr/0000-template.md`
  - ADR 작성 템플릿
- `docs/adr/0001-llm-search-export-expansion-governance.md`
  - 확장 작업의 아키텍처 거버넌스 결정
- `docs/work-log.md`
  - 이번 세션 인덱스 추가
- `Sources/Minto/Services/LLMProvider.swift`
  - 교정/요약/답변에 공통으로 쓸 LLM 공급자 프로토콜과 요청/응답/모델 정보 타입 추가
- `Sources/Minto/Services/LLMCorrectionService.swift`
  - 기존 "OpenAI Codex" 표시를 사용자에게 더 명확한 "GPT 계정 로그인"으로 변경
- `Tests/MintoTests/LLMProviderTests.swift`
  - 공급자 표시명, 로컬/클라우드 구분, 오류 메시지 테스트 추가

## 검증 계획

- `git diff --check` 통과
- `swift test --disable-sandbox --scratch-path /tmp/minto2-llm-provider-test --filter LLMProviderTests` 통과
- `swift build --disable-sandbox --scratch-path /tmp/minto2-llm-provider-build` 통과
- 문서 경로와 링크 확인
- 기존 경고:
  - `MicrophoneSource.swift`의 `nonisolated(unsafe)` 관련 경고
  - 일부 기존 테스트 파일의 미사용 변수 경고

## 다음 단계

1. 교정 설정을 새 LLM 공급자 계약으로 연결
2. API key 기반 GPT/Gemini/Claude/OpenRouter adapter 추가
3. 모델 목록 조회 실패 시 수동 입력 fallback과 UX 문구 추가
