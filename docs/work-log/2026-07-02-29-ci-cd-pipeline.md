# CI/CD 파이프라인 도입 + public 오픈 준비 정리

날짜: 2026-07-02
브랜치: `feat/ci-cd-pipeline` (staging에서 분기)
상태: 구현·로컬 검증 완료, 커밋 대기

## 배경

프로젝트 public 오픈을 준비하며 (1) 현재 오픈 가능 상태인지 점검하고 (2) CI/CD 전략을 세워 실제로 배선했다.

## 오픈 가능 상태 점검 결과

- 히스토리·워킹트리 시크릿 스캔: 하드코딩된 API 키·토큰·개인키 없음. `ANTHROPIC_API_KEY`는 환경변수 이름 상수, `ConfluenceService`/`SecretStore`는 Keychain 래퍼 로직.
- 모델 파일(`*.bin`)은 `.gitignore`로 제외됨. 히스토리에 삭제된 위험 파일 없음.
- 정리 대상 3건 식별: 홈 경로 노출(43곳), LICENSE 파일 부재, 테스트 이메일 픽스처.

## 한 일

### public 준비 정리

- **홈 경로 스크럽**: 추적 파일의 `/Users/d66hjkxwt9` 절대경로를 `~`로 치환(사용자명 PII 제거). 스크럽 대상 docs 대부분은 병행 중인 별도 작업(docs/test를 private 레포로 분리)에서 이미 이 브랜치 워킹트리에서 제거된 상태라, 이 커밋에는 `scripts/batisay_faster_whisper_bench.py`·`scripts/sherpa_streaming_bench.py`의 기본값 경로 치환만 남는다.
  - Python 벤치 스크립트 기본값 경로가 `~/...`로 바뀌었으나, `sample/`이 gitignore돼 레포에 없고 원래도 저자 머신 전용 절대경로였으므로 앱·CI 동작과 무관하다.
- **테스트 이메일**: `RelatedInfoTests.swift`의 `"jaehwi.kim"` 픽스처를 `"test.user"`로 치환. 둘 다 `@` 없는 불완전 이메일이라 "전체 계정 이메일 경고" 검증 의미는 동일하게 유지.
- **LICENSE 파일**: 이번 작업에서는 만들지 않음. CI/CD·오픈 준비가 끝난 뒤 사용자가 직접 교체할 예정(보류).

### CI/CD 배선

- **`.github/workflows/ci.yml`**: `staging`/`main`으로 가는 PR과 `staging` push에서 `swift build` + `swift test` + `git diff --check`(공백/conflict 마커)를 macos-14 러너에서 실행. SwiftPM 빌드 캐시(`Package.resolved` 해시 키) 적용. 테스트는 mock 기반이라 모델 다운로드·네트워크 불필요.
- **`.github/workflows/release.yml`**: `v*` 태그 push 시 `bundle.sh --zip`으로 자가서명(ad-hoc) `.app`+zip을 만들어 `gh release create`로 GitHub prerelease 첨부. 유료 Apple Developer 계정 확보 시 활성화할 Developer ID 서명·공증(notarization)·stapling 단계는 **주석으로 in-place 보존**(계정 생기면 주석 해제).
- **`scripts/bundle.sh`**: `MINTO_SIGN_IDENTITY=-`(ad-hoc) 가드 추가. 러너처럼 "Minto2 Dev" 인증서가 없는 환경에서도 번들 서명이 되게 함. 공증이 없으면 자가서명이든 ad-hoc이든 Gatekeeper 신뢰는 동일하므로 preview 배포엔 등가.

## 검증

- `swift build`(96s) + `swift test`: **826 테스트 / 123 스위트 전부 통과** (CI 등가).
- `MINTO_SIGN_IDENTITY=- ./scripts/bundle.sh --zip`(release 빌드 70s): `Signature=adhoc`로 정상 서명, `dist/Minto2.zip`(11MB) 생성. `dist/`는 gitignore로 커밋에서 제외 확인.
- 워크플로 YAML·`bundle.sh` 문법 검증 통과.

## 남은 일

- 커밋 + 브랜치 push (승인 대기).
- push 후 GitHub에서 CI 첫 실행 관측(워크플로는 push돼야 트리거).
- branch protection 규칙 연결: `main`/`staging`에 "CI 통과 필수" 게이트.
- LICENSE 파일 교체(사용자 진행).
- (유료 계정 확보 시) Developer ID 서명·공증 단계 주석 해제 + `cs.disable-library-validation` ↔ Hardened Runtime ↔ 공증 3자 호환성 PoC.
