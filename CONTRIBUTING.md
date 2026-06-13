# 기여 가이드

Minto2에 기여할 때의 규칙입니다. 작업 기준·검증 명령은 [`CLAUDE.md`](CLAUDE.md), 빌드·실행은 [`README.md`](README.md)를 함께 보세요.

## 작업 흐름

> 토픽 브랜치 → 구현 → 리뷰 → 리뷰 반영 → 병합 → 작업 로그

1. `main`에서 **토픽 브랜치**를 딴다.
2. 작은 단위로 구현하며 커밋한다.
3. 검증 게이트(아래)를 통과시킨다.
4. 코드 리뷰를 받고, 지적은 `fix: … 리뷰 지적 반영` 커밋으로 반영한다.
5. `main`에 병합한다 (`Merge type/slug: 설명`).
6. `docs/work-log.md` 인덱스 + `docs/work-log/YYYY-MM-DD-NN-slug.md`에 작업 로그를 남긴다.

## 워크트리 (권장)

이 저장소는 **형제 디렉토리 워크트리** 컨벤션을 쓴다 — 여러 작업을 격리된 폴더에서 동시에 진행한다.

```bash
git worktree add ../minto2-<slug> -b <type>/<slug> main
cd ../minto2-<slug>
```

기존 워크트리 확인: `git worktree list`. 작업 종료 후 정리: `git worktree remove ../minto2-<slug>`.

## 브랜치 네이밍

`<type>/<kebab-slug>` 형식. type은 커밋 접두어와 같은 어휘를 쓴다.

- `feat/glossary-candidates`, `fix/save-failure-recovery`, `docs/stt-boundary-plan`, `refactor/provider-single-source`, `chore/tech-debt-round`

## 커밋 메시지

**Conventional Commits 접두어(영문) + 설명(한국어)**.

```
feat: 회의 시작 용어집 묶음 선택 적용
fix: 채널 라벨 리뷰 반영 — preview 무라벨·reset 의도 주석
docs: 화자분리 계층형 구현 계획 (Phase 1/2)
test: 저장 복구 통합 테스트
```

- type: `feat` / `fix` / `docs` / `test` / `refactor` / `chore`
- **`Co-Authored-By:` 트레일러를 넣지 않는다.**
- 무엇을·왜 바꿨는지 한 줄로. 보충은 본문에.

## 검증 게이트 (커밋/병합 전 필수)

[`CLAUDE.md`](CLAUDE.md)의 검증 명령과 동일하다.

```bash
git diff --check
swift build --disable-sandbox --scratch-path /tmp/minto2-build
swift test  --disable-sandbox --scratch-path /tmp/minto2-test
```

- 앱을 실제로 띄워 확인할 때는 `./scripts/dev.sh run` (raw `swift build/test`는 컴파일·테스트 통과 확인용).
- `scripts/`의 Python 도구를 바꿨다면 해당 `Tests/test_*.py`도 통과시킨다.

## PR/병합 전 체크리스트

[`CLAUDE.md` "코드리뷰"](CLAUDE.md) 기준을 따른다. 요약:

- [ ] 계획 Phase와 연결되어 있다
- [ ] 기존 동작 회귀가 없다
- [ ] 테스트가 변경 범위를 커버한다
- [ ] **민감정보(transcript·prompt·token·정상 응답 본문)가 로그에 남지 않는다**
- [ ] UI 변경은 empty/loading/success/error/disabled 상태를 갖는다
- [ ] 문서와 작업 로그가 업데이트됐다
- [ ] 아키텍처 경계를 넘는 변경이면 ADR(`docs/adr/`)을 남겼다

## 코드 위치

- 앱 런타임 코드는 전부 `Sources/`.
- `scripts/`의 Python은 **STT 품질 분석·벤치마크 사이드카** — 앱과 무관하니 혼동하지 않는다.
