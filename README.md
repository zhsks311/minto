# Minto 소개 사이트 (GitHub Pages)

이 브랜치(`gh-pages`)는 Minto 공개 소개 사이트만 담는 정적 GitHub Pages 브랜치다. 앱 소스 브랜치와 merge하지 않는다.

## 역할

- `gh-pages` — GitHub Pages가 실제로 서빙하는 사이트 브랜치
- `site/main` — 사이트 저장소의 기본 브랜치로 쓰일 수 있으나, 현재 내용은 `gh-pages`와 같은 정적 사이트 파일이다
- 앱 소스 — 별도 앱 저장소/remote의 `main`/`staging` 흐름에서 관리한다. 이 사이트 브랜치에는 `Sources/`, `Tests/`, `Package.swift` 같은 앱 코드를 두지 않는다

## 구성

- `index.html` — 제품 소개 랜딩 페이지
- `download.html` — 현재 배포 상태와 설치 안내
- `guide.html` — 회의 기록·요약·검색·내보내기 사용법
- `privacy.html` — 로컬 처리와 외부 전송 데이터 경계
- `troubleshooting.html` — 권한·전사·요약·내보내기 문제 해결
- `assets/` — 앱 아이콘과 사이트 이미지
- `.nojekyll` — Jekyll 처리 비활성화

폰트(Pretendard, Gowun Batang)는 CDN으로 로드한다. 오프라인이면 system-ui로 폴백된다.

## 수정 원칙

- 앱 기능 설명을 바꿀 때는 먼저 앱 저장소의 `README.md` 또는 `docs/service-definition.md`와 내용이 충돌하지 않는지 확인한다.
- 사이트 문구·HTML·이미지만 수정한다. 앱 코드 변경과 한 커밋에 섞지 않는다.
- 개인정보, 토큰, 내부 경로, 미공개 회의 데이터, 프롬프트 원문을 사이트에 넣지 않는다.
- 다운로드/배포 안내는 실제 GitHub Release 상태와 맞아야 한다. 공증되지 않은 preview 빌드를 일반 배포처럼 표현하지 않는다.
- 공통 내비게이션을 바꾸면 모든 HTML 페이지(`index`, `download`, `guide`, `privacy`, `troubleshooting`)에서 링크가 일관되는지 확인한다.

## 로컬 미리보기

```bash
python3 -m http.server 8000
```

브라우저에서 `http://localhost:8000`을 연다.

최소 확인 항목:

- `index.html`, `download.html`, `guide.html`, `privacy.html`, `troubleshooting.html`이 모두 열린다.
- 상단 내비게이션 링크가 모두 동작한다.
- 모바일 폭에서 가로 스크롤이 생기지 않는다.
- 다운로드 안내가 현재 배포 상태와 맞다.

## GitHub Pages 설정

1. GitHub 저장소 → **Settings → Pages**
2. **Source**: `Deploy from a branch`
3. **Branch**: `gh-pages` / `/ (root)` 선택 후 Save
4. 1~2분 뒤 `https://zhsks311.github.io/minto/`에 게시된다.

무료 플랜은 공개 저장소에서만 Pages가 동작한다. 비공개 저장소 Pages는 GitHub 요금제 조건을 확인한다.
