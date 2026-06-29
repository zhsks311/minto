# Minto UI Design Guide

이 문서는 Minto의 UI/브랜드 디자인 기준이다. 새 화면, 컴포넌트, 아이콘, 상태 표현을 추가하거나 수정할 때 `CLAUDE.md`의 UI 원칙과 함께 이 문서를 먼저 확인한다.

## 1. 디자인 목표

Minto는 macOS 회의 기록 앱이다. UI는 회의 중 사용자의 주의를 빼앗지 않고, 회의 후에는 필요한 기록을 빠르게 찾고 활용하게 해야 한다.

- **Calm**: 회의 중 방해하지 않는 차분한 화면. 강한 색과 큰 모션은 핵심 행동에만 쓴다.
- **Clear**: 녹음, 전사, 요약, 저장, 검색, 내보내기 상태를 즉시 이해할 수 있어야 한다.
- **Trustworthy**: 로컬 처리와 클라우드 전송 여부, 실패와 복구 상태를 숨기지 않는다.
- **Mac-native**: macOS의 창, 메뉴바, Dock, 키보드/마우스 사용 감각을 따른다.
- **Actionable**: 사용자가 다음에 할 일을 쉽게 찾게 한다. Toss식 원칙: 좋은 기본값, 명확한 상태, 쉬운 다음 행동.

## 2. 브랜드

### 2.1 이름

- 제품명과 앱 표시명은 **Minto**다.
- 실행 파일/패키지 이름은 `minto2`일 수 있지만, 사용자에게 보이는 이름은 `Minto`를 우선한다.
- macOS 상단 앱 메뉴(🍎 옆)는 OS가 앱 이름 텍스트만 표시한다. 아이콘을 넣으려 하지 않는다.

### 2.2 키워드

- 민트, 기록, 깃펜, 가벼움, 회의 보조, 신뢰감
- 문서 작업 도구처럼 차분하되, 회의 중 상태는 충분히 명확해야 한다.

### 2.3 로고/아이콘 자산

소스 자산은 `Sources/Minto/Resources/`에 둔다.

| 용도 | 파일 | 규칙 |
|---|---|---|
| Dock/Finder/App bundle | `AppIcon.png` | 1024×1024 PNG. 배경과 squircle/투명 코너가 포함된 완성본. `scripts/dev.sh package`가 `.icns`로 변환한다. |
| 메뉴바 우측 아이콘 | `MenuBarIcon.png` | template 이미지. 색상은 OS가 라이트/다크 상태에 맞춰 틴트한다. 배경을 넣지 않는다. |
| 앱 내부 로고 | `LogoMark.png` | 배경 없는 컬러 깃펜 마크. 헤더, empty state, About성 화면 등에 사용한다. |

주의:

- 메뉴바 아이콘은 컬러 로고를 쓰지 않는다. macOS 메뉴바에서는 template 이미지가 라이트/다크/선택 상태를 안정적으로 처리한다.
- Dock 아이콘은 배경 포함 완성본을 사용한다. macOS는 iOS처럼 앱 아이콘 모서리를 자동으로 깎지 않으므로, PNG 자체가 squircle/투명 코너를 포함해야 한다.
- `.icns`는 파생 산출물이다. 직접 편집하지 말고 `AppIcon.png`를 교체한 뒤 `./scripts/dev.sh package`로 재생성한다.

## 3. 색상 체계

### 3.1 브랜드 색

현재 브랜드 아이콘에서 관측한 대표 색상:

| 토큰 | 값 | 사용처 |
|---|---:|---|
| `brandMintLight` | `#ECF8F2` | App icon 밝은 배경, 부드러운 브랜드 표면 |
| `brandMint` | `#83E2C1` | 깃펜 잎, 내부 로고 포인트 |
| `brandMintDeep` | `#73B89E` | App icon 하단/우하단 깊이감 |
| `brandTeal` | `#015254` | 깃펜 줄기/펜촉, 강한 대비가 필요한 브랜드 요소 |

이 값은 SwiftUI 전역 토큰으로 아직 고정하지 않는다. 반복 사용이 3곳 이상으로 늘어나면 `MintoDesignTokens` 같은 작은 내부 enum으로 승격한다.

### 3.2 시스템 색 우선

일반 UI는 macOS 시스템 색을 우선한다.

- 배경: `Color(nsColor: .windowBackgroundColor)`
- 표면: `Color(nsColor: .controlBackgroundColor)`
- 강조 표면: `Color(nsColor: .textBackgroundColor)`
- 경계: `Color.secondary.opacity(0.18)`
- 선택/포커스: `Color.accentColor`

이유:

- 라이트/다크 모드와 접근성 대비를 OS가 처리한다.
- 앱 전체를 브랜드 민트로 칠하지 않는다. 브랜드 색은 아이콘, 헤더 로고, 중요한 empty/illustration 포인트에 제한한다.

### 3.3 상태 색

- 성공/완료: 시스템 green 또는 `brandMint` 계열을 작은 면적으로 사용한다.
- 경고: 시스템 orange 계열. 카드 경계는 `Color.orange.opacity(0.2~0.3)` 수준을 우선한다.
- 오류: 시스템 red 계열. 실패를 숨기지 말고 복구 행동을 함께 보여준다.
- 정보/선택: `Color.accentColor`와 `Color.accentColor.opacity(0.08~0.12)` 조합을 우선한다.

## 4. 타이포그래피

macOS 시스템 폰트를 사용한다. 커스텀 폰트는 도입하지 않는다.

| 역할 | 권장 |
|---|---|
| 화면 대표 제목 | `.system(size: 20, weight: .bold)` 또는 화면 맥락에 맞는 큰 bold |
| 카드/섹션 제목 | `.headline` 또는 `.system(size: 13~16, weight: .semibold)` |
| 본문 | `.body` 또는 `.system(size: 13~15)` |
| 보조 설명 | `.caption`, `.system(size: 12)`, `.foregroundColor(.secondary)` |
| 버튼 | `.system(size: 13, weight: .semibold)` 중심 |

원칙:

- 회의 제목, 요약 문장, 검색 결과는 읽기가 목적이므로 과한 장식보다 행간/여백을 우선한다.
- 보조 정보(날짜, 길이, 구간 수, provider 등)는 `.secondary`로 낮춘다.
- 민감하거나 중요한 상태는 색만으로 전달하지 말고 텍스트도 함께 둔다.

## 5. 레이아웃과 간격

### 5.1 기본 간격

| 용도 | 권장 값 |
|---|---:|
| 화면 바깥 padding | 20~24 |
| 헤더 수직 padding | 16 |
| 카드 내부 padding | 16~24 |
| 카드 간격 | 12~16 |
| 버튼/칩 내부 수평 padding | 10~16 |
| 작은 요소 간격 | 6~10 |

기존 `MeetingLibraryView`는 `padding(.horizontal, 22)`, `padding(.vertical, 16)`, 카드 radius 8을 사용한다. 새 화면은 특별한 이유가 없으면 이 리듬을 따른다.

### 5.2 Radius

| 요소 | 권장 radius |
|---|---:|
| 카드/입력/작은 패널 | 8 |
| 작은 선택 카드 | 6~8 |
| pill/chip/primary action | `Capsule()` |
| Dock 앱 아이콘 | 이미지 자체에 squircle 포함 |

radius를 화면마다 임의로 늘리지 않는다. 큰 브랜드 일러스트나 empty card처럼 명확한 이유가 있을 때만 12 이상을 쓴다.

### 5.3 밀도

- 회의 중 overlay는 조밀하고 방해 적게.
- 회의 목록/상세는 스캔 가능성이 중요하므로 카드 경계와 섹션 분리를 명확히.
- 설정은 단계적으로 펼친다. 고급 설정을 첫 화면에 모두 노출하지 않는다.

## 6. 컴포넌트 규칙

### 6.1 Primary action button

- `.buttonStyle(.borderedProminent)`는 금지한다.
- 이유: non-key window에서 강조 배경이 사라지고 흰 라벨만 남아 대시보드형 사용 맥락에서 부적합하다.
- 강조 버튼은 `ProminentActionButtonStyle`처럼 배경을 직접 그린다.
- 비활성 상태는 배경/텍스트 대비를 유지하되, 클릭 가능해 보이지 않게 opacity와 설명을 조절한다.

### 6.2 Secondary action button

- 파일 가져오기, 용어집, 전사 복사 같은 보조 행동은 시스템 버튼 + `controlSize(.large/.small)`을 우선한다.
- 같은 줄에 primary와 secondary가 같이 있으면 primary는 오른쪽 또는 주요 진행 방향에 둔다.

### 6.3 Cards

- 카드 경계는 `Color.secondary.opacity(0.18)` 수준.
- 카드 배경은 시스템 surface를 우선한다.
- 선택된 카드에는 accent tint (`Color.accentColor.opacity(0.08~0.12)`)와 경계 강화 (`opacity(0.32~0.45)`)를 함께 쓴다.
- 텍스트만으로 selected를 표시하지 않는다.

### 6.4 Search field

- 검색은 회의 목록의 중심 작업이다.
- placeholder는 검색 대상과 범위를 구체적으로 말한다. 예: “회의, 안건, 결정사항 검색”.
- LLM 답변 생성은 검색과 별도 명령으로 둔다. 검색 입력 자체가 외부 provider 호출을 의미하게 만들지 않는다.

### 6.5 Chips / tags

- Capsule 형태를 우선한다.
- 작은 배경 tint + 짧은 텍스트.
- 태그가 많으면 한 줄 overflow보다 수평 스크롤 또는 줄바꿈 전략을 명확히 한다.

### 6.6 Segmented controls / tabs

- 요약/전사/관련 문서처럼 같은 record 안의 보기 전환에 사용한다.
- 선택 상태는 배경과 텍스트 weight로 함께 표현한다.

## 7. 상태 표현

모든 새 UI는 최소한 아래 상태를 검토한다.

| 상태 | 가이드 |
|---|---|
| Empty | 사용자가 다음에 할 수 있는 행동을 같이 제시한다. 예: 새 회의, 파일 가져오기, 설정 연결. |
| Loading | 무엇을 기다리는지 말한다. 긴 작업은 취소/백그라운드 가능성을 검토한다. |
| Success | 결과와 다음 행동을 함께 보여준다. |
| Error | 실패 원인과 복구 방법을 분리해 보여준다. 로그에는 민감정보 없이 판별 증거를 남긴다. |
| Disabled | 왜 비활성인지 알려준다. token 없음/권한 없음/모델 준비 중을 구분한다. |

상태 텍스트는 구체적이어야 한다. “오류가 발생했습니다”만 쓰지 않는다.

## 8. 화면별 가이드

### 8.1 Meeting Library

- 좌측은 회의 탐색, 우측은 선택 회의의 빠른 이해와 행동에 집중한다.
- 헤더에는 `LogoMark.png`와 제품명 `Minto`를 사용한다.
- 검색은 상단 중심에 두고, 새 회의/파일 가져오기/용어집 같은 주요 행동은 오른쪽에 둔다.
- 회의 카드에는 제목, 시간, 길이, 구간 수, 요약 일부를 노출한다.

### 8.2 Recording / Floating overlay

- 회의 중에는 방해하지 않는 것이 우선이다.
- 실시간 preview와 final transcript의 역할을 시각적으로 구분한다.
- 녹음 중/정지/마무리 중 상태가 색과 텍스트로 모두 드러나야 한다.

### 8.3 Meeting setup

- 설정은 단계적으로 펼친다.
- 회의 주제, 용어집, 문서 문맥은 “참고자료”임을 분명히 한다.
- 마이크/시스템 오디오/권한 상태를 사용자가 착각하지 않게 표현한다.

### 8.4 Settings

- provider, 모델, 로컬/클라우드 처리를 명확히 구분한다.
- token 없음, 미로그인, 네트워크 오류, provider 미지원은 다른 상태다.
- 고급 설정은 접거나 보조 설명을 둔다.

### 8.5 Export / Publish

- Markdown export는 기본 fallback으로 유지한다.
- Confluence 등 외부 publish 전에는 위치와 제목을 확인한다.
- 외부 전송 여부를 명확히 보여준다.

## 9. macOS-specific rules

- `MenuBarExtra` 아이콘은 template 이미지(`MenuBarIcon.png`)를 쓴다.
- 앱 상단 메뉴(🍎 옆)는 이름 텍스트만 표시된다. 아이콘을 넣으려 하지 않는다.
- `.buttonStyle(.borderedProminent)` 금지. 강조 버튼은 직접 배경을 그린다.
- non-key window에서도 버튼 라벨과 배경 대비가 유지되어야 한다.
- `.app` 패키징 아이콘은 `scripts/dev.sh package`에서 `.icns`로 생성한다.
- raw 바이너리 실행에서는 `NSApp.applicationIconImage` 런타임 주입으로 Dock 아이콘을 표시한다.
- 앱 실행 검증은 `./scripts/dev.sh run`을 사용한다. `swift run`은 코드서명/Keychain 문제 때문에 금지한다.

## 10. 디자인 변경 프로세스

### 10.1 Pencil 필요 조건

다음 중 하나라도 해당하면 구현 전에 Pencil로 flow를 설계하고 `.pen`과 export 이미지를 `Resources/designs/`에 저장한다.

- 3단계 이상 flow
- 4개 이상 상태
- 사용자의 mental model 변화
- 새 주요 화면 또는 기존 화면의 역할 변화

### 10.2 문서화 위치

- UI 디자인 시스템: `docs/ui-design-guide.md`
- 기능별 구현 계획/설계: `docs/work/`
- 아키텍처 결정: `docs/adr/`
- Pencil 산출물: `Resources/designs/`

### 10.3 리뷰 체크리스트

UI 변경 PR/커밋은 다음을 확인한다.

- 이 문서의 브랜드/아이콘/색/상태 규칙과 충돌하지 않는가?
- empty/loading/success/error/disabled 상태를 고려했는가?
- 라이트/다크 모드와 non-key window에서 대비가 유지되는가?
- 메뉴바/Dock/Finder/앱 내부 로고의 역할을 혼동하지 않았는가?
- 외부 provider 전송 여부와 로컬 처리 여부가 명확한가?
- 민감정보가 UI/로그에 노출되지 않는가?

## 11. 변경 관리

이 문서는 살아있는 기준이다. UI 작업 중 새 규칙이 생기면 코드와 함께 갱신한다. 단, 단발성 화면 취향이나 실험적 시안은 이 문서에 바로 고정하지 말고 `docs/work/` 또는 `Resources/designs/`에 먼저 둔다.
