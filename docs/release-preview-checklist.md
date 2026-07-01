# Minto2 Preview 배포 체크리스트

상태: 운영 메모  
목적: Apple Developer Program 가입 전, 소수 테스터에게 자가서명 preview 빌드를 직접 공유할 때 확인할 항목을 고정한다.

## 배포 원칙

- 현재 단계에서는 Apple Developer Program($99/년)에 가입하지 않는다.
- 일반 사용자용 정식 다운로드가 아니라, 신뢰하는 소수 사용자에게 preview zip을 직접 공유한다.
- 빌드는 자가서명되어 있으므로 `spctl`에서 `rejected`가 나오는 것이 예상 상태다.
- 테스터에게 macOS 첫 실행 경고와 `우클릭 > 열기` 절차를 미리 안내한다.
- 설치가 막히는 지점도 제품 검증 대상이다.

## 빌드 전 확인

```bash
git status --short --branch
swift test --disable-sandbox --scratch-path /tmp/minto2-test
```

관련 변경이 배포 산출물에 영향을 줄 때는 필요한 기능 테스트를 먼저 통과시킨다.

## Preview zip 생성

```bash
./scripts/bundle.sh --zip
```

기대 산출물:

```text
dist/Minto2.app
dist/Minto2.zip
```

## 산출물 확인

```bash
codesign --verify --deep --strict --verbose=2 dist/Minto2.app
spctl --assess --type execute --verbose=4 dist/Minto2.app || true
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/Minto2.app/Contents/Info.plist
```

기대 결과:

- `codesign`은 `valid on disk`, `satisfies its Designated Requirement`여야 한다.
- `spctl`은 공증되지 않은 자가서명 빌드라 `rejected`가 나올 수 있다.
- `CFBundleIconFile`은 `AppIcon`이어야 한다.
- Finder/Dock에서 앱 아이콘이 표시되어야 한다.

## 첫 실행 확인

가능하면 기존 권한/캐시가 없는 환경에서 확인한다.

- zip 압축 해제
- `Minto2.app`을 Applications 또는 테스트 위치로 이동
- 더블클릭이 아니라 `우클릭 > 열기`
- 마이크 권한 요청 확인
- 시스템 사운드 입력 안내 확인
- 짧은 녹음 시작/종료 확인
- 회의 저장 확인
- 요약 실패가 전사/저장을 막지 않는지 확인

## 테스터에게 보낼 안내문

```text
이 빌드는 아직 Apple 공증을 받지 않은 preview build입니다.
macOS가 처음 실행을 막을 수 있습니다.

설치 방법:
1. Minto2.zip 압축 해제
2. Minto2.app을 Applications 폴더로 이동
3. 더블클릭하지 말고 우클릭 → 열기
4. 경고가 뜨면 “열기” 선택
5. 마이크/시스템 사운드 권한 허용

그래도 안 열리면 알려주세요. 설치 과정도 테스트 대상입니다.
```

기술 사용자용 마지막 fallback:

```bash
xattr -dr com.apple.quarantine /Applications/Minto2.app
```

## 정식 배포 전환 조건

아래 신호가 생기면 Apple Developer Program 가입과 Developer ID 공증 배포를 다시 검토한다.

- 5명 이상이 preview build를 실행했다.
- 3명 이상이 실제 회의에 사용했다.
- 설치 경고가 주요 이탈 원인으로 반복된다.
- 공개 다운로드 링크가 필요해졌다.
- 반복 릴리스와 업데이트 배포가 필요해졌다.

## 정식 배포 때 추가할 일

- Developer ID Application 인증서 발급
- Hardened Runtime과 entitlement 호환성 확인
- notarization 및 stapling
- GitHub Releases 또는 DMG 배포
- `download.html`을 정식 다운로드 안내로 갱신
