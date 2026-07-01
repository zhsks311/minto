# Branch Strategy

상태: Accepted  
목적: Minto2 앱 코드, 검증 브랜치, GitHub Pages 브랜치를 섞지 않고 운영한다.

## Branches

- `main`: 배포 가능한 안정 브랜치.
- `staging`: 다음 배포 후보를 모아 검증하는 통합 브랜치.
- `feat/*`: 기능 작업 브랜치. `staging`에서 분기하고 `staging`으로 merge한다.
- `fix/*`: 버그 수정 브랜치. 기본적으로 `staging`에서 분기하고 `staging`으로 merge한다.
- `gh-pages`: GitHub Pages 사이트 전용 브랜치. 앱 코드 브랜치와 merge하지 않는다.

## Flow

```text
feat/*, fix/* -> staging -> main
```

## Rules

- `main`은 배포 가능한 상태를 유지한다.
- `staging`은 다음 배포 후보를 모아 테스트하는 브랜치다.
- 정해진 주기 또는 배포 필요 시점에 `staging`을 테스트하고, 통과한 묶음만 `main`으로 merge한다.
- 긴급 수정은 `main`에서 `fix/*`를 만들 수 있으나, 수정 내용은 반드시 `staging`에도 반영한다.
- `gh-pages`는 사이트 전용 orphan 브랜치이며 `main`/`staging`과 merge하지 않는다.
- `release/*` 브랜치는 당장 사용하지 않는다. 필요해지면 나중에 도입한다.

## Verification before merging `staging` to `main`

기본 검증:

```bash
git diff --check
swift build --disable-sandbox --scratch-path /tmp/minto2-build
swift test --disable-sandbox --scratch-path /tmp/minto2-test
```

배포 후보 검증:

```bash
./scripts/bundle.sh --zip
```

소수 테스터에게 preview zip을 공유할 때는 `docs/release-preview-checklist.md`를 따른다.
