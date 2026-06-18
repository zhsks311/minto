# Minto 공식 STT 모델 테스트/검증 프레임워크 재개용 핸드오프

작성 시점: 2026-06-17 KST

## 한 줄 요약

현재 작업 목표는 Minto의 STT 모델 비교를 공식 프레임워크로 만들기 위한 release workflow를 통과시키는 것이다. 코드 쪽 프레임워크는 준비되어 있고, 지금 막힌 것은 사람이 reference transcript 7개를 검토해서 `ok` 또는 `exclude`로 판단하는 human reference review evidence 단계다.

## 현재 실제 목표

- 목표: Minto STT 엔진/모델 비교를 공식적으로 반복 가능한 테스트/검증 프레임워크로 만들기
- 현재 단계: official release workflow의 남은 blocker인 `reference_review_workflow_report` 제출
- 현재 blocker 성격: 코드 버그가 아니라 사람 검토 증거 필요
- 지금 사용자가 해야 할 일: `review_answer_sheet.csv`에서 각 샘플을 `ok` 또는 `exclude`로 판단
- 주의: 검토하지 않은 row를 임의로 `ok` 처리하면 안 됨

## 관련 worktree와 브랜치

- 현재 대화 cwd:
  - `/Users/d66hjkxwt9/Idea/private/minto2`
  - branch: `main`
  - 이 repo에는 기존 untracked 파일들이 있음. 이 작업과 무관하면 건드리지 말 것.
- 공식 framework worktree:
  - `/Users/d66hjkxwt9/Idea/private/minto2-official-stt-benchmark-framework`
  - branch: `experiment/official-stt-benchmark-framework`
  - HEAD: `d0857f7 fix: preserve next blocking submission actions`
  - 현재 status: clean

## 공식 framework에서 이미 완료된 작업

### 커밋된 주요 작업

- `277d33b feat: emit reference review fill tasks`
  - release workflow가 operator에게 필요한 reference review fill task를 산출하도록 보강
- `c96e7ef fix: surface reference review fill task hints`
  - missing evidence 상황에서 어떤 row/field를 채워야 하는지 더 잘 보이게 수정
- `d0857f7 fix: preserve next blocking submission actions`
  - 다음 blocking submission action이 덮어써지지 않도록 보존

### 이전 검증 상태

- 공식 framework 테스트는 이전에 전체 통과한 상태로 기록됨
  - `Ran 639 tests ... OK`
- 현재 framework worktree는 clean
- 단, 현재 남은 것은 사람 검토 입력이므로 테스트 통과만으로 release workflow가 완료되지는 않음

## 현재 작업팩 위치

작업팩:

`/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/`

주요 파일:

- `WHAT_TO_DO_KR.md`
  - 한국어 작업 안내
- `reference_review_human_dashboard.html`
  - 검토용 HTML. 보기 전용이며 저장 기능 없음
- `review_answer_sheet.csv`
  - 사용자가 실제로 채워야 하는 답안지
- `apply_review_answer_sheet.sh`
  - 답안지를 공식 decision CSV에 반영하고 preflight 실행
- `run_after_human_review.sh`
  - preflight 통과 후 공식 workflow 재개
- `reference_review_decisions.to_fill.csv`
  - 내부 workflow가 실제로 읽는 CSV. 사용자가 직접 편집할 필요 없음
- `preflight_check/reference_review_preflight_report.json`
  - 현재 preflight 결과
- `review_helper.py`
  - answer sheet 생성/적용, interactive helper, preflight 연결용 helper

## 사용자가 지금 입력한 상태

현재 `review_answer_sheet.csv`는 7개 row가 모두 채워져 있다.

현재 값:

| sample_id | split | decision | reason/note 요지 |
|---|---|---|---|
| `haengan_20260526` | dev | `exclude` | 약 20초 밀림, 스크립트는 꽤 정확 |
| `본회의_20260423` | gold | `exclude` | 약 18초 밀림, 스크립트는 꽤 정확 |
| `본회의_20260428` | dev | `exclude` | 약 8초 밀림, 스크립트는 꽤 정확 |
| `본회의_20260508` | dev | `exclude` | 약 10초 밀림, 스크립트는 꽤 정확 |
| `외교통일위원회_20260520` | stress | `exclude` | 약 12초 밀림, 스크립트는 꽤 정확 |
| `재정경제기획위원회_20260429` | dev | `exclude` | 약 10초 밀림, 스크립트는 꽤 정확 |
| `재정경제기획위원회_20260430` | dev | `exclude` | 약 10초 밀림, 스크립트는 꽤 정확 |

## 현재 blocker

최근 실행:

`/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/run_after_human_review.sh`

결과:

- `preflight_state: blocked_review_decision_errors`
- `ready_to_apply: False`
- `blocking_gates: review_decision_invalid`
- error:
  - `row 3: 본회의_20260423: gold target_split requires review_status=reviewed`

의미:

- `본회의_20260423`은 유일한 gold 샘플이다.
- gold 샘플은 공식 gate를 통과하려면 `review_status=reviewed`, 즉 answer sheet에서는 `ok`여야 한다.
- 현재 이 row가 `exclude`라서 workflow가 멈춘다.

## 중요한 판단 기준

`ok`의 의미:

- 오디오가 열린다.
- reference text가 같은 회의 내용으로 보인다.
- 공식 STT 모델 비교의 기준 transcript로 써도 된다고 사람이 판단했다.
- 몇 초 단위의 SMI 시간 밀림이 있어도 transcript 내용이 맞으면 보통 `ok`다.
- 시간 밀림은 `note`에 남긴다.

`exclude`의 의미:

- 오디오가 열리지 않는다.
- reference가 다른 회의다.
- transcript 내용이 크게 틀려 기준 데이터로 못 믿겠다.
- 무음/잡음/깨진 파일 등으로 공식 기준 데이터로 쓰기 어렵다.
- 사람이 reference transcript로 신뢰할 수 없다고 판단했다.

현재 사용자가 적은 "약 N초 밀려있음, 스크립트는 꽤 정확"은 보통 `exclude`가 아니라 `ok` + note에 가깝다. 단, 실제 판단은 사람이 해야 한다.

## 재개 후 바로 할 일

### 1. 답안지 열기

```bash
open /private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/review_answer_sheet.csv
```

### 2. `본회의_20260423`을 다시 판단

현재 line:

```csv
본회의_20260423,gold,193.5,exclude,약 18초 밀려있음 스크립트는 꽤 정확,gold target scaffold; set review_status only after human review
```

만약 실제로 오디오와 transcript를 봤고 내용이 같은 회의로 신뢰 가능하다면 이렇게 수정:

```csv
본회의_20260423,gold,193.5,ok,,약 18초 밀려있음. 스크립트는 꽤 정확
```

실제로 기준 transcript로 못 쓰겠다면 `exclude`를 유지해야 한다. 이 경우 현재 샘플 구성으로는 공식 default gate를 통과할 gold 샘플이 없어서 다음 단계는 새 gold 후보를 고르거나 reference review pack을 다시 구성하는 것이다.

### 3. 저장 후 answer sheet 적용

```bash
/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/apply_review_answer_sheet.sh
```

기대 결과:

- 성공이면 `Preflight passed.`
- 실패이면 출력된 error를 보고 `review_answer_sheet.csv`를 다시 수정

### 4. preflight 통과 후 official workflow 재개

`Preflight passed`가 나온 뒤에만 실행:

```bash
/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/run_after_human_review.sh
```

이 스크립트가 하는 일:

1. human reference review decisions preflight
2. reference review batch workflow 실행
3. operator evidence return template 자동 채움
4. operator evidence return workflow 실행
5. official release workflow 재실행
6. final manifest validation

## 디스크 정리 후 복구한 것

문제:

- `/private/tmp/minto2-official-reference-draft-current/reference_manifest.json`이 없어져서 preflight가 `FileNotFoundError`로 실패했음

복구:

```bash
python3 /Users/d66hjkxwt9/Idea/private/minto2-official-stt-benchmark-framework/scripts/build_stt_reference_manifest.py \
  --raw-dir /Users/d66hjkxwt9/Idea/private/minto2/sample/meeting/raw \
  --output-root /private/tmp/minto2-official-reference-draft-current \
  --reference-version official-reference-draft-2026-06-12 \
  --gold-samples '본회의_20260423' \
  --stress-samples '외교통일위원회_20260520' \
  --reviewer regenerated-manifest \
  --reviewed-at '2026-06-17T00:00:00+09:00'
```

복구 결과:

- `sample_count: 7`
- `split_counts: {'stress': 1, 'dev': 5, 'gold': 1}`
- `reference_quality_issue_count: 0`

주의:

- 이 manifest 복구는 preflight가 돌아가게 하기 위한 임시 산출물 복구다.
- 사람 검토 결정을 대신 조작한 것이 아니다.

## helper를 고친 내용

### 1. interactive helper EOF 처리

처음 `start_review_helper.sh`를 shell command로 실행했을 때 stdin이 없어 `EOFError`가 났다.

수정:

- 이제 입력을 받을 수 없는 환경에서는 traceback 대신 안내 메시지를 낸다.
- 실제 interactive 방식은 macOS Terminal에서 직접 실행해야 한다.

### 2. simple CSV 방식 추가

중간에 `reference_review_decisions.simple.csv` 방식도 만들었다.

그러나 사용자에게 여전히 컬럼이 많고 헷갈릴 수 있어서, 더 단순한 answer sheet 방식으로 다시 줄였다.

### 3. answer sheet 방식 추가

추가 파일:

- `make_review_answer_sheet.sh`
- `apply_review_answer_sheet.sh`
- `review_answer_sheet.csv`

핵심:

- 사용자는 `decision_ok_or_exclude`만 채우면 된다.
- 값은 `ok` 또는 `exclude`
- `exclude`인 경우에만 `reason_if_exclude` 필요

### 4. gold 샘플 exclude 사전 차단

현재 helper는 `본회의_20260423` 같은 required gold sample이 `exclude`로 들어오면 preflight까지 가지 않고 더 명확한 메시지를 낸다.

현재 메시지:

`본회의_20260423: this is the required gold sample; use ok if the transcript text is usable, or choose/review another gold sample before continuing`

## 앞으로 할 작업

### A. 현재 gate를 통과시키는 최소 작업

1. 사용자가 `본회의_20260423`을 실제 검토한다.
2. transcript가 기준으로 쓸 수 있으면 answer sheet에서 `ok`로 바꾼다.
3. `apply_review_answer_sheet.sh` 실행
4. `Preflight passed` 확인
5. `run_after_human_review.sh` 실행
6. final release workflow가 `blocked_operator_evidence`에서 벗어났는지 확인

### B. 만약 `본회의_20260423`을 기준으로 못 쓰겠다면

1. `본회의_20260423`을 `exclude`로 유지한다.
2. 현재 pack에는 통과 가능한 gold 샘플이 없으므로 default gate는 계속 막힌다.
3. 새 gold 후보를 선택하거나 reference review pack을 다시 만들어야 한다.
4. 이후 새 gold row를 사람이 검토하고 `ok`로 만들어야 한다.

### C. 공식 프레임워크로 만들기 위한 다음 개선

현재 operator flow는 임시 작업팩 중심이다. 공식 프레임워크로 안정화하려면 다음이 필요하다.

- 작업팩을 `/private/tmp` 의존에서 벗어나 repo-local 또는 run-artifact directory로 보존
- answer sheet workflow를 공식 script로 승격
- HTML dashboard에 판단 기준을 더 명확히 표시
- gold 샘플의 의미와 `ok/exclude` 판단 기준을 UI/CSV에 직접 표시
- timing shift는 exclusion 사유가 아니라 note/known issue로 관리하는 정책 명문화
- 사람이 한 판단을 audit 가능한 evidence로 남기는 report 강화
- release workflow 재실행 후 결과 HTML/JSON을 사람이 읽기 쉽게 요약
- 임시 산출물 삭제 후에도 복구 가능한 command bundle 제공

## 하지 말아야 할 일

- 검토하지 않은 row를 임의로 `ok` 처리하지 말 것
- `run_after_human_review.sh`를 preflight 실패 상태에서 반복 실행하지 말 것
- `reference_review_decisions.to_fill.csv`를 직접 만지지 말 것. 특별한 이유가 없으면 `review_answer_sheet.csv`만 수정
- 현재 `minto2` repo의 기존 untracked 파일들을 정리하거나 되돌리지 말 것
- `/private/tmp` 산출물이 사라졌다고 결론을 바꾸지 말 것. 필요한 것은 재생성 가능 여부 확인

## 재개 체크리스트

1. 이 문서를 읽는다.
2. 현재 답안지 확인:

```bash
open /private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/review_answer_sheet.csv
```

3. 검토 HTML 확인:

```bash
open /private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/reference_review_human_dashboard.html
```

4. `본회의_20260423` row가 실제로 기준 transcript로 쓸 수 있는지 판단
5. 쓸 수 있으면 `decision_ok_or_exclude=ok`, 사유는 note로 이동
6. 적용:

```bash
/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/apply_review_answer_sheet.sh
```

7. `Preflight passed` 확인 후:

```bash
/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/run_after_human_review.sh
```

8. final release report 확인:

`/private/tmp/minto2-official-release-workflow-current/official_release_workflow_report.json`

## 현재 저장 위치

이 handoff 문서의 안정 저장 위치:

`/Users/d66hjkxwt9/Idea/private/minto2/docs/reports/2026-06-17-official-stt-benchmark-framework-pause-resume-handoff.md`

작업팩 복사본:

`/private/tmp/minto2-official-release-workflow-current/operator_reference_review_working_pack/PAUSE_RESUME_HANDOFF_KR.md`
