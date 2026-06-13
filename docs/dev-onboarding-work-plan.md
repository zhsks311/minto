# 개발자 온보딩 실행 작업 계획 (옵션 1: 무료·소수 배포)

> 작성일 2026-06-14. 브랜치 `chore/dev-onboarding` (worktree `minto2-onboarding`, base `main`).
> 전략·배경은 [`dev-onboarding-and-distribution-plan.md`](dev-onboarding-and-distribution-plan.md) 참조.
> 이 문서는 **실행 체크리스트**다. 각 작업은 검증 기준(verify)으로 완료를 판정한다.

## 범위 결정 (확정)

- **채택**: 트랙 A 전체(개발자 온보딩) + 트랙 B 중 무료 가능 부분(B1 `.app` 번들, B5 자가서명 우회 배포)
- **범위 밖(의도적 제외)**: B2 Developer ID 서명 / B3 공증 / B4 정식 패키징 / B6 CI
  - 이유: 유료 Apple Developer 계정($99/년)이 없고, 대상이 "개발자/소수 동료"라 공증 불필요.
  - 외부 일반 사용자 배포가 실제로 필요해지는 시점에 별도 작업으로 착수.

---

## Phase 1 — 온보딩 핵심 (최우선, 기존 자산 문서화)

### T1. `README.md` 작성
- **산출물**: 루트 `README.md` — 프로젝트 소개, 스택, 사전 준비, 빌드/실행/테스트, 디렉토리 맵
- **포함**: `./scripts/dev.sh run`이 진입점이며 **`swift run` 금지** 이유 한 줄, `Sources/` vs `scripts/`(Python 분석) 경계
- **verify**: 이 저장소를 처음 받은 사람이 README만 보고 빌드→실행까지 막힘 없이 도달 가능한가 (체크리스트로 자가 점검)

### T2. 루트 `CLAUDE.md` 작성
- **산출물**: 프로젝트 전용 `CLAUDE.md` — 빌드/테스트 명령, gotcha(swift run 금지, Metal/entitlement), **검증 게이트** 명령 목록
- **제약**: 전역 `~/.claude/CLAUDE.md`와 중복 회피 — 프로젝트 고유 사항만
- **verify**: 검증 게이트에 적힌 명령들(`dev.sh build`, `dev.sh test`)이 실제로 존재·동작하는가

### T3. 자가서명 인증서 온보딩
- **산출물**: README에 "Minto2 Dev" Self-Signed Code Signing 인증서 생성 절차(Keychain Access 단계별)
- **선택**: `dev.sh setup` 서브커맨드로 인증서 존재 확인 + 안내(자동 생성은 PoC 후 결정 → T7)
- **verify**: 인증서 없는 깨끗한 환경에서 안내대로 따라 `dev.sh build`가 서명까지 성공

### T4. 기여 규칙 (CONTRIBUTING)
- **산출물**: 브랜치 전략(형제 워크트리 `minto2-<slug>` 컨벤션 포함), 커밋 컨벤션, PR 전 체크리스트
- **verify**: 신규 기여자가 브랜치 생성→작업→PR 흐름을 문서만으로 수행 가능

---

## Phase 2 — 소수 배포 경로 (무료)

### T5. `.app` 번들 생성 스크립트 (B1)
- **산출물**: `scripts/bundle.sh`(가칭) — `swift build -c release` → `Minto2.app/Contents/{MacOS,Resources,Info.plist}` 구성
- **확인 필요**: 현재 linker 주입 `Info.plist`를 번들 표준 위치로, 아이콘(`.icns`)·`Resources/models` 동봉 방식
- **verify**: 더블클릭으로 실행되고 마이크 TCC 권한 프롬프트가 정상 표시

### T6. 자가서명 배포 + 우회 안내 (B5)
- **산출물**: `.app`을 "Minto2 Dev"로 서명 후 zip, README에 받는 사람 안내(우클릭>열기 / `xattr -dr com.apple.quarantine`)
- **명시**: macOS 15+에서 우회 단계가 더 늘어남을 경고. 외부 일반 배포엔 부적합
- **verify**: 다른 (또는 초기화된) 사용자 계정에서 안내대로 실행 성공

---

## Phase 3 — 범위 밖 (이번 작업 제외)

> 사용자 결정(2026-06-14): 이번엔 Phase 1·2만 진행. T7은 보류.

### T7. 자가서명 인증서 CLI 자동 생성 PoC *(보류)*
- 자가서명 Code Signing 인증서를 CLI(`security`/`openssl`)로 생성 가능한지 검증 → 되면 `dev.sh setup`에 통합

---

## 미해결/조사 항목 (작업 중 해소)

- [ ] `Resources/models/*.bin`은 gitignore 제외 → 번들에 모델 동봉 vs 최초 실행 시 다운로드 (T5 영향)
- [ ] 앱 아이콘(`.icns`) 자산 존재 여부
- [ ] `cs.disable-library-validation`이 release 빌드·자가서명에서 문제없는지 (T5/T6)

---

## 권장 실행 순서

1. **T1 + T2** (README + CLAUDE.md) — 효용 최대, 즉시 가능
2. **T3 + T4** (인증서 온보딩 + 기여 규칙) — 온보딩 완성
3. **T5 + T6** (번들 + 소수 배포) — 무료 배포 경로 확보
4. (여유 시) **T7**

## 진행 현황

- [x] 워크트리/브랜치 셋업 (`chore/dev-onboarding`)
- [x] 전략 문서 + 실행 작업 계획 작성
- [x] T1 README (영업 카피 + 개발 셋업)
- [x] T2 CLAUDE.md (기존 파일에 dev.sh/서명/entitlement 섹션 보강)
- [x] T3 인증서 온보딩 (README "1회 설정: 코드서명 인증서"에 포함)
- [x] T4 기여 규칙 (CONTRIBUTING.md — 관찰된 브랜치/커밋/리뷰 컨벤션)
- [x] T5 `.app` 번들 (`scripts/bundle.sh` — 빌드/서명/검증 통과)
- [x] T6 자가서명 배포 (README "배포하기" + bundle.sh `--zip`)
- [~] T7 (보류)

## 작업 중 해소된 사실 (T5)
- 모델은 런타임 다운로드 → 번들에 모델 동봉 불필요 (`Resources/models` 비어 있음)
- 앱 아이콘(.icns) 없음 → 스크립트는 아이콘 옵셔널 처리 (`Resources/AppIcon.icns` 추가 시 자동 포함)
- 의존성 리소스 번들 **2개 존재**: `swift-crypto_Crypto.bundle`, `swift-transformers_Hub.bundle` (평면 리소스 번들)
- 검증으로 잡은 결함: 리소스 번들은 `Contents/Resources/`에 둬야 함(`MacOS/`에 두면 codesign이 코드로 오인해 실패). 개별 서명 불가 → .app 전체 서명으로 봉인.
- 검증 결과: `codesign --verify --deep --strict` = "valid on disk" + "satisfies its Designated Requirement"

## 남은 수동 QA (권장)
- 실제 `.app` 더블클릭 실행 + 마이크 권한 프롬프트 정상 표시 확인 (GUI 메뉴바 앱이라 자동 검증 대신 수동 1회 권장)
