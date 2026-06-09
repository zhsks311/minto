# Minto2 기능 정의서

작성일: 2026-06-09
상태: 초안

## 1. 서비스 목적

Minto2는 Mac에서 회의를 기록하고, 전사와 요약을 사용자가 다시 찾고 공유할 수 있는 회의 지식 도구다.

핵심 가치는 다음이다.

- 회의 중 발화를 가능한 한 빠르게 전사한다.
- 전사 결과를 회의 문맥에 맞게 읽기 좋은 회의록으로 정리한다.
- 저장된 회의를 검색하고, 필요하면 관련 근거를 바탕으로 답변을 생성한다.
- Confluence, Notion 같은 업무 문서와 연결해 회의 전후 맥락을 잇는다.
- 개인정보와 로컬 우선 흐름을 존중하면서, 사용자가 선택한 경우에만 외부 LLM/API를 사용한다.

## 2. 핵심 사용자 흐름

### 2.1 실시간 회의 기록

1. 사용자가 새 회의를 시작한다.
2. 회의 주제, 이번 회의 용어, 참고 문서를 선택적으로 입력한다.
3. 앱이 마이크 또는 선택한 입력 소스를 전사한다.
4. 전사는 회의 목록의 현재 회의 항목에 바로 쌓인다.
5. 사용자는 필요할 때 오버레이를 열어 전사 흐름을 볼 수 있다.
6. 회의 종료 시 회의 기록이 저장되고, 요약/목차/회의 내용 정리/결정사항/할 일/미해결 질문/전사를 볼 수 있다.

### 2.2 사후 회의록 작성

1. 사용자가 음성 또는 영상 파일을 넣는다.
2. 앱이 파일을 16kHz mono PCM으로 변환한다.
3. 기존 전사, 교정, 요약, 저장 pipeline을 재사용한다.
4. 결과는 일반 회의와 동일하게 회의 목록에 저장된다.

### 2.3 회의 검색과 답변

1. 사용자가 회의 목록에서 키워드나 질문을 입력한다.
2. 앱은 저장된 회의의 요약, 전사, 결정사항, 할 일, 미해결 질문을 검색한다.
3. 임베딩 인덱스가 준비된 경우 semantic search를 함께 사용한다.
4. 사용자가 답변 생성을 요청하면, 검색된 근거 chunk만 LLM에 전달한다.
5. 답변은 출처 회의, 섹션, 시간 정보와 함께 표시한다.

### 2.4 내보내기

1. 사용자가 회의 상세에서 내보내기를 누른다.
2. 앱은 선택지를 보여준다.
   - Markdown 파일
   - 클립보드 복사
   - Confluence
3. Confluence token이 없으면 Confluence 선택지는 비활성화하고 설정으로 안내한다.
4. token이 있으면 내보낼 위치와 제목을 확인한 뒤 publish한다.

## 3. 현재 기능

- 메뉴바 앱 및 회의 목록 메인 윈도우
- 실시간 마이크 입력
- WhisperKit 기반 로컬 STT
- Apple SpeechAnalyzer, SFSpeechRecognizer 계열 STT 후보
- VAD 기반 chunking과 preview/final transcript 분리
- 전사 오버레이 표시와 접기
- 회의 시작 시 주제, 용어집, Confluence 문맥 입력
- LLM 기반 전사 교정
- LLM 기반 증분/최종 요약
- 회의 저장 JSON
- 회의 목록 검색
- 관련 문서 탭에서 Notion/Confluence 조회
- Markdown 내보내기
- 비밀값 저장은 기본 Keychain을 사용하고, 개발 opt-in으로 file 기반 SecretStore를 사용할 수 있음

## 4. 확장 예정 기능

- 전사 자동 교정과 회의 요약/구조화 설정 분리
- 로컬 LLM provider
- GPT, Gemini, Claude, OpenRouter 공식 API provider
- provider별 모델 목록 fetch/cache와 수동 입력 fallback
- 전역 용어집 관리와 회의별 용어 선택
- 저장 회의 embedding index
- 검색 결과 기반 LLM 답변 생성
- Confluence token 발급 가이드
- Confluence 내보내기
- 음성/영상 파일 입력
- 시스템 사운드 입력

## 5. 데이터 원칙

- 원본 전사, 교정 전사, 요약, export 결과는 구분한다.
- 검색과 내보내기에는 사용자가 읽기 쉬운 정규화 전사를 사용한다.
- CER 같은 STT 정확도 측정에는 원문과 정규화/교정을 분리한다.
- 외부 LLM으로 전송되는 데이터는 UI에서 사용자가 이해할 수 있어야 한다.
- token, prompt, transcript 원문은 로그에 남기지 않는다.
- 저장 schema 변경은 backward-compatible 하거나 migration/rollback 계획을 둔다.

## 6. 아키텍처 경계

기본 방향은 다음이다.

> Domain/Core <- Application/Use-case <- Infrastructure/Adapter <- UI

- Domain/Core
  - 전사 정규화, 용어 매칭, 검색 scoring, export 변환 규칙
  - IO, HTTP, Keychain, UserDefaults에 직접 의존하지 않는다.
- Application/Use-case
  - 전사, 교정, 요약, 검색, 내보내기 workflow orchestration
  - retry, timeout, idempotency, job 상태 전이를 소유한다.
- Infrastructure/Adapter
  - LLM provider, Confluence, Notion, Keychain, 파일 변환, embedding backend
  - domain rule을 넣지 않는다.
- UI
  - 상태 표시와 사용자 명령 전달
  - prompt 생성, provider request 구성, 저장 schema 변환을 직접 하지 않는다.

## 7. 사용자 경험 원칙

- 첫 화면은 새 회의, 검색, 파일로 회의록 만들기를 바로 이해할 수 있어야 한다.
- 설정은 progressive disclosure를 사용한다.
- 비개발자에게 모델명만 던지지 않는다. 추천, 빠름, 품질 우선, 저비용, 로컬 처리 같은 언어를 사용한다.
- Confluence, LLM API, 시스템 사운드처럼 권한/토큰이 필요한 기능은 상태와 다음 행동을 분명히 보여준다.
- 검색 답변은 반드시 근거 회의와 시간을 함께 보여준다.
- 클라우드로 나가는 기능과 기기 안에서 처리되는 기능을 구분한다.

## 8. 완료 기준

이 문서의 기능은 다음 증거가 있을 때 완료로 본다.

- 관련 코드가 계획된 Phase에 맞게 구현되어 있다.
- 단위/통합 테스트가 통과한다.
- UI 변경은 Pencil 산출물 또는 앱 실행 QA 증거가 있다.
- benchmark가 필요한 기능은 `docs/benchmark/`에 결과가 있다.
- 아키텍처 변경은 ADR과 코드리뷰 기록이 있다.
- 작업 내용은 `docs/work-log.md`와 세션별 `docs/work-log/` 문서에 기록되어 있다.
