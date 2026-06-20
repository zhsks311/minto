# 첨부 문서 직접 주입 파이프라인 설계 (용어·맥락을 전사·교정·요약에 직접 활용)

작성일: 2026-06-19 · 최종 갱신: 2026-06-21 (직접 주입 구조로 확정, Codex 구현가능성 1패스 반영)

> 이 문서는 여러 차례 논의로 방향이 바뀌었고(용어집 경유 → 직접 주입), **아래가 최종 합의안**이다. 과거 "용어집 후보로 흘린다" 프레이밍은 폐기됨.

## 배경 / 문제

첨부 문서는 가공 없이 raw 텍스트로 프롬프트에 들어가고, 앞부분만 잘린다.

- **가공 0**: `combinedDocument`(`MeetingSetupView.swift:409`) = `[수동입력, Confluence].joined()` + trim이 전부.
- **위치 맹목 절단**: 교정 `prefix(1500)` / 증분요약 `prefix(2500)` / 최종요약 `prefix(4000)` — 긴 문서 뒤쪽 핵심 용어는 영구 누락.
- **전사(STT)는 용어를 아예 모름**: `WhisperKitSTTEngine`·`STTService`에 glossary/문서 참조 0. 용어집조차 **교정·요약(LLM 단계)에서만** 쓰이고(`LLMCorrectionService`, `SummaryService`), 인식 단계엔 0 영향. → 전사 정확도는 문서 덕을 한 번도 못 봤다.

## 가치 판단 (왜 정적-우선 + 직접 주입인가)

문서는 두 자산을 담고, 가치·실현방법이 다르다:

| 자산 | 쓰임 | 가치 | 정적분석으로? |
|---|---|---|---|
| **용어(표기 앵커)** | 전사·교정 | **높음** (전사에 없는 정확한 철자 = 고유 가치, CER 측정가능) | ✅ regex + POS-보조 한국어 + 통계 |
| **이해된 맥락** | 요약 | 낮음 (요약은 전사 기반·grounding 규칙이 상한을 누름, 전사와 중복) | ⚠️ 추출(extractive)까지만, 이해는 LLM |

원리: "맥락 많을수록"이 아니라 **"신호 대 잡음 높을수록"** 정확하다. raw prefix는 잡음 많고 끝부분 버리는 열등한 선택.

---

## 핵심 결정 4가지

### (1) 직접 주입 구조 (용어집 큐레이션 우회)

문서를 1회 가공한 **`DocumentContext { terms:[String], contextDigest:String }`** 를 만들어, **GlossaryStore 후보·승인 시스템을 거치지 않고** 각 단계의 입력에 직접 넣는다.

```
문서 첨부/녹음 시작 → (정적) 추출 → DocumentContext
   ├─ MeetingContext (라이브, ephemeral)  → 전사(bias)·교정·요약
   └─ record에 영속(record.document 재사용) → 재요약
```

- **왜 용어집(GlossaryStore)을 안 거치나**: GlossaryStore는 cross-meeting 누적·사용자 큐레이션 도구다(후보 제안→승인). "이번 회의를 즉시 돕는다"는 목표엔 우회로이고, **후보는 라이브 교정에 안 닿는다**(라이브 교정은 `MeetingContext.glossary`를 읽지 `GlossaryStore`를 읽지 않음 — Codex 검증). 그래서 **이번-회의 정확도용 직접 주입**과 **전역 큐레이션(GlossaryStore)**을 분리하고, 본 설계는 전자만 다룬다. (선택: 같은 용어를 GlossaryStore 후보로도 제안 가능하나 별도·부가.)
- **주입 지점**:
  - 교정/요약: `MeetingContext.glossary`(프롬프트 용어 슬롯)에 용어 병합 → `CorrectionPrompt`/`SummaryPrompt`가 그대로 소비(프롬프트 코드 변경 최소).
  - 전사: `terms` → `DecodingOptions.promptTokens`(아래 (3)).
- **Swift 6 동시성**: `MeetingContext`/`GlossaryStore`는 `@MainActor`. 추출은 `Task.detached`(MainActor 점유 금지), 병합은 `await MainActor.run { … }`로 hop.
- **summaryGlossary 스냅샷**: 라이브 병합 시 최종 요약의 `summaryGlossary`(record 영속)에 문서 용어가 섞일 수 있음. 기본 **허용**(요약에 쓴 용어 기록이라 합리적). 완전 비영속이 필요하면 별도 분리.

### (2) 선별 + 상한 장치 (전 단계 공통)

"많이"가 아니라 **"정확한 소수"**. 비용 폭발은 이미 캡으로 막혀 있으나(STT ~111토큰 자동절단, 프롬프트 글자예산), 단순 절단은 **중요 용어가 잘리고 잡음이 남으며 할루시네이션을 키운다**.

- **랭킹**: 빈도 × distinctiveness(TF-IDF — 다른 회의 대비 이 문서에만 잦은 단어) → 중요도 순.
- **단계별 cap**(측정으로 튜닝할 시작값):
  - **STT 바이어싱**: 최상위 **~10–20** (고신뢰 ASCII 위주). 작게 = 할루시네이션↓.
  - **교정/요약 주입**: **~20–30** (글자 예산 내).
- **신뢰도 계층**: ASCII/약어/숫자-하이픈 = 고신뢰 → STT까지. 한국어 명사(저신뢰) = 교정/요약까지만(STT 자동주입 금지).
- **필터·dedup**: 불용어·짧은 토큰 제거 + 기존 회의 용어 중복 제거.

### (3) STT 바이어싱 — 측정 게이트 (플래그 뒤, net-new)

전사 단계는 현재 용어 활용이 **완전히 비어 있어**, "더 정확한 전사"는 STT 바이어싱이 유일한 길. `WhisperKitSTTEngine`의 `DecodingOptions`에 `promptTokens` 지원 확인됨(`Configurations.swift:175`).

- **메커니즘**: 고신뢰 용어 상위 N개 → WhisperKit 토크나이저로 토큰 ID → `DecodingOptions.promptTokens` 세팅(엔진이 `MeetingContext`에서 용어 수신).
- **1순위 위험 = 할루시네이션(품질)**, 지연 아님. soft bias라 안 들린 말을 용어로 지어낼 수 있음. 기존 가드(`avgLogprob>-1.0`, `compressionRatio<2.4`, `noSpeechThreshold 0.80`)가 일부 방어.
- **반드시 측정 후 채택**: 기존 STT 벤치마크 하니스(국회 회의 코퍼스)로 **A/B** — ① 해당 용어 CER ② 반복률/할루시네이션 ③ 지연. 셋이 허용 범위일 때만 기본 on 검토.
- **fail-soft**: 용어 없으면 `promptTokens=nil`(현재 동작, 무회귀). 부작용 크면 플래그로 off.
- **opt-in 플래그**로 출시 — 교정/요약 직접 주입(저위험) 이후 별도 Phase.

### (4) 캐시 비용 정정 (이전 분석 과장 → 바로잡음)

초기 분석에서 "promptTokens → prefill 캐시 off → 느려짐"을 과대평가했음. 정정:

- prefill 시퀀스는 **고정 4토큰**(`[SOT, ko, transcribe, timestamp]`, `TextDecoder.swift:314-335`). prefill 캐시는 이 4토큰 KV를 **룩업 테이블에서 꺼내는 것**(`:357`)뿐.
- promptTokens 설정 시 캐시 off되나(`:355` TODO, "non-zero index에서 깨짐"), 어차피 프롬프트 토큰을 forward로 처리하므로 **4토큰 재계산의 한계비용은 거의 0**.
- 진짜 비용은 **프롬프트 N토큰(≤~111)을 매 윈도우 1패스 처리**하는 것 — 병렬 1패스라 모데스트.
- **결론: 캐시는 망설일 이유가 아니다.** STT 바이어싱의 진짜 관문은 (3)의 할루시네이션 품질.

---

## Phase 구성 (가치·위험 순)

| Phase | 내용 | 위험 | 신규 파일/지점 |
|---|---|---|---|
| **1a** | 용어 추출 → 교정·요약·재요약 **직접 주입** | 낮음 | `DocumentTermExtractor`(신규), `MeetingContext.glossary` 병합 |
| **1b** | 요약 맥락: prefix → **정적 발췌** | 낮음 | `DocumentContextSelector`(신규), `SummaryPrompt` |
| **2** | **STT 바이어싱**(플래그+측정) | 중 | `WhisperKitSTTEngine` `DecodingOptions.promptTokens` |
| **3** | LLM digest(맥락 이해) | — | 보류 — 구체적 결손 사례 나올 때만 |

(2)의 선별+상한 장치는 전 Phase 공통.

## 한국어 용어 추출 방법 (NER 의존 금지)

Apple `NLTagger`의 한국어 **NER(`.nameType`)은 신뢰 불가** → 기반으로 삼지 않는다. 대신:

1. **`NLTokenizer(.word)`** — 토큰화(조사 분리, 가장 신뢰 가능한 부분).
2. **`NLTagger(.lexicalClass)`** — 명사 보존(POS는 NER보다 안정적, 단 불완전).
3. **빈도 + distinctiveness(TF-IDF, 배경=다른 회의)** — 의미 분류 대신 **통계적 두드러짐**으로 도메인 용어 포착(결정론적, NER 불필요).
4. **필터·상한**.

기대치: 한국어는 **재현율 양호·정밀도 중간** → STT 자동주입엔 부적합(고신뢰 ASCII만), 교정/요약 주입엔 충분. 정밀도 부족은 단계별 cap·계층으로 흡수.

ASCII/약어/숫자-하이픈은 정규식으로 **고정밀** 추출(전 단계 활용).

## 측정 (CER vs 가독성 분리 — CLAUDE.md)

- **Phase 1a / 교정·전사**: 고유명사·용어 CER 개선(용어 주입 on/off). 핵심 성공 지표.
- **Phase 2 / STT**: 위 (3) A/B(용어 CER·할루시네이션·지연).
- **Phase 1b / 요약**: 가독성(주관, 별도 지표) — CER와 섞지 않는다.
- 추출 품질: 정밀도(오탐률)·재현율 샘플 점검.

## 영향 받는 파일 (예상)

- 신규 `Sources/Minto/Services/DocumentTermExtractor.swift` (정적, LLM 없음 — `CorrectionAliasExtractor`의 "순수 규칙" 패턴)
- 신규 `Sources/Minto/Services/DocumentContextSelector.swift` (Phase 1b)
- `Sources/Minto/Services/MeetingContext.swift` — 문서-파생 용어 ephemeral 병합 경로
- `Sources/Minto/UI/MeetingSetupView.swift` / 녹음 시작 경로 — `Task.detached` 추출 트리거
- `Sources/Minto/Services/SummaryPrompt.swift` — Phase 1b prefix → selector
- `Sources/Minto/Services/WhisperKitSTTEngine.swift` — Phase 2 promptTokens
- (교정 프롬프트는 변경 없음 — `MeetingContext.glossary` 경유로 자동 반영)

## 비목표 (YAGNI)

- GlossaryStore 후보·승인 경유 — 본 설계는 직접 주입만(전역 큐레이션은 별도).
- LLM digest(Phase 3) — 측정 후 결정.
- 추상적 요약/패러프레이즈 — 정적 불가, 보류.
- 문서를 요약 사실로 사용 — grounding 규칙 위반, 안 함.
- 외부 형태소 분석기 의존 — Apple `NaturalLanguage`(기본 프레임워크)만.

## 다음 세션 시작점

1. **Phase 1a 먼저 구현** (Codex 위임 → opus+codex 크로스리뷰 → CER 측정). 가장 안전·측정가능.
2. 1a 효과 확인 후 1b → 2(플래그+벤치마크) 순.
3. 구현 전 이 문서의 (1)~(4)와 한국어 추출 방법을 그대로 따른다.
