# 용어집 별칭 자동 수집 계획

## 목표

전사 교정 결과에서 원문 오인식 표현과 교정된 표기를 보수적으로 추출해 용어집에 제안으로만 축적한다. 시스템은 자동 등록하지 않고, 실제 등록은 사용자가 설정 화면에서 누른 뒤에만 수행한다.

## 공통 제약

- 앱 실행 금지.
- 검증은 `./scripts/dev.sh build`와 `./scripts/dev.sh test`만 사용한다.
- 로그에는 전사, 용어, 프롬프트 원문을 남기지 않고 개수와 길이만 남긴다.
- 저장소 변경은 디스크 저장 성공 후에만 메모리 상태를 publish한다.
- 커밋 메시지에 `Co-Authored-By`를 넣지 않는다.

## 단계별 계획

### 1. CorrectionAliasExtractor

- 공백 토큰화와 LCS 기반 diff로 원문 청크와 교정문의 치환 구간을 찾는다.
- 각 구간은 양쪽 1~3토큰만 허용한다.
- 원문 쪽은 alias, 교정문 쪽은 canonical로 반환한다.
- 한쪽은 한글을 포함하고 다른쪽은 영문 또는 숫자를 포함하는 경우만 통과시킨다.
- 구두점 제거 뒤 2자 미만이면 버린다.
- 삽입/삭제/어순 변경/대규모 재작성은 버린다.
- 검증: 단순 치환, 다토큰, 어순 변경 무시, 한영 조건 불충족 무시, 동일 텍스트 무추출 테스트.

### 2. 수집 및 축적 배선

- `LLMCorrectionService.correct` 성공 후 추출기를 호출한다.
- 추출 쌍 개수만 `Log.correction.debug`에 남긴다.
- `GlossaryStore`에 별칭 제안 축적 API를 추가한다.
- canonical이 기존 entry canonical/alias와 일치하면 아직 없는 alias만 `pendingAliases`에 축적한다.
- canonical이 없으면 기존 후보에 `suggestedAliases`를 함께 저장한다.
- `approveAliasSuggestion`은 사용자 클릭 경로에서만 entry alias에 추가한다.
- `dismissAliasSuggestion`은 제안만 제거한다.
- 검증: 축적, 중복, 상한 30, 후보 동반 별칭, snapshot 하위 호환, approve/dismiss 영속.

### 3. UI 노출

- 제안된 용어 행에 `오인식: ...`를 표시한다.
- 후보 `[추가]` 시 등록 폼 별칭 필드를 `suggestedAliases`로 프리필한다.
- 기존 용어 행에는 `별칭 제안 N` 배지를 표시하고, 클릭 시 제안 목록을 펼친다.
- 각 제안은 `[추가]`, `[무시]`만 제공하며 `.borderedProminent`는 사용하지 않는다.
- 검증: build/test로 SwiftUI 컴파일 확인. 앱 실행은 하지 않는다.

### 4. 후보 별칭 LLM 프리필

- 후보 `[추가]`로 폼을 열고 별칭 필드가 비어 있으면 백그라운드 LLM을 1회 호출한다.
- 프롬프트에는 후보 용어만 넣고 회의 내용은 넣지 않는다.
- 응답은 쉼표/줄바꿈 구분으로 1~3개만 정리해 별칭 필드에 채운다.
- 실패, provider 없음, 지연은 fail-soft로 빈 필드를 유지한다.
- 사용자가 입력을 시작했으면 LLM 결과로 덮어쓰지 않는다.
- 검증: build/test 통과.
