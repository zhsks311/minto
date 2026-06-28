# 문장 단위 화자 구분 연구

작성일: 2026-06-29
브랜치: `feat/sentence-level-speaker-attribution`
목표: 전사와 화자를 더 잘 구분한다. 특히 **문장 단위로 화자를 귀속**한다.

---

## 1. 한 줄 결론

문장 단위 화자 구분에 필요한 **데이터(WhisperKit word-level 타임스탬프)는 이미 저장 끝까지 흐르고 있다.** 빠진 것은 그 단어 타임스탬프를 소비해 화자 경계로 전사를 쪼개는 **정렬 패스 하나뿐**이다. 새 무거운 의존성(wav2vec2 forced alignment 등)은 필요 없고, 오히려 한국어에서는 해롭다. 순수 Swift 알고리즘 레이어 추가로 해결한다.

---

## 2. 현재 상태 (코드 근거)

### 2.1 화자 배정은 "청크 1개 = 화자 1명"

`TranscriptSpeakerMatcher`(`Sources/Minto/Services/Diarization/TranscriptSpeakerMatcher.swift`)는 세그먼트 단위 최대 겹침 투표를 한다.

- 각 전사 `Segment`의 `[timestamp, timestamp+duration]` 구간을 회의 시작 기준 초로 변환(`:44-45`)
- 그 구간과 겹치는 모든 `DiarizedSpeakerSegment`를 화자별로 겹침 초 합산(`:49-61`)
- 가장 많이 겹친 화자 1명을 세그먼트 전체에 배정(`:64-69`)

즉 **한 전사 세그먼트에는 화자가 정확히 한 명만** 붙는다.

### 2.2 전사 세그먼트의 단위는 문장이 아니라 VAD 청크

- 라이브: `VADProcessor`가 침묵 1.5초 또는 최대 15초로 청크를 자름 → 세그먼트 길이 1.5~15초
- 임포트: 30초 고정 청크 (`MeetingFileImportUseCase(chunkSeconds: 30)`)

한 세그먼트(특히 임포트의 30초) 안에는 여러 문장과 여러 화자 교대가 들어있다. 그런데 2.1에 따라 **더 많이 말한 화자 1명만 남고 나머지는 사라진다.** 이것이 메모리에 기록된 "5명 회의가 4명으로 줄어드는" 손실의 직접 원인이다.

### 2.3 핵심: word 타임스탬프는 이미 있는데 안 쓴다

- `WordTimestamp(word, start, end)`가 `Segment.words: [WordTimestamp]?`로 존재 (`Sources/Minto/Models/Meeting.swift:3-21`)
- `WhisperKitSTTEngine`이 `wordTimestamps: true`로 요청해 채움
- `TranscriptSpeakerMatcher`가 `words`를 **그대로 통과만** 시키고 배정엔 안 씀 — 코드 주석이 자백: `// Word-level alignment is a later pass; this matcher assigns a speaker per transcript segment.` (`:25`)

> ⚠️ 주의: `WordTimestamp.start/end`는 **청크 내부 상대 초**(0 기준)다. diarization 세그먼트(오디오 절대 초)와 맞추려면 `세그먼트시작초 + word.start`로 절대화해야 한다. 세그먼트시작초 = `segment.timestamp - meetingStart`.

### 2.4 시간축은 (다행히) 오디오 기준이다

메모리는 "벽시계 `Date()`"를 우려했으나, 라이브/임포트 모두 실제로는 **오디오 샘플 offset**(`chunk.startSeconds = startSample / 16000`)을 시간 기준으로 쓰고 `Date`로 인코딩만 한다. 따라서 전사 구간과 diarization 구간은 같은 오디오 타임라인 위에 있어 정렬이 원리적으로 가능하다. (단, word 타임스탬프 자체의 정밀도 한계는 3.4 참조.)

---

## 3. 방법론 비교 (SOTA 조사 결과)

### A. word-level 다수결 재배정 + 문장 재분할 — **권장**

업계 표준(WhisperX의 화자 배정 단계와 동일한 골격). 단계:

1. **단어 절대화**: 각 세그먼트의 `words`를 `segmentStart + word.start/end`로 오디오 절대 초로 변환.
2. **단어별 화자 배정**: 각 단어 구간과 가장 많이 겹치는 diarization 세그먼트의 화자를 그 단어에 배정(중간점 포함 또는 최대 겹침).
3. **문장 경계 분할**: 단어열을 문장으로 나눈다. 경계 기준은 (a) 구두점, (b) 단어 간 침묵 갭(예: 0.5초 이상), (c) 화자 전환점. 셋 중 하나라도 만족하면 분할.
4. **문장 다수결**: 문장 내 단어들의 최빈 화자를 문장 화자로 확정. 3단어 미만의 짧은 화자 조각은 인접 화자에 흡수(업계 관행).

- 장점: **새 의존성 0**, 이미 있는 `words` 소비, 순수 Swift, 라이브·임포트·저장 경로에 동일 적용 가능. fail-soft 쉽다(words 없으면 기존 세그먼트 단위 배정으로 폴백).
- 한계: 정밀도가 WhisperKit word 타임스탬프 품질에 종속(3.4).

### B. wav2vec2 forced alignment (WhisperX 정식 경로) — **기각**

word 타임스탬프를 음소 강제정렬로 더 정확히 얻는 방식.

- 기각 근거: ① 한국어 모델(`kresnik/wav2vec2-large-xlsr-korean`)은 영어 대비 품질이 낮다는 보고. ② 온디바이스 macOS Swift에 wav2vec2 추론 스택을 새로 얹는 비용(CoreML 변환·모델 번들·메모리). ③ 우리는 이미 WhisperKit이 word 타임스탬프를 주므로 한계 효용이 작다.

### C. joint neural (Sortformer/whisper-diarization/diart 등) — **장기 후보**

전사와 화자분리를 함께 푸는 최신 연구. diart는 JOSS 2024, 실시간 가능하나 **Python 전용**. 우리 스택과 안 맞고, 기존 측정(메모리)에서 LS-EEND DER이 VBx의 2배라 카운트 정확도도 열세. → 지금은 배제, A로 충분.

---

## 4. 권장 설계 (구체) — critic 리뷰 반영본

> 초안은 "매처 뒤 2차 패스, 스키마 무변경, 한 곳만 고치면 전부"라고 했으나 critic이 **블로커 2건**을 잡았다: (C-1) Segment를 쪼개면 `id`가 바뀌어 사용자 화자 편집 보존(`editedSpeakerSegmentIds`)이 무력화 → 스키마 무변경 주장은 거짓, (C-2) 삽입 지점은 3곳. 아래는 반영본이다.

### 4.1 핵심 결정: Splitter는 **저장·임포트 시점에만**, 라이브엔 적용 안 함

라이브 전사 화면은 기존 `TranscriptSpeakerMatcher`(세그먼트 단위)를 그대로 유지한다. 문장 단위 정밀 분할은 **실제로 저장·재열람되는 산출물에만** 적용한다:

- 저장(녹음 종료): `LiveDiarizationFinalizeUseCase.finalize()` 반환 직전
- 임포트: `MeetingFileImportUseCase`의 `assignSpeakers(...)` 직후

이 한 결정이 critic 지적 셋을 동시에 해소한다:
- **M-1 라이브 깜빡임**: 라이브에서 매 청크 분할 → 세그먼트 id 목록이 매번 바뀌어 SwiftUI 전체 재렌더. 라이브에 적용 안 하면 발생 자체가 없다.
- **M-4 교정 배치 충돌**: 교정은 `pendingCorrectionIds`(UUID)로 추적 — 라이브 중 분할이 끼면 in-flight 교정과 id가 어긋난다. 저장 시점은 교정이 끝난 뒤라 안전.
- **C-1 라이브 편집 손실**: 라이브에서 분할이 안 일어나니 편집 시점의 id가 그대로 저장 단계까지 간다.

라이브 미리보기가 세그먼트 단위인 건 수용 가능한 트레이드오프다(미리보기 역할 — CLAUDE.md "preview와 final transcript의 역할을 구분한다").

### 4.2 `SentenceSpeakerSplitter` — diarization을 직접 재소비 (매처 결과 무시)

critic M-3/skeptic 지적: 매처 뒤 2패스는 같은 timeline을 두 번 계산하고 충돌 시 우선순위가 모호하다. WhisperX의 올바른 순서는 word → 배정 → 문장 분할이며 세그먼트 매처를 먼저 두지 않는다.

→ Splitter는 **diarization timeline을 직접 받아** word 단위로 재배정한다. 매처 결과(`segment.speaker`)는 폴백용으로만 본다.

입력: `[Segment]`(words 포함), `[DiarizedSpeakerSegment]`, `meetingStart`
처리(세그먼트별):
- `words != nil`: ① 각 단어를 `meetingStart` 기준 절대 초로(4.3) → ② 단어별 최대 겹침 화자 배정 → ③ 화자 전환점·구두점·침묵갭으로 문장 분할 → ④ 문장 내 다수결, 짧은 조각 흡수 → ⑤ 분할된 sub-Segment들 방출
- `words == nil`(SpeechAnalyzer·Nemotron·일부 임포트 청크): 분할하지 않고 매처가 붙인 `speaker` 그대로 통과 → **회귀 0**
- `diarization timeline 비어 있음`(diar 실패): 전체를 폴백 처리(분할 안 함)

출력: `[Segment]` — 문장 단위로 쪼개진 세그먼트. 각자 자기 구간의 `words`만 보유.

### 4.3 word 절대화 — 두 경로 공통 공식 + nil 폴백

라이브: `meetingStart = transcriptTimelineStartDate`, 임포트: `meetingStart = startedAt`. 두 경로 모두 `segment.timestamp - meetingStart == chunk.startSeconds`가 성립하므로 **공통 공식**: `절대초(word) = (segment.timestamp - meetingStart) + word.start`.
단, 라이브에서 `transcriptTimelineStartDate == nil`이면 호출부가 `committedSegments.first?.timestamp`로 폴백한다(`AppDelegate`) — 이 경우 첫 세그먼트 word 절대화가 약간 틀어질 수 있으므로, **호출부에서 항상 일관된 `meetingStart`를 Splitter에 넘기도록** 명시한다.

### 4.4 Segment.id 정책 (C-1 해소)

- 분할 시 **첫 sub-Segment는 부모 id를 승계**, 나머지는 새 UUID.
- **`editedSpeakerSegmentIds`에 부모 id가 있으면 그 세그먼트는 분할하지 않는다** — 사용자가 이미 화자를 결정했으므로 건드리지 않는다(저장 경로의 편집 보존 정신과 일치). 가장 단순하고 안전.
- `speakerEmbeddings`는 문자열 라벨("화자 N") 키라 id 분할의 영향을 받지 않는다. 다만 분할로 라벨이 바뀌는 세그먼트가 생기면 embedding 키 정합은 기존 finalize 경로(라벨→실명 치환)가 그대로 보장.

### 4.5 스키마 영향 (정정)

초안의 "무변경"은 부정확하다. **구조(JSON 필드)는 불변이지만 `segments` 배열 길이·id 구성이 달라진다**. 기존 저장 회의는 재분할하지 않으므로(새 저장분에만 적용) 읽기 호환은 유지된다 → CLAUDE.md "backward-compatible" 조건 충족. ADR은 여전히 불요(새 의존성·경계 변경·비호환 읽기 없음, ADR 0005의 후속 개선)이나, 이 판단을 작업 로그에 명시한다.

---

## 5. 측정·검증 방법 — critic 반영본

> critic M-2: "화자 카운트 보존"은 Splitter가 아니라 VBx diarization 정확도에 더 의존한다 → 효과가 혼재돼 해석 불가. 아래처럼 **Splitter 효과를 분리**한다.

### 5.1 1차: 합성 입력 단위 테스트 (Splitter 단독 정확도)

`SentenceSpeakerSplitter`는 순수 함수 → 화자 타임라인과 word 타임스탬프가 **알려진** 합성 케이스로 검증. 이게 Splitter 효과를 오염 없이 측정하는 유일한 길:
- 한 청크 안 2화자 교대 → 2개 세그먼트로 정확히 분할되는가
- 문장 경계(구두점/0.5초 갭/화자전환) 각각 단독·조합
- 3어절 미만 짧은 조각 흡수(한국어 어절 기준 — minor 1 참조)
- `words==nil` 폴백 = 입력 그대로
- diarization 빈 배열 폴백

### 5.2 2차: 실코퍼스 AB (VBx 출력 고정)

동일 오디오에 **같은 diarization timeline을 양쪽에 먹이고** Splitter only on/off 비교. VBx를 고정해야 "VBx 향상"과 "Splitter 효과"가 안 섞인다.
- 지표: 한 청크에 갇혀 사라지던 소수 화자가 살아나는 세그먼트 수, 화자 전환이 청크 중간에서 잡히는 사례.
- 경계 정확도: SMI 자막엔 화자 라벨이 없어 정량 DER 불가 → 소수 클립 **수동 검수(정성)**. 이건 인간 게이트임을 명시(자동 완료 판정 불가).

### 5.3 회귀 가드

- `words==nil` 경로에서 세그먼트 수·id·speaker가 기존과 byte-identical인지 단위 테스트.
- 빌드 + 기존 전체 테스트 무회귀.

관련(메모리): 코퍼스 `sample/meeting/raw/`, 하니스 `MeetingCorpusTests`, 저장 JSON으로 객관 검증.

---

## 6. 단계별 계획 (제안) — 순서 정정

> critic minor 2: 절대화 헬퍼가 Splitter 내부에서 필요해 Step 1/2 의존순서가 거꾸로였다. 합쳐서 재정렬.

> Step 1: `WordTimestamp` 절대화 헬퍼 + word→화자 배정 + `SentenceSpeakerSplitter` 순수 함수(분할·다수결·짧은조각흡수·폴백·빈timeline) → verify: 5.1 합성 단위 테스트 통과
> Step 2: 저장 경로 배선 — `LiveDiarizationFinalizeUseCase.finalize()` 반환 직전 삽입, id 정책(4.4)·편집보존 가드 → verify: 빌드 + 기존 테스트 무회귀, 편집 세그먼트 미분할 테스트
> Step 3: 임포트 경로 배선 — `MeetingFileImportUseCase` `assignSpeakers` 직후 → verify: 임포트 회의가 문장 단위로 저장
> Step 4: 실코퍼스 AB 측정(5.2, VBx 고정) → verify: 소수 화자 회복·전환 포착 사례 수집, 수동 검수
> Step 5(선택): UI 문장 단위 화자칩 렌더 → verify: 앱 실행, 화자 전환이 문장 경계에서 보임

라이브 경로는 **의도적으로 범위 밖**(4.1). 구현 전 critic 리뷰 1회 완료(이 문서).

---

## 7. 미해결·리스크

- **word 타임스탬프 정밀도가 상한이자 전제** — critic open question: 30초 임포트 청크에서 드리프트가 크면 Splitter가 오히려 화자를 오배정할 수 있다. 따라서 임포트 청크 단축(30→10초)은 "보조 레버"가 아니라 **Splitter가 제대로 작동하기 위한 선행 검증 대상**일 수 있다. Step 1 합성 테스트 통과 후, Step 4 전에 실제 WhisperKit word 드리프트를 짧은 클립으로 먼저 실측한다.
- 문장 경계 휴리스틱(구두점/갭/전환) 파라미터·짧은조각 흡수 기준(한국어 어절 수)은 한국어 회의로 튜닝 필요.
- 5.2 경계 정확도의 객관 지표 부재 → 완료 판정에 인간 검수 게이트가 들어간다(자동화 불가).
