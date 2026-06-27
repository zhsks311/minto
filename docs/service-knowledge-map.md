# Minto2 서비스 지식 지도 (학습용 아키텍처 맵)

> 이 서비스의 **모든 지식을 습득**하려는 사람을 위한 학습 지도. 각 기능마다 **무슨 알고리즘/개념인가 → 원리 → 우리 코드에서 봐야 할 클래스(file:line)** 순으로 정리한다.
> 작성: 2026-06-21 · 기준 브랜치: main · 코드 인용은 작성 시점 기준(라인은 드리프트 가능, 클래스명으로 찾을 것).
> 함께 볼 문서: `docs/service-definition.md`(기능 정의), `CLAUDE.md`(제약·경계), `docs/adr/`(결정 기록).

## 0. 학습 순서 (권장)

회의 **데이터 흐름 순서**로 읽으면 자연스럽다:

> 오디오 캡처 → VAD(발화 구분) → STT(전사) → 화자분리 → 교정 → 요약 → 저장 → 검색 → 내보내기

가로지르는(cross-cutting) 관심사는 따로 본다: **LLM provider 추상화**(교정·요약·답변이 공유), **용어집**(교정·요약·검색이 공유), **영속·스키마 안전성**.

## 1. 전체 데이터 흐름

```
[오디오 소스] mic / system / mixed
   │ onBuffer([Float])  16kHz mono
   ▼
[VAD] 발화/무음 구분 → 청크 분할
   │ onPreviewChunk(실시간 자막) / onChunk(확정)
   ▼
[STT] WhisperKit → Segment(text, time, duration)
   │ committedSegments
   ▼
[교정] 창 단위 배치 → LLM → 병합 교정 세그먼트
   │ (증분 요약 갱신)
   ▼
[녹음 종료] 잔여 버퍼 drain → 최종 교정 → 최종 요약
   ▼
[화자분리] (파일 임포트/사후) embedding + clustering → 화자 라벨
   ▼
[저장] MeetingRecord(JSON) + 검색 인덱스 사이드카 재빌드
   ├─→ [검색] 토큰 + 임베딩 재랭킹 + LLM 답변(RAG)
   └─→ [내보내기] Markdown / Confluence
```

오케스트레이터: **`TranscriptionViewModel`** (녹음 state machine — `startRecording()` :229, `stopRecordingAndDrain()` :381, `flushCorrectionBatch()` :433). 세션 컨텍스트(주제·용어집·문서·running summary): **`MeetingContext`** (`@MainActor`, in-memory, 비영속).

---

## 2. 오디오 캡처

**개념**: 마이크/시스템오디오/둘을 섞어 **16kHz mono Float32 PCM** 스트림으로 통일해 공급.

**원리**:
- **마이크**: `AVAudioEngine` input 노드에 tap 설치 → `AVAudioConverter`로 네이티브 포맷을 16kHz mono로 **실시간 리샘플링(SRC)**.
- **시스템 오디오**: `ScreenCaptureKit`의 `SCStream`(`capturesAudio=true`)으로 시스템 사운드 수신, `CMSampleBuffer`→Float 변환, 다채널은 평균 다운믹스.
- **믹스**: 두 소스를 프레임 단위 동기화(`min(count)` 소비) 후 gain 0.5 가중합. 채널별 RMS 비교로 **dominant 채널을 화자 힌트**로 기록.

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `AudioSourceProtocol` | `Services/AudioSourceProtocol.swift` | 공통 인터페이스(`onBuffer:`) |
| `AudioSourceFactory` | `Services/AudioSourceFactory.swift` | `AudioInputMode`별 구현체 생성 |
| `MicrophoneSource` | `Services/MicrophoneSource.swift:82,122` | AVAudioEngine 캡처 |
| `SystemAudioSource` | `Services/SystemAudioSource.swift:56,89` | ScreenCaptureKit 캡처 |
| `MixedAudioSource` / `DualAudioBufferMixer` | `Services/MixedAudioSource.swift:102,239` | 믹싱·동기화 |

**알고리즘 키워드**: 샘플레이트 변환(SRC), RMS→dB 레벨, 다운믹스.

---

## 3. VAD (Voice Activity Detection)

**개념**: 무음과 발화를 구분해 **전사할 청크 경계**를 만든다. 무음을 STT에 안 보내 비용·환각을 줄인다.

**원리**:
- **Energy VAD**: 첫 10프레임으로 노이즈 플로어 보정 → `noiseFloor+10dB`를 적응 임계값으로. 1.5초 침묵 누적 시 청크 flush. 1초마다 최근 8초 preview chunk 방출.
- **Silero VAD(기본)**: FluidAudio의 `VadManager`(CoreML로 도는 **Silero v6 LSTM 신경망 모델**)에 정확히 256ms(4096샘플) 프레임을 공급, `speechStart/End` 이벤트로 발화 구간 검출, 1.1초 이내 gap은 병합. 모델 미준비 시 Energy로 fail-soft.

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `VoiceActivityDetector` | `Services/VoiceActivityDetector.swift` | 프로토콜(`process/flushPending/onChunk/onPreviewChunk`) |
| `VoiceActivityDetectorFactory` | `Services/VoiceActivityDetectorFactory.swift` | Silero/Energy 선택, 인스턴스 재사용 |
| `VADProcessor` | `Services/VADProcessor.swift:57,93` | Energy VAD |
| `SileroVADProcessor` / `SileroVADCore` | `Services/SileroVADProcessor.swift:19,252` | Silero 신경망 VAD |
| `SileroVADModelStore` | `Services/SileroVADModelStore.swift` | 모델 다운로드·캐시 |

**알고리즘 키워드**: 에너지 임계값·적응 노이즈 플로어, Silero LSTM VAD, 프레임 누산.

---

## 4. STT (전사) — 핵심

**개념**: 음성을 텍스트로. **WhisperKit**(OpenAI Whisper의 on-device 구현, CoreML).

**원리 — Whisper transformer encoder-decoder**:
- **encoder**가 오디오의 mel-spectrogram을 컨텍스트 벡터로 인코딩.
- **decoder**가 **autoregressive**(한 토큰씩, 앞 토큰을 보고 다음 예측)로 텍스트 토큰 생성.
- **KV 캐시**: decoder가 매 토큰마다 과거 토큰의 Key/Value 벡터를 재사용(재계산 회피). **prefill**(`[SOT, ko, transcribe, timestamp]` 4토큰)은 매번 동일해 룩업 테이블로 즉시 채움. → STT 바이어싱(`promptTokens`)을 켜면 이 prefill 캐시가 비활성(자리 어긋남)되나 비용은 미미(상세: `docs/work/2026-06-19-document-static-extraction-design.md`).
- **환각 필터**: `avgLogprob>-1.0`, `compressionRatio<2.4`, `noSpeechThreshold 0.80`, 에너지<-50dB 생략.
- **preview vs final**: preview는 cancel-and-replace로 실시간 자막, final은 확정 세그먼트. 빈 final은 ±1초 패딩으로 재전사(empty-final repair).

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `SpeechTranscriptionEngine` | `Services/SpeechTranscriptionEngine.swift` | 엔진 프로토콜 |
| `WhisperKitSTTEngine` | `Services/WhisperKitSTTEngine.swift:47` | WhisperKit 래퍼, `DecodingOptions` 구성 |
| `STTService` | `Services/STTService.swift:242` | 엔진 선택·로드 파사드, 모델 복구 |
| `STTAudioUtilities` | `Services/STTAudioUtilities.swift:9,32` | 패딩·dB·정규화 |
| `TranscriptionViewModel` / `TranscriptionState` | `ViewModels/TranscriptionViewModel.swift:229,381,433` | 녹음 state machine, advanceWindow/replaceRange |

**Whisper 내부 더 깊이**: `WhisperKit` 의존성 소스 `Sources/WhisperKit/Core/TextDecoder.swift`(KV 캐시·prefill·promptTokens), `Configurations.swift`(`DecodingOptions`).

**알고리즘 키워드**: transformer, attention(Q/K/V), KV 캐시, autoregressive decoding, mel-spectrogram, beam/greedy, logprob·compression ratio 환각 휴리스틱.

---

## 5. 화자분리 (Diarization) + 보이스프린트

**개념**: "누가 언제 말했나"를 구분(diarization)하고, 등록된 목소리(voiceprint)와 매칭해 **실명**을 붙인다.

**원리**:
- **diarization**: FluidAudio가 **256차원 speaker embedding** 추출 → **agglomerative clustering**(가까운 것끼리 묶기, threshold 기반)으로 화자 그룹화.
- **라벨 번호**: 삽입 순서가 아니라 **가장 이른 발화 시각** 기준 → 재현성(같은 입력=같은 "화자 N").
- **전사↔화자 매칭**: 전사 세그먼트와 화자 구간의 **시간 겹침(overlap)** 최대인 화자 선택, 50% 미만이면 미할당.
- **voiceprint 매칭**: 클러스터 centroid(임베딩 평균, L2 정규화)와 등록 voiceprint 간 **cosine similarity** → threshold(0.65) 이상 중 최고를 그리디 1:1 할당.

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `SpeakerDiarizationProvider` | `Services/SpeakerDiarizationProvider.swift:18` | 프로토콜 |
| `FluidAudioOfflineDiarizationProvider` | `Services/SpeakerDiarizationProvider.swift:53,81` | FluidAudio 구현(embedding+clustering) |
| `DiarizationSpeakerLabeling` | `Services/DiarizationSpeakerLabeling.swift:8` | speakerId→"화자 N"(재현성) |
| `TranscriptSpeakerMatcher` | `Services/TranscriptSpeakerMatcher.swift:13` | overlap 기반 라벨 할당 |
| `VoiceprintMatching` | `Services/VoiceprintMatching.swift:27,88` | centroid·cosine 실명 매핑 |
| `SpeakerLabelEditing` | `UI/SpeakerLabelFormatting.swift:40,102` | 라벨 편집(이름변경·재할당·병합) |

진입 흐름(임포트): `MeetingFileImportUseCase.assignSpeakersIfNeeded()` :368.

**알고리즘 키워드**: speaker embedding, agglomerative clustering, cosine similarity, centroid, 그리디 매칭.

---

## 6. 교정 (Correction)

**개념**: STT 오인식을 LLM으로 고친다(띄어쓰기·고유명사·동음이의어). 내용은 추가/삭제 안 함(길이·의미 보존).

**원리**: `CorrectionPrompt`가 **고정 정책(instructions) + 참고데이터(userContent: 주제·용어집·이전맥락·요약·문서)**를 분리 조립(인젝션 방어). 창 단위 **배치 교정**(번호 목록 전송·파싱, 불일치 시 nil→원문 유지, fail-soft). 교정 전후 diff에서 **용어집 별칭 후보 자동 추출**.

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `LLMCorrectionService` | `Services/LLMCorrectionService.swift:85,136` | 교정 진입점(단건/배치), provider 선택 |
| `CorrectionPrompt` | `Services/CorrectionPrompt.swift:20` | 단건 프롬프트 빌더 |
| `BatchCorrectionPrompt` | `Services/BatchCorrectionPrompt.swift:22,76` | 배치 빌더 + 응답 파서 |
| `CorrectionOutputPostprocessor` | `Services/CorrectionOutputPostprocessor.swift:13` | LLM 마커·따옴표 제거 |
| `CorrectionAliasExtractor` | `Services/CorrectionAliasExtractor.swift:7` | diff→용어집 별칭 후보(LCS 앵커) |

**알고리즘 키워드**: 프롬프트 엔지니어링(policy vs data), LCS diff, 배치 처리, fail-soft.

---

## 7. 요약 (Summary) + 재요약

**개념**: 회의를 **구조화 요약**(리드 Q&A·섹션·결정·할일·미해결질문·키워드 JSON)으로. **전사 기반만**(없는 사실 날조 금지).

**원리**: 증분 요약(녹음 중 running summary 갱신) + 최종 요약(JSON 파싱 → 실패 시 평문 폴백 → 최후 running summary). 재요약은 평문 폴백 회의를 구조화로 재시도(성공 시만 저장).

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `SummaryService` | `Services/SummaryService.swift:44,81,106` | 증분/최종 요약, JSON 파싱·폴백 |
| `SummaryPrompt` | `Services/SummaryPrompt.swift:35,64` | 증분·최종 프롬프트(JSON 스키마, time 날조 방지) |
| `MeetingSummaryRetryUseCase` | `Services/MeetingSummaryRetryUseCase.swift:92` | 재요약 |
| `MeetingRecordFactory` | `Services/MeetingRecordFactory.swift:5` | 요약+전사→MeetingRecord 조립 |
| `MeetingSummary` (모델) | `Models/MeetingSummary.swift` | 구조화 요약 모델, `.plain()` 폴백, `markdown()` |

**알고리즘 키워드**: structured output(JSON) 파싱, grounding(전사 기반), 폴백 체인, 증분 누적.

---

## 8. LLM Provider 추상화 (cross-cutting)

**개념**: 교정·요약·답변·임베딩이 공유하는 **provider 교체 레이어**(로컬/외부 API/레거시 OAuth). useCase별 라우팅·폴백·timeout.

**원리**: `LLMUseCase`(correction/incrementalSummary/finalSummary/answer)로 분기. 레지스트리가 local→legacy→APIKey 순으로 인스턴스 선택. 요약 provider는 override 없으면 교정 provider를 Combine으로 추종.

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `LLMTextGenerationProvider` | `Services/LLMProvider.swift:318` | provider 프로토콜 |
| `LocalLLMProvider` | `Services/LocalLLMProvider.swift:279,453` | Ollama/OpenAI호환 + 임베딩 |
| `LLMAPIKeyTextProvider` | `Services/LLMAPIKeyTextProvider.swift:86` | OpenAI/Gemini/Claude/OpenRouter |
| `LegacyAccountLLMTextProvider` | `Services/LegacyAccountLLMTextProvider.swift:41` | Codex/Gemini/Copilot OAuth |
| `LLMProviderRegistry` | `Services/LLMProviderRegistry.swift:42` | id→인스턴스 팩토리 |
| `LLMSummarySettingsService` | `Services/LLMSummarySettingsService.swift:153` | 요약 provider(override/follow) |

**알고리즘 키워드**: adapter 패턴, capability 라우팅, 폴백, Combine 구독.

---

## 9. 용어집 (Glossary) (cross-cutting)

**개념**: 전문용어·고유명사의 정확 표기를 **교정·요약·검색**에 활용. 전역 + 회의별. 후보는 자동등록 않고 **사용자 제안**.

**원리**: 회의 keywords에서 후보 추출(2자+·중복 제거, 상한 20) → 사용자 승인 시 entry. 관련 용어는 query 포함 관계로 점수화해 **상위 N개만 선별**(전체를 LLM에 안 넣음). 검색어 확장은 entry의 canonical↔aliases로 동의어 토큰 추가. LLM으로 오인식 별칭 프리필.

**봐야 할 클래스**:

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `GlossaryEntry`/`GlossaryCandidate`/`GlossaryAliasSuggestion` | `Models/GlossaryEntry.swift:4` | 데이터 모델 3종 |
| `GlossaryStore` | `Services/GlossaryStore.swift:113,237,446` | 영속·후보추출·관련선별 |
| `GlossaryContextResolver` | `Services/GlossaryStore.swift:665,674` | 프롬프트용 용어 텍스트(최대 1200자) |
| `GlossaryQueryExpander` | `Services/GlossaryQueryExpander.swift:19` | 검색어 동의어 확장 |
| `GlossaryAliasPrefillService` | `Services/GlossaryAliasPrefillService.swift:16` | LLM 별칭 프리필 |

**알고리즘 키워드**: 후보 추출 휴리스틱, 포함-기반 relevance 랭킹, 동의어 확장.

---

## 10. 검색 (Search)

세 층: **토큰 검색** → **임베딩 재랭킹** → **LLM 답변(RAG)**.

### 10-1. 토큰 검색
**원리**: record를 **chunk**(title/topic/summary/section/decision/action/question/transcript/keywords/document)로 분해, 각 Kind에 정적 `rankWeight`. 토큰화는 folding(대소문자·발음구별·전각 무시). 점수 = exactPhrase(20) + termCount×6 + coverage×10 + 확장토큰 + rankWeight. chunk ID는 **FNV-1a 해시**로 content-addressed. document는 문단 분할 + 800자 상한(chunkingVersion=3).

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `MeetingSearchChunk.Kind` | `Services/MeetingSearchIndex.swift:4,31` | chunk 종류·rankWeight |
| `MeetingSearchIndex` | `Services/MeetingSearchIndex.swift:116,160,219` | chunk 분해·토큰 검색 |
| `MeetingSearchIndexStore` | `Services/MeetingSearchIndexStore.swift:41,53,67` | 사이드카 영속·버전 호환 |

### 10-2. 임베딩 재랭킹
**원리**: `LocalHashEmbeddingProvider`가 외부 모델 없이 **FNV-1a 해시 → random-projection 모사 → L2 정규화**로 128차원 lexical-hash 벡터 생성(의미 아닌 어휘 겹침 근사). **cosine similarity**로 재랭킹: `mixedScore = 0.75×토큰점수 + 0.25×cosine`.

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `LocalHashEmbeddingProvider` | `Services/LocalHashEmbeddingProvider.swift:41,51` | 로컬 해시 임베딩 |
| `MeetingSearchEmbeddingIndex` | `Services/MeetingSearchEmbeddingIndex.swift:72,99` | cosine·혼합 재랭킹 |
| `MeetingSearchEmbeddingBuilder` | `Services/MeetingSearchEmbeddingIndex.swift:130` | 임베딩 배치 빌드(actor) |

### 10-3. LLM 답변 (RAG)
**원리**: 토큰검색 → 재랭킹 → **인용 후보 선별**(metadataKinds 제외, 회의당 최대 3) → 근거 블록 조립 → `AnswerPrompt` → LLM → `[1]` 스타일 인용 포함 답변. 재랭킹 5초 타임아웃 fail-soft.

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `MeetingSearchAnswerUseCase` | `Services/MeetingSearchAnswerService.swift:88,173,249` | RAG 오케스트레이터 |
| `AnswerPrompt` | `Services/AnswerPrompt.swift:12` | RAG 프롬프트(인젝션 방어·인용 지시) |

**알고리즘 키워드**: 역색인 유사 토큰 스코어링, TF 유사 가중, FNV-1a 해시, random projection, cosine similarity, 하이브리드 재랭킹, RAG(검색증강생성), 인용(citation).

---

## 11. 저장 (Persistence)

**개념**: 회의를 `{id}.json`으로 영속. **하위호환·손상 격리**가 핵심.

**원리**: `MeetingRecord`의 tolerant `init(from:)` — `id/title/startedAt`만 strict, 나머지 `decodeIfPresent`(구 스키마 nil 로드). 키가 있는데 손상이면 throw → **조용한 기본값 덮어쓰기 대신 quarantine**. additive optional 필드는 schemaVersion 안 올림. 저장은 `.atomic`, 빈 회의는 skip, 저장/삭제마다 검색 인덱스 재빌드. 저장 실패 시 `.md`+`.json` 복구 파일.

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `MeetingRecord` | `Models/MeetingRecord.swift:89` | 회의 모델, tolerant 디코딩 |
| `MeetingStore` | `Services/MeetingStore.swift:53,76,115` | 저장·삭제·quarantine·인덱스 재빌드 |
| `MeetingSaveRecovery` | `Services/MeetingSaveRecovery.swift:16,67` | 저장 실패 복구 |
| `Meeting`/`Segment` | `Models/Meeting.swift` | 전사 세그먼트 모델 |

**알고리즘 키워드**: 스키마 진화(tolerant decode), 격리(quarantine), 원자적 쓰기, content-addressed 사이드카 버저닝.

---

## 12. 내보내기 (Export) + 외부 연동

**개념**: 회의록을 Markdown(기본 fallback) / Confluence로. 녹음 중엔 실시간 `.md` 리포트.

**원리**: `MeetingExporter`가 `MeetingResult`를 표준 MD로 조립(제목→메타→요약→회의자료→전사, 제어문자 이스케이프). Confluence는 Basic Auth + REST(검색 v1 CQL / 생성 v2), MD→Storage HTML 변환, CQL 인젝션 방어. `ReportService`는 serial 큐로 전사 실시간 append.

| 클래스 | 파일:line | 역할 |
|---|---|---|
| `MeetingExporter` | `Services/MeetingExporter.swift:11,57` | Markdown 조립·저장 |
| `MeetingResult` | `UI/MeetingSummaryView.swift:42` | export 입력 모델(record→Result 변환점 :371) |
| `ConfluenceService` | `Services/ConfluenceService.swift:350,376,634` | Confluence REST·MD→HTML |
| `ReportService` | `Services/ReportService.swift:30,89,113` | 실시간 전사 리포트 |

**알고리즘 키워드**: Markdown 직렬화·이스케이프, CQL 인젝션 방어, serial queue I/O.

---

## 13. 첨부 문서 (현재 + 설계중)

**현재**: 회의 자료(`MeetingContext.document` → `record.document`)는 교정·요약 프롬프트에 **raw prefix**(교정 1500/증분 2500/최종 4000자)로 주입. 검색엔 document chunk로 색인. **STT엔 미반영.**

**설계중(미구현)**: 문서에서 **용어+맥락을 정적 추출해 전사·교정·요약·재요약에 직접 주입** — `docs/work/2026-06-19-document-static-extraction-design.md` 참조(직접 주입 구조·선별+상한·STT 바이어싱 측정 게이트).

---

## 14. 부록 — 알고리즘/개념 용어집

- **mel-spectrogram**: 오디오를 사람 청각 척도(mel)의 주파수×시간 2D 표현으로 변환한 것. Whisper encoder 입력.
- **transformer / attention (Q·K·V)**: 토큰들이 서로를 "참고"해 표현을 만드는 신경망. Query로 Key를 뒤져 Value를 가중합.
- **autoregressive decoding**: 앞 토큰을 보고 다음 토큰을 하나씩 생성.
- **KV 캐시**: 과거 토큰의 Key/Value를 저장해 재계산 회피. prefill(고정 시작 토큰)은 룩업으로 채움.
- **VAD**: 발화/무음 판별. Energy(에너지 임계) vs Silero(LSTM 신경망).
- **speaker embedding**: 목소리를 고차원 벡터로. 가까우면 같은 화자.
- **agglomerative clustering**: 가까운 것끼리 점점 묶어 그룹 형성(threshold로 멈춤).
- **cosine similarity**: 두 벡터의 방향 유사도(`dot/(|a||b|)`). 화자·검색 유사도에 사용.
- **centroid**: 한 클러스터 벡터들의 평균(대표점).
- **FNV-1a 해시**: 빠른 비암호 해시. chunk ID·해시 임베딩 버킷에 사용.
- **random projection**: 고차원을 무작위 방향으로 저차원에 투영해 거리 근사 보존.
- **lexical-hash 임베딩**: 의미가 아닌 **어휘 겹침**을 근사하는 로컬 임베딩(외부 모델 불필요).
- **RAG (검색증강생성)**: 검색으로 근거를 모아 LLM 답변에 넣고, 출처를 인용.
- **grounding**: 생성이 입력(전사)에 근거하도록 제약(날조 방지).
- **tolerant decoding**: 누락 필드는 기본값, 손상 필드는 throw→격리.
- **fail-soft**: 실패해도 핵심(전사·저장)을 망치지 않고 부드럽게 후퇴.
- **프롬프트 인젝션 방어**: 사용자 데이터를 정책(instructions)이 아닌 데이터(userContent)에 둬 규칙 변경을 막음.

## 15. 핵심 진입점 빠른 색인

| 알고싶은 것 | 시작 파일 |
|---|---|
| 녹음이 어떻게 도나 | `ViewModels/TranscriptionViewModel.swift` |
| 세션 컨텍스트(주제/용어집/문서) | `Services/MeetingContext.swift` |
| 전사 엔진 | `Services/WhisperKitSTTEngine.swift` / `STTService.swift` |
| 화자 누가 정하나 | `Services/TranscriptSpeakerMatcher.swift` / `VoiceprintMatching.swift` |
| 교정/요약 프롬프트 | `Services/CorrectionPrompt.swift` / `SummaryPrompt.swift` |
| LLM provider 고르는 곳 | `Services/LLMProviderRegistry.swift` |
| 검색 점수 | `Services/MeetingSearchIndex.swift` |
| 저장 스키마·안전성 | `Models/MeetingRecord.swift` / `Services/MeetingStore.swift` |
| 내보내기 | `Services/MeetingExporter.swift` / `ConfluenceService.swift` |
