# Minto2 책을 연속 교재형 서사로 바꾸는 계획

작성 기준일: 2026-06-26  
범위: `docs/book/` 산출물만 정리한다. 앱 코드, 무관한 리포트, 무관한 디자인 파일은 건드리지 않는다.

## Planning status

이 문서는 실행 계획이다. 이 단계에서는 `docs/book/minto2-speech-ai-study-book.md`, `docs/book/source-matrix.md`, `docs/book/index.html`의 실제 내용이 아직 바뀌지 않은 것이 정상이다. 리뷰는 현재 tree의 구현 완료 여부가 아니라, 아래 실행 계획이 사용자의 요구를 충족할 만큼 구체적이고 검증 가능한지를 기준으로 한다.

## RALPLAN-DR

### Principles

- 읽는 순서가 곧 학습 순서여야 한다. 핵심 개념을 뒤쪽 부록에 미루지 않는다.
- 쉬운 설명은 유지하되, STT/화자분리/검색/런타임의 경계를 흐리지 않는다.
- 사실 주장과 학습용 예시는 분리한다. 예시는 반드시 예시로 보이게 쓴다.
- 정본은 Markdown이다. HTML은 같은 내용을 읽기 좋게 렌더한 결과물이어야 한다.
- 출처 매트릭스는 유지한다. 새 주장이나 앞당겨진 설명은 추적 가능해야 한다.

### Decision Drivers

- `top-to-bottom` 가독성: 부록을 읽기 전에 핵심 개념이 먼저 나와야 한다.
- 최소 파일 표면: 기존 정본/HTML/출처표/기존 자산을 최대한 재사용한다.
- 검증 가능성: 내용 재배치 후에도 source-matrix로 근거 추적이 가능해야 한다.

### Viable Options

| 옵션 | 접근 | 장점 | 단점 |
|---|---|---|---|
| A. 선형 서사로 재배치 + 부록 레이블 제거 | 1~10장을 본문 흐름으로 다듬고, 11장 신경망 부록은 각 장으로 흡수하며, 12장은 일반 마지막 장으로 바꾼다 | 읽는 흐름이 가장 자연스럽고 현재 요청과 정확히 맞는다 | 편집량이 가장 많다 |
| B. 현재 목차 유지 + 장별 연결문만 강화 | appendices는 거의 그대로 두고 본문 곳곳에 참조만 추가한다 | 변경량이 적다 | 사용자가 원한 “교재처럼 읽히는 맛”이 약하다 |

선택: **A**. 현재 목표는 참고문서가 아니라 연속 교재다. 최종 목차에는 `부록`이라는 장 제목을 남기지 않는다.

## 실행 계획

### 1) 서사 구조를 먼저 다시 짠다

- `docs/book/minto2-speech-ai-study-book.md`의 장별 역할을 다시 배치한다.
- 핵심 용어는 처음 필요해지는 장에서 바로 설명한다.
- `11. 신경망 원리 부록`은 최종 목차에서 제거한다. 핵심 설명은 3, 6, 8, 9, 10장으로 흡수한다.
- `12. 더 고려할 수 있는 기술 부록`은 `11. 다음 기술을 고를 때 보는 기준`이라는 일반 마지막 장으로 바꾼다.
- `docs/book/source-matrix.md`의 `장별 근거 배치`도 새 목차에 맞게 재작성한다. 11/12장 매핑을 그대로 두지 않는다.

### 2) 장마다 연결 문장과 예시를 넣는다

- 각 장의 첫 문단은 “이 장을 읽으면 무엇을 이해하게 되는가”를 바로 말한다.
- 이야기/예시는 학습용 예시로만 쓴다.
- 예시는 프로젝트 사실로 보이지 않게 짧고 명시적으로 쓴다.
- 용어는 한 번만 풀어 쓰고, 이후에는 같은 표현을 유지한다.
- humanize 기준은 factual draft 이후에 적용한다. 의미, 수치, 고유명사, 기술 경계는 바꾸지 않는다.

### 3) 기존 자산과 출처표를 재사용한다

- `docs/book/assets/pipeline-map.svg`, `speech-model-path.svg`, `diarization-timeline.svg`, `correction-summary-boundary.svg`, `embedding-space.svg`, `runtime-boundary-map.svg`는 우선 그대로 쓴다.
- 새 그림은 꼭 필요할 때만 추가한다. 기본 계획은 무추가다.
- `docs/book/source-matrix.md`는 장 재배치에 맞춰 `장별 근거 배치`를 새 목차 기준으로 정리한다.
- 새 주장이나 새 비교표가 생기지 않으면 출처 범위를 넓히지 않는다.

### 4) Markdown을 기준으로 HTML을 다시 맞춘다

- `docs/book/index.html`은 `docs/book/minto2-speech-ai-study-book.md`를 반영한 렌더 결과로만 유지한다.
- 수동 HTML 편집은 하지 않는다.
- Markdown 수정 뒤에는 기존 pandoc 렌더 명령으로 `docs/book/index.html`을 다시 생성한다.
- 목차, 이미지 경로, 표 구조, 장 순서를 다시 확인한다.

### 5) 최종 QA를 한 번에 끝낸다

- 읽기 흐름이 부록 의존 없이 성립하는지 확인한다.
- 기술 용어가 chapter-to-chapter로 일관되게 이어지는지 확인한다.
- 모든 비자명한 주장과 표가 source-matrix로 추적되는지 확인한다.
- `docs/book/minto2-speech-ai-study-book.md`, `docs/book/source-matrix.md`, `docs/book/index.html`에서 낡은 `신경망 원리 부록`, `더 고려할 수 있는 기술 부록` 제목이 사라졌는지 확인한다.
- 재생성된 HTML diff가 Markdown 구조 변경과 대응되는지 확인한다.
- 기존 이미지 경로와 TOC 앵커가 깨지지 않는지 확인한다.

## 파일 영향

- [minto2-speech-ai-study-book.md](/Users/d66hjkxwt9/Idea/private/minto2/docs/book/minto2-speech-ai-study-book.md)
- [index.html](/Users/d66hjkxwt9/Idea/private/minto2/docs/book/index.html)
- [source-matrix.md](/Users/d66hjkxwt9/Idea/private/minto2/docs/book/source-matrix.md)
- [book.css](/Users/d66hjkxwt9/Idea/private/minto2/docs/book/assets/book.css) 필요 시만

## Acceptance Criteria

- 최종 목차에 `부록` 제목이 남지 않는다.
- 마지막 장 제목은 `11. 다음 기술을 고를 때 보는 기준`이다.
- 신경망 핵심 개념은 처음 필요한 장에서 설명된다. `학습/추론/attention/token/embedding`을 읽기 위해 뒤쪽 장으로 점프하지 않아도 된다.
- 첫 읽기에서 1~10장만으로 STT, VAD, diarization, correction, RAG, runtime의 기본 흐름을 따라갈 수 있다.
- 마지막 후보 기술 장은 appendix가 아니라 “앞에서 배운 기준으로 다음 기술을 읽는 법”으로 동작한다.
- 학습용 예시는 모두 예시로 읽히며, 프로젝트 사실과 혼동되지 않는다.
- 각 장 도입부는 “학습 약속 + 짧은 예시” 구조를 가진다. 예시는 `예를 들어`, `가상의 회의 상황`, `비유하면`처럼 프로젝트 사실이 아님을 드러낸다.
- 기술 주장, 수치, 고유명사, 모델 비교는 source-matrix 근거 없이 새로 추가하지 않는다.
- `docs/book/index.html`이 `docs/book/minto2-speech-ai-study-book.md`의 새 구조를 그대로 반영한다.
- HTML diff가 Markdown 정본 변경과 대응되며, 수동 HTML 전용 변경이 없다.
- source-matrix가 새 목차 기준으로 주요 주장과 비교표의 근거를 계속 추적한다.
- 기존 6개 이미지 자산은 경로 깨짐 없이 재사용된다.
- `docs/book/` 밖의 파일은 변경하지 않는다.

## Verification

- Markdown 기준으로 목차를 훑어보며, `부록` 제목이 사라졌는지 확인한다.
- 핵심 용어가 처음 등장하는 장에 바로 풀려 있는지 본다.
- 기존 렌더 명령으로 HTML을 재생성한다: `pandoc docs/book/minto2-speech-ai-study-book.md --standalone --toc --toc-depth=2 --metadata title=\"Minto2 음성 AI 기술 복습서\" --metadata lang=ko --css assets/book.css --output docs/book/index.html`.
- `rg -n \"신경망 원리 부록|더 고려할 수 있는 기술 부록\" docs/book/minto2-speech-ai-study-book.md docs/book/source-matrix.md docs/book/index.html`가 매치되지 않아야 한다.
- `rg -n \"부록|신경망 원리 부록|더 고려할 수 있는 기술 부록\" docs/book/minto2-speech-ai-study-book.md docs/book/source-matrix.md docs/book/index.html`는 최종 문맥에서 0건이어야 한다. 과거 제목 설명이 꼭 필요하면 별도 변경 이력 문맥에만 허용한다.
- `rg -n \"11\\. 다음 기술을 고를 때 보는 기준\" docs/book/minto2-speech-ai-study-book.md docs/book/source-matrix.md docs/book/index.html`가 Markdown과 HTML 쪽에서 새 최종 장 제목을 확인해야 한다.
- `git diff -- docs/book/index.html`을 보고 HTML 변경이 Markdown 재생성 결과와 맞는지 확인한다.
- HTML 렌더본에서 TOC, 표, 이미지, 앵커가 정상인지 확인한다.
- source-matrix와 본문을 대조해 새로 앞당겨진 설명이 빠진 근거 없이 등장하지 않는지 점검한다.
- `git diff --check`로 문서 형식 오류를 확인한다.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| 서사가 길어져 보고서처럼 다시 보일 수 있음 | 각 장 첫머리를 짧게 유지하고, 예시는 1~2개만 둔다 |
| 정의를 앞당기다 보면 중복 설명이 생길 수 있음 | 한 용어는 처음 한 번만 풀고 이후에는 같은 표현을 반복한다 |
| source-matrix가 본문 재배치와 어긋날 수 있음 | `장별 근거 배치` 표를 새 목차 기준으로 다시 쓴다 |
| 새 이미지가 범위를 키울 수 있음 | 기본적으로 기존 6개 자산만 재사용하고, 새 그림은 보류한다 |

## ADR

### Decision

`docs/book/minto2-speech-ai-study-book.md`를 단일 정본으로 유지하되, `부록` 장을 제거하고 본문 전체를 선형 교재 서사로 다시 쓴다. 신경망 기초는 처음 필요한 장에 흡수하고, 후보 기술은 마지막 일반 장으로 재구성한다. `docs/book/index.html`은 이 정본을 그대로 렌더한 결과로 맞춘다.

### Drivers

- top-to-bottom 읽기 경험
- 부록으로 점프하지 않아도 되는 개념 설명
- 최소 파일 표면과 유지보수성
- 기존 source-matrix 중심의 검증 discipline 유지

### Alternatives considered

- B. 현재 appendix 중심 구조를 유지하고 참조만 늘리는 방법
- C. 장별 파일로 분리하는 방법

### Why chosen

- B는 변경량이 작지만, 사용자가 원하는 “부록이 아닌 연속 교재” 감각을 충분히 만들기 어렵다.
- C는 장기 유지보수에는 좋지만, 이번 요청의 범위를 넘는다.
- A는 지금 있는 구조를 가장 적은 방향 전환으로 교재형으로 바꾼다.

### Consequences

- 장 사이 연결이 좋아진다.
- 편집량은 늘지만, 완성 후 읽는 비용이 줄어든다.
- 근거 추적을 위해 source-matrix의 장별 매핑 재작성이 필수다.

### Follow-ups

- 본문을 다시 읽고도 마지막 후보 기술 장이 appendix처럼 튀면, 장 앞의 연결 서사를 더 강화하거나 표를 줄인다.
- 새 설명이 필요해질 때만 그림을 추가한다.
- 최종 문구가 완성되면 HTML 렌더본을 다시 확인한다.

## Execution Handoff

### Available agent-types roster

- `writer`: 본문 재배치, 교과서형 서사, 예시 문장 작성
- `researcher`: 새 주장이나 새 출처가 필요할 때만 source-matrix 보강
- `verifier`: grep, HTML 렌더, 이미지/TOC/source-matrix 검증
- `critic`: 최종 원고가 부록형으로 되돌아갔는지 검토

### Recommended Ralph path

- 추천: `$ralph "Implement .omx/plans/minto2-book-textbook-narrative.md"`
- 이유: 문서 정본 하나와 렌더 산출물을 함께 다루는 선형 편집 작업이라 단일 실행자가 가장 충돌이 적다.
- reasoning: `writer=high`, `verifier=medium`

### Recommended Team path

- 추천: `$team "Implement .omx/plans/minto2-book-textbook-narrative.md"`
- staffing:
  - `writer` 1명: `docs/book/minto2-speech-ai-study-book.md`
  - `researcher` 1명: `docs/book/source-matrix.md`, 새 주장 발생 시에만
  - `verifier` 1명: HTML 재생성, grep, 이미지/TOC 검증
- team verification path:
  - team은 Markdown/source-matrix/HTML 산출물과 검증 로그를 남긴다.
  - Ralph 또는 메인 실행자는 최종 diff를 읽고 `부록` 잔여, source-matrix drift, HTML-only drift를 다시 확인한다.
