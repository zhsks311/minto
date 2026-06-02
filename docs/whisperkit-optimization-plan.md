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
- 각 tier 전후 동일 명령으로 측정, 표로 누적.

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

### T1 결과: 보류 (naive prompt 주입 실패)

- `promptTokens`에 "쿠팡 개인정보 유출 청문회 경제뉴스. 쿠팡, 로저스, ..."를 넣자 **CER 100.00%** (정확히 1.0 = hypothesis 빈 문자열). prompt가 디코딩을 degenerate하게 만들어 STTService 품질 필터(avgLogprob/compressionRatio/noSpeechProb)가 전 구간을 거른 것으로 추정.
- WhisperKit 코드상 promptTokens 처리·prefill cache 비활성(TextDecoder:355)은 정상 → SDK 버그 아님, **사용 방식 문제**.
- **조치**: production VM 배선 되돌림(prompt 미사용 유지). STTService `promptText` 파라미터 + A/B 테스트는 조사용으로 유지(미커밋).
- **2차 시도(special token 필터 추가, WhisperKit CLI 정석 패턴)도 100% CER** → 필터는 원인 아님. 빈 출력 + `[STT] skip` 로그 없음 = whisper가 prompt 조건에서 0 세그먼트 반환(degenerate).
- **측정 노이즈 발견(중요)**: prompt 없음 CER이 실행마다 9.44% / 19.09% / 16.3%로 출렁 → **단일 샘플(sample/you) 측정은 1~3% 차이를 신뢰할 수 없다.** 이후 모든 일반-품질 판정은 **g2 다수 샘플**로 한다.
- **판정: T1 보류(deferred)**. 2회 실패 + 증거 약함(n≈1) + 측정 노이즈. 코드 3파일 `5c4356e`로 복원(미커밋 폐기). 재개 시 WhisperKit prompt+turbo 모델 상호작용을 별도 심층 조사 필요.

### T2 진행 (다음)

WhisperKit temperature fallback ↔ STTService 사후필터 중복. **구체적 결함 후보 발견**:
- `DecodingOptions(noSpeechThreshold: 0.80)`로 디코딩하는데, 사후필터는 `seg.noSpeechProb < 0.6`로 거름 → **임계 불일치(0.80 vs 0.6)**. noSpeechProb 0.6~0.8 구간 세그먼트를 WhisperKit은 살리는데 앱이 버림(발화 유실 가능).
- compressionRatio(2.4)·avgLogprob(-1.0)도 WhisperKit이 fallback에 쓰는 임계를 앱이 사후 중복 적용 → WhisperKit 최선 결과를 또 버릴 수 있음.
- 측정: **g2**로 필터 정렬/제거 전후 CER + 세그먼트 유지율 비교.
