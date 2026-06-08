# LLM/Search/Export 확장 구현 시작

날짜: 2026-06-09
브랜치: `feature/llm-correction-search-export`
상태: 진행 중

## 작업 요약

대규모 기능 확장을 바로 코드에 넣기 전에, 구현 기준이 되는 기능 정의와 프로젝트 컨벤션을 정리했다.

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

## 검증 계획

- `git diff --check`
- 문서 경로와 링크 확인
- 문서만 변경했으므로 Swift build/test는 다음 코드 변경 커밋에서 실행

## 다음 단계

1. Phase 1 상세 구현 시작
2. 교정/요약 설정 분리와 provider adapter skeleton 추가
3. 관련 테스트 추가 후 Swift build/test 실행
