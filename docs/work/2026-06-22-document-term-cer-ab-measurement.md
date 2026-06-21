# 문서 용어 주입 교정 CER A/B 측정 (Phase 1a 종단 검증)

작성일: 2026-06-22 · 브랜치: `feat/document-term-injection`

## 목적

첨부 문서에서 정적 추출한 용어를 교정 프롬프트에 주입(ON)했을 때, 미주입(OFF) 대비 교정 후 CER이 개선되는지 종단 측정한다. Phase 1a(`feat(correction)` 3c60cf3)의 실효를 실제 LLM 교정으로 확인하는 단계.

## 테스트

`Tests/MintoTests/MeetingCorpusTests.swift`의 `documentTermInjectionCER()`.

방법론은 같은 파일 `correctionContributionCER()`을 따른다 — **창당 STT 1회**로 얻은 raw를 OFF/ON 양쪽 교정에 재사용해, ANE 비결정성·방송자막 비-verbatim 바닥이 양쪽에 동일하게 박혀 **델타에서 상쇄**되게 한다. 절대 CER은 무시하고 **공유-raw 델타만** 신뢰한다.

- **OFF**: `CorrectionPrompt.build(topic, glossary: baseGlossary, context: prevRaw, text: raw)` — 문서·추출용어 없음.
- **ON**: `glossary: DocumentTermExtractor.mergeGlossary(baseGlossary, document)` + `document:` 주입 — Phase 1a 전체.
- 핵심 지표: **ON−OFF 델타**(문서 주입의 순기여, 음수=개선). 보조: OFF−raw, ON−raw.
- 가드: insertion(교정본이 raw 1.2배↑ 길면 추가 의심 → 탈오염 누적), touch rate·폴백을 OFF/ON 각각 집계.

## 실행 (앱 Codex 로그인 선행 필수)

`CodexOAuthService.shared.isLoggedIn`(앱 keychain) 필요 — codex CLI 로그인과 별개다. 앱에서 Codex 로그인 후:

```bash
RUN_STT_TESTS=1 RUN_DOC_CER=1 \
MEETING_WAV=외교통일위원회_20260520_full.wav \
MEETING_SMI=외교통일위원회_20260520_smi.json \
MEETING_DOCUMENT=sample/meeting/documents/외교통일위원회_20260520_agenda.txt \
swift test -c release --filter MeetingCorpusTests/documentTermInjectionCER
```

env: `MEETING_CORR_WINDOWS`(기본 20, OFF+ON 2배 호출이라 비용 보호), `MEETING_TOPIC`, `MEETING_GLOSSARY`.

## fixture (재현용 — `sample/`은 gitignored라 미커밋)

`sample/meeting/documents/외교통일위원회_20260520_agenda.txt` 내용(외교통일위원회 20260520 회의의 공개 안건을 agenda 형식으로 구성, correct 표기 포함):

```
제435회 국회(임시회) 외교통일위원회 제1차 전체회의 — 외교안보 현안질의

[회의 개요]
- 위원회: 외교통일위원회 (약칭 외통위)
- 위원장: 김석기 위원장
- 여야 간사: 김영배 위원, 김건 위원
- 정부측 출석: 외교부 장관, 외교부 제1차관 박윤주(불출석 사유서 제출), 국가안보실

[의사일정]
제1항. 청원 심사기간 연장 요구의 건 (청원 3건, 심사기간 2026년 5월 29일까지 연장)
제2항. 외교안보 현안질의

[현안 배경]
- 호르무즈 해협 인근(아랍에미리트 부근)에서 우리나라 국제 해운사 HMM 소속 컨테이너선 나무호가 피격당한 사건 및 그 조사 결과
- 중동 정세, 이란·이스라엘 관련 외교안보 현안
- 의회 외교 및 국익 관련 현안 전반

[참고 용어]
외교통일위원회, 외통위, 청원심사, 의사일정, 불출석 사유서, 이석 사유서, 현안질의,
HMM, 나무호, 호르무즈, 아랍에미리트, 국가안보실, 외교부, 박윤주, 김석기, 김영배, 김건
```

추출 검증(`DocumentTermExtractor`): 위 문서 → 40개 용어(김석기·김영배·김건·박윤주·국가안보실·호르무즈·아랍에미리트·나무호·HMM 등 도메인 용어 전부 포함).

## 캐비엇 (해석 시 반드시)

- **best-case(upper-ish bound)**: fixture는 회의에 실제 등장하는 용어로 구성했다 → "문서가 회의 핵심 용어를 담고 있을 때"의 이득이다. 임의 문서의 field 대표성은 아니다.
- corpus 7개에 원래 첨부 문서가 없어 fixture를 작성했다. 다른 회의로 확장하려면 같은 형식의 agenda fixture를 추가한다.
- 측정은 추출 정밀도(상류)와 별개로 **교정 단계 종단 CER**을 본다. STT 바이어싱(Phase 2)은 turbo 모델 차단으로 별도 트랙.

## 발견 (이 측정이 드러낸 것)

fixture 작성 중 `NLTokenizer` 한국어 enumeration이 dash·공백하이픈 separator에서 토큰화를 전면 중단하는 버그를 발견 → `fix(correction)` eebad88로 수정(한국어 토큰화 입력을 단어문자 외 공백 1:1 치환). 측정용 fixture가 실제 문서를 흉내 내자 단위테스트·리뷰가 못 잡은 결함이 드러난 사례.
