# 개발자 온보딩 & 빌드/배포 가이드 구축 계획

> 작성일 2026-06-14. 목적: (1) 다른 개발자가 이 프로젝트에 진입할 수 있는 온보딩 가이드와
> (2) 앱을 빌드해 배포하는 파이프라인을, "지금 무엇이 있고 무엇이 비었는지"에서 출발해 단계적으로 구축한다.
>
> 이 문서는 **계획**이다. 실제 README/스크립트/서명 작업은 아직 하지 않았다.

---

## 1. 현재 상태 진단

### 기술 스택 (`Package.swift` 기준)
- Swift 6.0 / SPM 단독 (`.xcodeproj` 없음) / macOS 14+
- 타깃: `MintoCore`(라이브러리) + `minto2`(executable) + `MintoTests`
- 의존성: WhisperKit(STT), FluidAudio(화자분리), MCP swift-sdk(Notion OAuth, pre-1.0 minor 고정)
- Info.plist를 linker `-sectcreate`로 바이너리에 주입 → **현재 산출물은 `.app` 번들이 아니라 맨 실행파일** `.build/debug/minto2`

### 이미 갖춰진 것 ✅
- `scripts/dev.sh` — 로컬 빌드 + 안정 서명. 자가서명 인증서 "Minto2 Dev"로 재서명해 재빌드 시에도 Keychain ACL("항상 허용")이 유지된다. `build|run|test|sign` 서브커맨드 + `swift run` 금지 같은 함정까지 주석화돼 있음
- `Minto.entitlements` — 마이크(`device.audio-input`) / JIT(`cs.allow-jit`) / library-validation 비활성(`cs.disable-library-validation`, Metal 셰이더 로딩용)
- Swift 테스트(`Tests/MintoTests`) + Python 분석·벤치 스크립트/테스트 다수(`scripts/`, `Tests/test_*.py`)
- `docs/` 아래 작업 로그·계획 문서 풍부 (`work-log.md` 인덱스 패턴 존재)

### 비어 있는 것 ❌ (= 가이드가 채워야 할 것)
- **README.md 없음** — 신규 개발자 진입점 전무
- **루트 CLAUDE.md / AGENTS.md 없음** — 프로젝트 전용 규칙·명령이 코드에 안 적혀 있음 (전역 `~/.claude`만 존재)
- **배포 경로 전무** — 지금은 "디버그 실행파일 + 자가서명"이 끝. 다른 Mac 배포는 `.app` 번들링 → Developer ID 서명 → 공증 → 패키징이 통째로 미구현

### 전제 (확인된 결정사항)
- **Apple Developer Program 유료 계정 없음 (무료 Apple ID만).** → 공증(notarization)은 현재 불가. 배포는 자가서명 + 수동 우회 또는 추후 계정 발급 후 진행.
- 이번 작업 범위는 **이 계획 문서까지**. 실제 구현은 별도 진행.

---

## 2. 두 개의 트랙

가이드는 성격이 다른 두 묶음이다.

> **트랙 A — 개발자 온보딩**: 이미 있는 자산(dev.sh, docs/)을 글로 옮기는 일. 난이도 낮음, 의존성 없음.
> **트랙 B — 빌드/배포 파이프라인**: 새로 짓는 일. 난이도 높음, 유료 Apple 계정에 일부 차단됨.

### 트랙 A — 개발자 온보딩 가이드

- **A1. `README.md` 작성**
  - 프로젝트 한 줄 소개(회의 녹음·전사·요약 macOS 앱), 스택, 사전 준비(Xcode/Swift 6 toolchain, macOS 14+)
  - 빌드/실행: `./scripts/dev.sh run` (그리고 **왜 `swift run`을 쓰면 안 되는지** 한 줄)
  - 디렉토리 맵: `Sources/Minto/{App,UI,ViewModels,Models,Services,Bridge}`, `Sources/MintoApp`, `scripts/`(Python 분석), `docs/`
  - 검증: `./scripts/dev.sh test`
  - → verify: 이 프로젝트를 처음 받은 사람이 README만 보고 `dev.sh run`까지 도달 가능한가

- **A2. 사전 준비 1순위 자동화 — 자가서명 인증서**
  - 신규 개발자가 가장 먼저 막히는 지점: Keychain에 "Minto2 Dev" Self-Signed Code Signing 인증서 생성
  - 옵션 (a) README에 Keychain Access GUI 단계 스크린샷/순서로 명문화
  - 옵션 (b) `dev.sh`에 `setup` 서브커맨드 추가 — `security`/인증서 자동 생성 시도(자가서명 인증서 CLI 생성은 까다로우므로 PoC 후 결정)
  - → verify: 인증서 없는 깨끗한 계정에서 안내대로 따라 `dev.sh build`가 서명까지 성공

- **A3. 루트 `CLAUDE.md` 작성** (프로젝트 전용)
  - 빌드/테스트/lint 명령, "swift run 금지" gotcha, Metal/entitlement 주의
  - **검증 게이트**: 작업 완료로 간주하기 전 통과해야 할 명령 목록 (`dev.sh build`, `dev.sh test`, 해당 시 Python 테스트)
  - 전역 `~/.claude/CLAUDE.md`와 중복 회피 — 프로젝트 고유 사항만

- **A4. 기여 규칙**
  - 브랜치 전략(현재 `experiment/stt-engine-poc` 같은 토픽 브랜치 관찰됨), 커밋 컨벤션, PR 전 체크리스트
  - **Python 스크립트 vs Swift 앱 경계** 설명 — `scripts/`의 STT 벤치/분석은 연구용 사이드카, 앱 본체는 `Sources/`. 신규 개발자 혼란 1순위

### 트랙 B — 빌드/배포 파이프라인

> ⚠️ **유료 Apple 계정 게이트**: B2~B4는 Developer ID 인증서가 있어야 한다. 현재 무료 계정이므로 **B1과 B5(무료 우회)까지만 지금 가능**하고, B2~B4는 계정 발급 후 착수.

- **B1. `.app` 번들 생성 스크립트** *(계정 불필요 — 지금 가능)*
  - `swift build -c release` 산출물을 `Minto2.app/Contents/{MacOS,Resources,Info.plist}` 구조로 패키징
  - 현재 linker 주입 중인 `Info.plist`를 번들 표준 위치로, 아이콘(`.icns`)·`Resources/models` 포함
  - → verify: 더블클릭으로 실행되고 마이크 TCC 프롬프트가 정상 표시

- **B2. Developer ID 서명** *(유료 계정 필요)*
  - "Developer ID Application" 인증서로 `.app` 서명, Hardened Runtime 활성
  - ⚠️ 충돌 검토: 현재 `cs.disable-library-validation`(Metal dylib 허용)이 Hardened Runtime·공증과 호환되는지 사전 검증. 안 되면 셰이더 로딩 방식 재설계 필요

- **B3. 공증(notarization)** *(유료 계정 필요)*
  - `notarytool submit` → 통과 후 `stapler staple`. Gatekeeper가 다른 Mac에서 조용히 통과하게 함

- **B4. 배포 패키징 & 릴리스**
  - DMG 또는 zip, 버전 태깅, 릴리스 노트. `docs/work-log.md`와 연결

- **B5. 무료 계정 임시 배포 경로** *(계정 없이 소수 배포 시)*
  - 자가서명 `.app` 배포 → 받는 사람이 **우클릭 > 열기** 또는 `xattr -dr com.apple.quarantine Minto2.app`로 quarantine 제거
  - 한계: 신뢰 경고 발생, 외부 일반 사용자에겐 부적합. "내 Mac/소수 개발자"까지만 권장

- **B6. (선택) CI 자동화** — GitHub Actions 등으로 B1~B4 자동화. 유료 계정 + 인증서 secret 필요

---

## 3. "A 먼저, 필요할 때 B" 전환 비용 분석

핵심 질문에 대한 답: **A→B 전환 비용은 사실상 0이다.**

- **버려지는 산출물이 없다.** A는 *기존 자산의 문서화*, B는 *신규 파이프라인 구축*이다. A에서 만든 README/CLAUDE.md/기여규칙은 B를 추가해도 그대로 유효하고, "배포" 섹션 한 덩어리만 나중에 덧붙이면 된다. A의 어떤 결정도 B를 더 어렵게 만들지 않는다.
- **진짜 비용은 "전환"이 아니라 B 자체의 진입 장벽이다.** 그 장벽은 지금 하든 나중에 하든 동일하다:
  - 유료 Apple Developer 계정 $99/년 (가입 후 승인까지 보통 수시간~1~2일)
  - `.app` 번들링 스크립트 신규 작성 (B1, 반나절 규모)
  - 서명+공증+staple 최초 배선 (B2~B3, 첫 시도는 entitlement/Hardened Runtime 충돌 디버깅으로 하루 규모)
- **무료 계정에선 B의 핵심(B3 공증)이 원천 차단**이다. 따라서 "필요할 때 B"로 미루는 건 손해가 아니라 자연스러운 순서다. 계정이 생기는 시점이 곧 B 착수 시점.
- **단, B1(.app 번들링)은 계정 없이 지금도 가능**하다. 배포가 급하면 B1 + B5(자가서명 우회)만으로 "소수 Mac 수동 배포"는 즉시 열린다. 외부 일반 배포만 계정을 기다리면 된다.

> 요약: A를 먼저 해도 B에서 재작업이 발생하지 않는다. 미루는 비용은 "전환"이 아니라 "유료 계정 + 번들링 신규 구축"이며 이는 시점과 무관한 고정 비용이다.

---

## 4. 권장 시작 순서

1. **A1 + A3** (README + 루트 CLAUDE.md) — 기존 자산 기반이라 즉시 작성 가능, 효용 가장 큼
2. **A2 + A4** (인증서 자동화 + 기여 규칙) — 온보딩 완성
3. (배포 필요 시점에) **B1 + B5** — 무료 계정으로 가능한 소수 배포 경로 확보
4. (유료 계정 확보 후) **B2 → B3 → B4** — 정식 외부 배포
5. (반복 배포가 잦아지면) **B6** — CI 자동화

---

## 5. 미해결/조사 필요 항목

- [ ] `cs.disable-library-validation` ↔ Hardened Runtime ↔ 공증 3자 호환성 (B2 착수 전 PoC 필수)
- [ ] 자가서명 인증서 CLI 자동 생성 가능 여부 (A2 옵션 b 타당성)
- [ ] `Resources/models/*.bin`은 gitignore 제외 → 배포 번들에 모델을 어떻게 동봉/다운로드할지 (B1·B4 영향)
- [ ] 앱 아이콘(`.icns`) 자산 존재 여부 확인
