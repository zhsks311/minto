# Minto2

**기기 안에서 끝나는 Mac 회의록.** 회의를 실시간으로 받아 적고, 읽기 좋은 회의록으로 정리하고, 나중에 다시 찾아 물어볼 수 있는 macOS 회의 지식 도구입니다.

> macOS 14+ · Apple Silicon · Swift 6 · 음성은 클라우드로 보내지 않습니다

---

## 왜 Minto2인가?

대부분의 회의록 앱(Otter, Granola, Fireflies, Notion AI…)은 **당신의 회의 음성을 자사 서버로 업로드**하고, **매달 구독료**를 받습니다. 민감한 사내·고객·법무 대화가 통째로 외부에 올라가고, 인터넷이 없으면 동작하지 않으며, 결제를 멈추면 기록 접근까지 위태로워집니다.

Minto2는 반대 방향으로 설계됐습니다.

| | 일반 클라우드 회의록 앱 | **Minto2** |
|---|---|---|
| 음성 처리 | 서버로 업로드해 전사 | **기기 안에서 전사** (WhisperKit + Metal) |
| 오프라인 | 불가 | **음성 전사는 오프라인 동작** |
| 비용 | 월 구독 | **앱 자체는 구독 없음** — 내 하드웨어로 실행 |
| 한국어 | 영어 우선, 한국어는 들쭉날쭉 | **한국어 회의 특화** (문맥·용어집 교정) |
| AI 요약 | 제공사 모델 고정, 클라우드 강제 | **로컬 LLM(Ollama 등) 또는 원하는 클라우드 LLM 선택** |
| 내 기록 | 제공사 클라우드에 종속 | **내 디스크에 JSON으로 저장** |

핵심은 하나입니다 — **"녹음된 회의 음성은 어떤 이유로도 외부 서버로 전송되지 않는다"**가 제품의 1번 원칙입니다.

## 프라이버시 경계 (정직하게)

"로컬"을 뭉뚱그리지 않고 정확히 긋습니다.

- **기기 안에서만 처리** — 음성 캡처, 음성→텍스트 전사(STT), 회의 검색 임베딩. 음성 데이터 자체는 절대 나가지 않습니다. (STT 모델만 최초 1회 내려받고, 이후 전사는 오프라인)
- **켰을 때만, 텍스트만 나감** — AI 교정·요약·검색 답변에 클라우드 LLM을 쓰도록 *직접 선택한 경우에만* 외부로 나갑니다. 그것도 음성이 아니라 텍스트이며, 검색 답변은 관련 근거 조각만 보냅니다.
- **완전 로컬도 가능** — LLM마저 Ollama 같은 로컬 모델로 돌리면 전 과정이 오프라인입니다.
- **캘린더·미리알림도 기기 안에서만** — 일정 프리필과 할 일 내보내기는 macOS EventKit(로컬)만 씁니다. 외부 캘린더 서버로 전송하지 않고, 일정 제목·참석자는 로그에도 남기지 않습니다.
- 토큰·프롬프트·전사 원문은 로그에 남기지 않습니다.

## 주요 기능

- 🎙 **실시간 전사** — 마이크 + **시스템 오디오 캡처**로 화상회의 상대방 목소리까지 받아 적기. 떠 있는 오버레이로 전사 흐름 확인
- 📝 **구조화된 회의록** — 요약·목차·결정사항·할 일·미해결 질문으로 자동 정리
- 📅 **캘린더 연동** — 회의 시작 시 macOS 캘린더의 다가오는 일정을 감지해 제목·시각·참석자 프리필 (EventKit, 온디바이스)
- ✅ **할 일 관리** — 회의 할 일을 macOS 미리알림으로 내보내고, 여러 회의에 걸친 미완료 할 일을 한곳에서 확인
- 🗣 **발화 분석** — 화자별 발화 시간·비율을 회의 상세에서 확인
- 📂 **파일로 회의록 만들기** — 기존 음성/영상 파일을 넣어 사후 전사
- 🔎 **회의 검색 & 답변** — 저장된 회의에 질문하면 **출처 회의·시간과 함께** 근거 기반 답변 (로컬 임베딩 semantic search)
- 📖 **용어집(Glossary)** — 회의별 전문용어·고유명사를 미리 등록해 전사 교정 품질↑
- 🔗 **업무 도구 연동** — Confluence / Notion 문서 조회 및 Markdown·Confluence 내보내기
- 🧰 **메뉴바 상주 앱** — 회의 시작/종료를 메뉴바에서 제어

자세한 기능 정의는 [`docs/service-definition.md`](docs/service-definition.md)를 참고하세요.

---

## 시작하기 (개발자)

### 사전 준비

- **macOS 14+ / Apple Silicon(M1 이상)**
- **Xcode 16+** (Swift 6 toolchain)
- **자가서명 코드서명 인증서 "Minto2 Dev"** — 아래 1회 설정 참고

> STT 모델은 첫 실행 시 자동으로 내려받습니다. 오프라인에 미리 두려면 환경변수 `WHISPER_MODEL_FOLDER`로 로컬 폴더를 지정할 수 있습니다.

### 1회 설정: 코드서명 인증서

이 앱은 OAuth 토큰 등을 Keychain에 저장합니다. adhoc 서명은 재빌드마다 해시가 바뀌어 매번 권한창이 뜨므로, **고정된 자가서명 인증서**로 서명합니다.

1. **Keychain 접근(Keychain Access)** 실행
2. 메뉴 `인증서 지원 > 인증서 생성…`
3. 이름 **`Minto2 Dev`**, 종류 **자가서명 루트(Self-Signed Root)**, 용도 **코드 서명(Code Signing)**
4. 생성 완료 (자가서명이라 신뢰가 `NOT_TRUSTED`로 떠도 서명에는 문제 없습니다)

> 다른 이름을 쓰려면 `MINTO_SIGN_IDENTITY` 환경변수로 지정하세요.

### 빌드 · 실행 · 테스트

```bash
./scripts/dev.sh run            # 빌드 + 서명 + 실행
./scripts/dev.sh build          # 빌드 + 서명만
./scripts/dev.sh test [필터]    # 테스트 빌드 + 서명 + 실행
./scripts/dev.sh sign           # 현재 산출물 재서명만
```

> ⚠️ **`swift run`을 쓰지 마세요.** SPM이 실행 직전 adhoc 서명을 다시 덮어써서 Keychain 권한이 깨집니다. 반드시 `./scripts/dev.sh run`을 사용하세요.

---

## 배포하기 (소수 공유)

동료나 본인의 다른 Mac에 건네줄 `.app` 번들을 만듭니다.

```bash
./scripts/bundle.sh             # release 빌드 + Minto2.app 생성 + 서명 → dist/
./scripts/bundle.sh --zip       # 위 + 배포용 dist/Minto2.zip 생성
```

번들에는 `Resources/AppIcon.icns`가 포함되어 Finder/Dock에서 앱 아이콘이 표시됩니다.

> ⚠️ 이 번들은 **공증(notarization)되지 않습니다.** 받는 사람은 첫 실행 시 한 번만 아래가 필요합니다.
> - **우클릭 > 열기** → "열기" 확인, 또는
> - 터미널에서 `xattr -dr com.apple.quarantine Minto2.app`
>
> 이 방식은 **개발자/소수 동료 배포**용입니다. 외부 일반 사용자에게 "더블클릭하면 바로 열리는" 경험으로 배포하려면 유료 Apple Developer Program($99/년) + Developer ID 서명 + 공증이 필요합니다. 자세한 배경은 [`docs/dev-onboarding-and-distribution-plan.md`](docs/dev-onboarding-and-distribution-plan.md) 참고.

---

## 프로젝트 구조

```
Sources/
├── Minto/                  # MintoCore: 앱 본체 라이브러리
│   ├── App/                #   앱 진입점, AppDelegate
│   ├── UI/                 #   SwiftUI 화면 (회의 목록·요약·전사 오버레이·설정)
│   ├── ViewModels/         #   화면 상태
│   ├── Models/             #   회의·전사·요약·용어집 데이터 모델
│   └── Services/           #   STT·VAD·화자분리·LLM·검색·Notion/Confluence 엔진
└── MintoApp/               # minto2: 실행 타깃 (Info.plist 주입)
Tests/MintoTests/           # Swift 단위·통합 테스트
scripts/                    # dev.sh (개발 빌드) + Python STT 분석·벤치 도구
docs/                       # 기능 정의·작업 로그·STT 연구 문서
Resources/                  # 모델·자원 (대용량 모델 파일은 git 제외)
```

> `scripts/`의 Python 스크립트는 **STT 품질 분석·벤치마크용 사이드카**이며 앱 런타임과 별개입니다. 앱 본체는 모두 `Sources/`에 있습니다.

## 기술 스택

- **STT**: [WhisperKit](https://github.com/argmaxinc/WhisperKit) (온디바이스, Metal 가속) — Apple SpeechAnalyzer/SFSpeech 엔진도 후보로 포함
- **화자분리**: [FluidAudio](https://github.com/FluidInference/FluidAudio)
- **VAD**: Silero VAD
- **연동**: [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (Notion OAuth)
- **동시성**: Swift 6 strict concurrency (`@ModelActor` + `AsyncStream`)

## 더 읽을거리

- [`docs/service-definition.md`](docs/service-definition.md) — 기능 정의서
- [`docs/mac-meeting-recorder.md`](docs/mac-meeting-recorder.md) — 아키텍처 설계·결정 기록
- [`docs/work-log.md`](docs/work-log.md) — 작업 로그 인덱스
- [`docs/stt-engine-benchmark-guide.md`](docs/stt-engine-benchmark-guide.md) — STT 엔진 벤치마크 한 명령 사용법(측정→비교→판정→리포트)
- [`docs/stt-benchmark-glossary.md`](docs/stt-benchmark-glossary.md) — STT 벤치마크 용어집(비전문가용, 받아쓰기 시험 비유)
