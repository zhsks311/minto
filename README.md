# Minto2 소개 페이지 (GitHub Pages)

이 브랜치(`gh-pages`)는 Minto2 소개용 정적 랜딩 페이지만 담는 orphan 브랜치다. 앱 소스는 `main`에 있다.

## 구성

- `index.html` — 단일 파일 랜딩 페이지 (CSS 인라인)
- `assets/` — 앱 아이콘·로고 (`main`의 `feat/app-icon-logo`에서 가져옴)
- `.nojekyll` — Jekyll 처리 비활성화

폰트(Pretendard, Gowun Batang)는 CDN으로 로드한다. 오프라인이면 system-ui로 폴백된다.

## GitHub Pages 켜는 법

1. GitHub 저장소 → **Settings → Pages**
2. **Source**: `Deploy from a branch`
3. **Branch**: `gh-pages` / `/ (root)` 선택 후 Save
4. 1~2분 뒤 `https://zhsks311.github.io/Minto2/` 에 게시된다.

> 무료 플랜은 공개 저장소에서만 Pages가 동작한다(비공개는 Pro 필요).

## 로컬 미리보기

```bash
python3 -m http.server 8000   # http://localhost:8000
```
