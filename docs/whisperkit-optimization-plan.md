# WhisperKit 활용 최적화 계획

> 목표: **glossary 없이도** 한국어 회의 전사 기본 품질을 끌어올린다. WhisperKit이 제공하지만
> 현재 안 쓰는 디코딩/품질/타임스탬프 기능을 **하나씩 켜고 sample로 측정**한다.
> 작업은 Codex를 도구로 적극 활용하고, 각 변경은 독립 커밋으로 되돌릴 수 있게 한다.

## 베이스라인 / 되돌림 전략

- **베이스라인 커밋**: `5c4356e` (clean). 각 실험은 독립 커밋. 회귀 시 `git revert`/`git reset`으로 복귀.
- 실험은 **변수 1개씩**. CER 개선/회귀를 기록 후 채택/롤백 결정.

## 측정 프로토콜 (sample 활용)

- **실측 자산**: `sample/you/audio/test.mp4` + `sample/you/script/test.transcription.txt` (ground truth)
- **지표**:
  - 내용 CER — 공백·문장부호 제거, 글자/동음이의어 정확도 (STT 자체 품질)
  - 포맷 CER — 공백·문장부호 포함, 가독성 (교정 효과)
  - 정성 — 전문용어 교정 여부, 과교정 유무
- **명령**:
  - 기본 전사 CER: `RUN_STT_TESTS=1 swift test -c release --filter STTFileTests`
  - raw vs 교정 비교: `RUN_CORRECTION_TEST=1 swift test --filter STTFileTests`
  - 대량(g2): `RUN_STT_TESTS=1 swift test -c release --filter STTG2Tests`
  - **회의(국회 영상회의록)**: `RUN_STT_TESTS=1 swift test -c release --filter MeetingCorpusTests` (env: MEETING_WINDOW_SEC/MEETING_MAX_WINDOWS/MEETING_DEBUG). `sample/meeting/`(gitignore, 비상업·재배포금지)에 16kHz WAV+SMI 자막. **micro-average CER, 상대 A/B 전용**(방송자막 비verbatim이라 절대값 무의미·g2와 비교 금지).
- 각 tier 전후 동일 명령으로 측정, 표로 누적.
- **코퍼스 선택**: 품질 보존형 변경(prompt/suppressBlank/할루시네이션)은 g2(깨끗한 낭독)에선 발동조차 안 함 → **회의 코퍼스로 측정**. g2는 일반 STT 품질 회귀 감시용.

## 후보 기능 (WhisperKit DecodingOptions / API)

| Tier | 기능 | 가설 | 측정 | 비고 |
|------|------|------|------|------|
| **T1** | `promptTokens` (topic+glossary+recentContext 주입) | 도메인 vocabulary를 STT 디코더에 prime → "헌크→청크" 같은 오인식 **발생 자체** 감소 | 내용 CER ↓ | no-glossary 핵심. `transcribe(promptText:)` 추가 필요 |
| **T2** | temperature fallback ↔ 사후필터 중복 점검 | 앱이 avgLogprob/compressionRatio/noSpeechProb로 사후 필터 → WhisperKit 내부 fallback 결과를 또 버릴 수 있음 | 누락 구간 수, CER | 품질 누수 가능. 정렬/제거 |
| **T3** | `wordTimestamps` | 병합 문단 타임스탬프 정밀도 회복 | 정성(타임스탬프 정확도) | 비용↑ 가능 — 측정 |
| **T4** | `windowClipTime`/`suppressBlank`/`supressTokens` | 할루시네이션·빈토큰 억제 | 정성(반복/환각), CER | 기본값 점검 |
| **T5** | 내장 VAD(`EnergyVAD`/`chunkingStrategy:.vad`) / `AudioStreamTranscriber` vs 커스텀 | 중복 제거·정확도 | CER + 지연 | 큰 변경 — 평가만, 별도 결정 |
| **T6** | `task:.translate` / `detectLanguage` / `modelCompute` / 모델 변형 | 향후 기능·속도 | — | 지금 범위 밖 |

## 실행 순서

1. **베이스라인 측정** (현재 코드, sample/you) → 내용/포맷 CER 기록
2. **T1 promptTokens** — Codex로 구현 → 측정 → 채택/롤백 → 커밋
3. **T2 fallback 중복 점검** — Codex로 진단 → 정렬 → 측정 → 커밋
4. T3 → T4 순차, 각 측정·커밋
5. T5는 평가 리포트만(구현은 별도 승인)

## Codex 활용

- 각 tier의 구현/진단 패스를 Codex에 위임, **결과는 CER 하니스로 검증**(Codex 자체 주장 신뢰 금지).
- Codex 출력 → 빌드/테스트 → CER 측정 → 판정은 이 문서에 기록.

## advisor 반영 (판정 기준 강화)

- **단일 샘플 과적합 경계**: sample/you는 n=1(경제뉴스 1클립). 1~3% CER 흔들림은 노이즈일 수 있다.
  - T2/T4(일반 STT 품질) → **g2(3,900쌍)** CER이 움직여야 채택.
  - T1(topic/glossary prompt) → g2엔 회의 맥락이 없어 **증거가 본질적으로 약함(n≈1 판단)**. 우호적 sample/you 숫자에 속지 말 것.
- **하니스 경로 주의**: `STTFileTests`는 30초 청크 독립 전사 + 롤링 prompt 없음(production은 5/15초+롤링). T1은 **동일 청크에 prompt on/off 1변수 A/B**로 측정.
- **prompt 피드백 루프(T1)**: 롤링 `recentCommittedText`는 오류 전파 위험(N의 "헌크"가 N+1을 오염). **topic+glossary 단독 vs +recentContext를 분리 측정**.
- **Codex에 API ground truth 주입**: `promptTokens: [Int]?`, `tokenizer.encode`, `TextDecoder.swift:340`의 `specialTokenBegin` 필터를 그대로 전달(환각 방지).
- sample/you 도메인 = 경제뉴스(쿠팡 청문회). 이 샘플용 topic/glossary = "쿠팡 개인정보 유출 청문회" / 쿠팡·로저스·김범석·고란·글로비스·SKT.

## 진행 기록 (측정값 누적)

| 시점 | 변경 | 내용 CER | 포맷 CER | 판정 |
|------|------|----------|----------|------|
| baseline | (5c4356e) sample/you, 30s청크, prompt無 | **16.3%** | — | 기준점 |
| T1 A/B | prompt 없음 (동일 하니스) | 19.09% | — | A/B 기준 |
| T1 A/B | topic+glossary prompt on | **100.00%** | — | ❌ **깨짐(전 구간 빈 출력)** |
| T2 전 | (5c4356e+T1복원) g2 350샘플, 사후필터 3종 | **6.2%** | — | skip 0회(전 필터) |
| T2 후 | `noSpeechProb<0.6` 제거 | **6.4%** | — | ✅ 채택. Δ0.2%·skip 0회 = WhisperKit 비결정성 노이즈 |
| T4 | `suppressBlank: true` | **6.1%** | — | ✅ 채택. skip 0회, 6.1~6.4% 노이즈 한 구름(S000012가 2.8↔4.7 왕복) |

### T1 결과: 보류 (naive prompt 주입 실패)

- `promptTokens`에 "쿠팡 개인정보 유출 청문회 경제뉴스. 쿠팡, 로저스, ..."를 넣자 **CER 100.00%** (정확히 1.0 = hypothesis 빈 문자열). prompt가 디코딩을 degenerate하게 만들어 STTService 품질 필터(avgLogprob/compressionRatio/noSpeechProb)가 전 구간을 거른 것으로 추정.
- WhisperKit 코드상 promptTokens 처리·prefill cache 비활성(TextDecoder:355)은 정상 → SDK 버그 아님, **사용 방식 문제**.
- **조치**: production VM 배선 되돌림(prompt 미사용 유지). STTService `promptText` 파라미터 + A/B 테스트는 조사용으로 유지(미커밋).
- **2차 시도(special token 필터 추가, WhisperKit CLI 정석 패턴)도 100% CER** → 필터는 원인 아님. 빈 출력 + `[STT] skip` 로그 없음 = whisper가 prompt 조건에서 0 세그먼트 반환(degenerate).
- **측정 노이즈 발견(중요)**: prompt 없음 CER이 실행마다 9.44% / 19.09% / 16.3%로 출렁 → **단일 샘플(sample/you) 측정은 1~3% 차이를 신뢰할 수 없다.** 이후 모든 일반-품질 판정은 **g2 다수 샘플**로 한다.
- **판정: T1 보류(deferred)**. 2회 실패 + 증거 약함(n≈1) + 측정 노이즈. 코드 3파일 `5c4356e`로 복원(미커밋 폐기). 재개 시 WhisperKit prompt+turbo 모델 상호작용을 별도 심층 조사 필요.

### T1 재시도 결과 (회의 코퍼스, 2026-06-03): 차단 확정 → 종료

국회 회의 코퍼스 + micro-average 하니스로 promptTokens를 정밀 재검(STTService `promptText`→`tokenizer.encode(" "+text).filter{<specialTokenBegin}`, WhisperKitCLI 정석):

| 조건 | prompt micro-CER | 비고 |
|------|------|------|
| 59토큰 회의 prompt | **100%(전 창 빈 출력)** | base는 동일 클립 정상(9~17%) |
| 2토큰 prompt("회의") | **100%** | → 길이 무관 |
| prompt + `withoutTimestamps:true` | **100%** | → timestamp 규칙 경로 무관 |

- **확정**: `promptTokens`는 이 스택(WhisperKit + large-v3-**turbo**)에서 길이·timestamp 모드와 **무관하게 빈 출력**. 인코딩 정상(토큰 생성됨)·prepend 정상(소스 확인)·CLI 정석 패턴 → **사용법 오류 아님, 디코딩 레벨 차단**. (비-turbo 모델 미검증이라 "turbo 탓"으로 단정은 보류.)
- **판정: T1 종료**. 도메인 용어는 후처리 **LLM 교정 레이어**(`a29fa2f`, 회의 맥락)에 위임. 단 *인식 불가능하게 뭉개진 고유명사*는 prompt-priming만 살릴 수 있어 후처리가 완전 대체는 아님 — 전문용어 많은 회의에서 재검토 가치(그땐 비-turbo 모델로 차단 우회 시도).
- production 무변경(promptText 배선 되돌림). 차단 재현 절차는 위 표로 보존.

### T4 결과: 채택 (suppressBlank=true), supressTokens·windowClipTime 기본 유지

**SDK ground truth** (LogitsFilter.swift / TextDecoder.swift:1058):
- `suppressBlank`(기본 false→**true**): `SuppressBlankFilter`가 **윈도우 첫 토큰 위치**(`tokens.count==sampleBegin`)에서만 공백·EOT를 `-inf`로 막는다. OpenAI Whisper는 기본 true. 발화 있는 청크의 빈 출력을 줄이며, 첫 위치 한정이라 부작용 최대 토큰 1개. 순수 무음 청크는 에너지 사전필터(-50dB)가 이미 차단 → 위험 낮음.
- `supressTokens`(기본 [] 유지): WhisperKit가 `nonSpeechTokens()` 기본 구현 안 함(TODO). 올바른 토큰 ID 직접 주입은 모델/토크나이저 의존적 → **위험>이득, 의도적 미설정**.
- `windowClipTime`(기본 1.0 유지): 청크 내 seek 동작. VAD로 청크를 직접 끊는 우리 파이프라인엔 영향 적음 → 미변경.

**측정**: g2 350샘플 CER **6.1%**(T2전 6.2 / T2후 6.4 사이, 노이즈 한 구름). `[STT] skip` 0회, suppressBlank도 g2 무발동(깨끗한 발화는 첫 토큰이 공백일 일 없음). **no-regression 확정, 이득은 g2 측정 불가** — 조용한 발화 시작·VAD로 잘린 부분 청크에서만 발현하므로 **라이브 녹음으로만 검증 가능**.

### T3 결과: 보류 (소비자 없음 — 거부 아님, deferred-pending-consumer)

- **거짓 전제 발견**: T3 가설 "병합 문단 타임스탬프 정밀도 회복"은 성립 안 함. `STTService`는 WhisperKit의 `seg.start`/`seg.end`(오디오 상대 초)를 **버리고** `Segment(timestamp: Date(), duration: samples.count/16000)`로 **벽시계**를 쓴다. UI(`formatTimestamp`)·`Report`·`ReportService`·`replaceRange` 병합 모두 이 벽시계 Date를 읽는다 → 회복할 오디오-상대 정밀도가 애초에 없다.
- `wordTimestamps:true`는 디코딩 후 forced-alignment 패스라 **텍스트 무변(CER 0 영향)**, 단어별 타이밍을 줄 뿐인데 **소비자가 없다** → compute 비용만 추가. 컨벤션 "speculative feature 금지" 위반.
- **조치**: 활성화하지 않음. **재개 조건**: 제품 비전 #3(과거 회의 열람/export·오디오 동기 재생)이 들어오면 그때 `seg.start`/`seg.end` 소비자가 생기므로 wordTimestamps 재검토.

### T2 결과: 채택 (noSpeechProb 사후필터 제거)

**SDK ground truth로 확인한 WhisperKit 내부 동작** (두 단계):
1. **Fallback 결정** (`DecodingFallback.init`, Models.swift:377): 재디코딩 트리거용. `noSpeechProb > threshold`면 fallback **안 함**("silence" 수용), compressionRatio/avgLogProb는 fallback 트리거.
2. **세그먼트 skip** (`SegmentSeeker`, line 58-75): 디코딩+fallback 후 최종 drop. `noSpeechProb > 0.80` **AND** `avgLogProb ≤ -1.0`일 때만(확신이 무음을 덮어씀).

→ WhisperKit는 compressionRatio/avgLogProb를 **버리는 데 쓰지 않고** fallback 트리거로만 쓴다. 5회 fallback 후 best-effort 반환.

**측정 기반 결정** (CER 노이즈 회피 위해 `[STT] skip:` 로그 카운트로 판정):
- 세 사후필터(`noSpeechProb<0.6`, `avgLogprob>-1.0`, `compressionRatio<2.4`) **모두 g2 350샘플에서 0회 발동**.
- **`noSpeechProb<0.6` 제거**: WhisperKit가 디코딩 시 0.80+confidence-override로 이미 무음 skip. 사후 0.6 재검은 그 튜닝을 무효화하고 확신 있는 발화(noSpeechProb 0.6~0.8)까지 버림. "0.80으로 정렬"은 confidence-override가 없어 같은 버그의 약한 버전 → **완전 제거**가 유일한 일관 해.
- **`avgLogprob`/`compressionRatio` 유지**: g2 0회 발동 = 깨끗한 발화 안 버림. WhisperKit가 안 거르는 **추가 정책(할루시네이션 억제)** 이므로 의도적 가드로 유지+주석. 잔여 발화손실 위험 명시.
- **CER 6.2%→6.4% = 노이즈**: skip 0회였으므로 제거한 분기는 출력에 무영향(논리적 no-op). Δ0.2%는 WhisperKit ANE 비결정성. **이득은 g2로 측정 불가**(noSpeechProb 0.6~0.8 구간이 깨끗한 낭독엔 없음) → real 회의 음성에서만 발현.
