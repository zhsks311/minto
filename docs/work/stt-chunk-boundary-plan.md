# STT chunk boundary improvement plan

작성일: 2026-06-11

## 1. 현 구조

### 결론

현재 checkout의 기본 실시간 녹음 경로에서 60초 hard cap은 기본값이 아니다. 기본값은 Energy VAD이고 첫 강제 청크 5초, 이후 강제 청크 15초다. Silero VAD는 환경값으로만 켜지며, 기본 `mergeMaxSeconds`는 15초다.

다만 "60초급 강제 플러시"가 실제 앱에서 관찰될 수 있는 현재 코드 후보는 있다. `MINTO_VAD_ENGINE=silero`와 `MINTO_VAD_MERGE_MAX_SEC=60` 같은 런타임 환경값이 주입되면 Silero의 `mergeMaxSeconds` hard cap 위치가 60초가 된다. Energy VAD에는 같은 production env override가 없다.

확인된 현재 구조는 다음과 같다.

- Energy VAD: 첫 강제 청크 5초, 이후 강제 청크 15초
- Silero VAD 후보: 기본 `mergeMaxSeconds` 15초, `maxSpeechDuration` 14초, `MINTO_VAD_MERGE_MAX_SEC`로 runtime override 가능
- 파일 가져오기: 고정 30초 chunk
- 벤치마크/문서: 첫 60초 smoke 기록은 있음. 단, `silero-060-gap11` 결과 경로명의 `060`은 Silero threshold `0.60` 표기이지 60초 chunk 표기가 아니다.

사용자가 제시한 65/60/26초와 문장 절단 예시는 문제 사례로 인정한다. 이 문서는 그 실측을 "현재 checkout 기본값"으로 단정하지 않고, 코드 근거가 있는 hard boundary 위치와 60초급 런타임 후보를 분리한다.

**근거 (Evidence):**

- [VADProcessor.swift](../../Sources/Minto/Services/VADProcessor.swift) L8-L18: Energy VAD의 `silenceDurationThreshold=1.5`, `maxChunkDuration=15.0`, `firstChunkMaxDuration=5.0`, `minSpeechDuration=0.5`.
- [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L81-L90: Silero 기본 후보는 `maxSpeechDuration=14.0`, `mergeGapSeconds=1.1`, `mergeMaxSeconds=VADProcessor.maxChunkDuration`.
- [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L112-L124: production Silero 설정은 `MINTO_VAD_MERGE_MAX_SEC`를 읽어 `mergeMaxSeconds`를 override할 수 있다.
- [VoiceActivityDetectorFactory.swift](../../Sources/Minto/Services/VoiceActivityDetectorFactory.swift) L3-L18: `MINTO_VAD_ENGINE=silero`가 아니면 Energy VAD를 사용하고, Silero model bundle이 없으면 Energy VAD로 fallback한다.
- [SpeechEngine.swift](../../Sources/Minto/Models/SpeechEngine.swift) L12-L13, L148-L158: 기본 STT engine은 `whisperAccurate`, 즉 WhisperKit turbo variant다.
- [MeetingFileImportUseCase.swift](../../Sources/Minto/Services/MeetingFileImportUseCase.swift) L145-L155: 파일 import 기본 `chunkSeconds=30`.
- [stt-overall-work-plan.md](../stt-overall-work-plan.md) L392-L399: 60초 smoke 결과와 재현 조건은 문서에 존재한다.
- [stt-overall-work-plan.md](../stt-overall-work-plan.md) L431-L456: `silero-060-gap11` full-duration 결과는 Silero `threshold=0.6`, `merge gap=1.1초` 재현 조건이며 60초 chunk 설정이 아니다.

### 오디오 입력에서 committedSegments까지

실시간 녹음 경로는 아래 순서다.

> `AudioSource.onBuffer` -> `VAD.process(samples:)` -> `onChunk` -> `AsyncStream<AudioChunk>` -> `transcribeFinalChunk` -> `STTService.transcribe` -> engine별 `transcribe` -> `TranscriptionState.advanceWindow` -> `committedSegments` -> 배치 교정 -> 저장 시 `TranscriptNormalizer`

**근거 (Evidence):**

- [MicrophoneSource.swift](../../Sources/Minto/Services/MicrophoneSource.swift) L136-L175: mic tap을 16kHz mono Float32로 변환한 뒤 `onBuffer(samples)`와 `onLevel(level)`을 main queue로 전달한다.
- [SystemAudioSource.swift](../../Sources/Minto/Services/SystemAudioSource.swift) L63-L76, L89-L103: ScreenCaptureKit system audio도 16kHz mono로 설정하고 `onBuffer(samples)`를 호출한다.
- [MixedAudioSource.swift](../../Sources/Minto/Services/MixedAudioSource.swift) L76-L102: mic/system audio child source를 받아 mixer output을 `onBuffer`로 전달한다.
- [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L214-L245: `vadProcessor.onChunk`는 final chunk를 enqueue하고, `audioSource.onBuffer`는 원본 buffer 저장 후 `vadProcessor.process(samples:)`를 호출한다.
- [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L261-L292: stream의 final chunk를 `transcribeFinalChunk`로 전사하고 `state.advanceWindow(newResult:)` 후 `committedSegments`에 반영한다.
- [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L415-L428: final chunk는 한 번 STT하고, empty final repair 조건이 맞을 때만 padded samples로 한 번 더 STT한다.
- [STTService.swift](../../Sources/Minto/Services/STTService.swift) L242-L245: facade는 현재 engine의 `transcribe(pcmSamples:)`로 그대로 위임한다.
- [WhisperKitSTTEngine.swift](../../Sources/Minto/Services/WhisperKitSTTEngine.swift) L47-L73: WhisperKit은 전달받은 chunk samples를 독립 `pipe.transcribe(audioArray:decodeOptions:)` 호출로 처리한다.
- [TranscriptionState.swift](../../Sources/Minto/Models/TranscriptionState.swift) L8-L29: `advanceWindow`는 유사한 마지막 segment만 skip하고 새 segment를 append한다.
- [MeetingRecordFactory.swift](../../Sources/Minto/Services/MeetingRecordFactory.swift) L14-L37: 저장 record를 만들 때 `TranscriptNormalizer.normalize(segments)`를 적용한다.

### Energy VAD의 hard boundary

Energy VAD는 침묵으로 자연 종료되거나, 발화 buffer가 상한에 도달하면 즉시 flush한다. 강제 flush는 현재 `forced: true`로 기록되고 buffer를 비운다.

샘플 손실 관점에서 보면, 현재 코드가 `flushChunk` 시점에 buffer 안의 긴 발화 샘플을 버리지는 않는다. `drainBufferedChunk`가 `samples = buffer`를 `AudioChunk`로 만들고 그 뒤 buffer를 비운다. 다만 강제 flush는 다음 침묵을 기다리지 않으므로 chunk 경계가 음성/문장 중간에 놓일 수 있고, overlap이 없다.

별도 주의점은 `minSpeechSamples`다. 0.5초 미만 buffer는 chunk로 emit하지 않고 버린다. 이것은 60초 hard boundary의 직접 원인은 아니지만, 아주 짧은 경계 잔여 발화가 독립 buffer로 남으면 유실 후보가 된다.

**근거 (Evidence):**

- [VADProcessor.swift](../../Sources/Minto/Services/VADProcessor.swift) L93-L120: 각 input frame을 처리하며 silence가 1.5초 이상이면 `flushChunk(... forced:false)`를 호출한다.
- [VADProcessor.swift](../../Sources/Minto/Services/VADProcessor.swift) L121-L132: non-silent samples를 buffer에 append하고 `buffer.count >= chunkCap`이면 즉시 `flushChunk(... forced:true)`를 호출한다.
- [VADProcessor.swift](../../Sources/Minto/Services/VADProcessor.swift) L167-L195: `drainBufferedChunk`는 현재 buffer 전체를 chunk samples로 만들고 start/end seconds를 계산한 뒤 buffer를 비운다. 단, L168-L171은 `minSpeechSamples` 미만 buffer를 emit하지 않고 초기화한다.

### Silero VAD의 hard boundary

Silero 경로도 active speech가 `mergeMaxSeconds`를 넘으면 `start + mergeMaxSeconds` 지점에서 final chunk를 만들고 `activeStartSample = end`로 다음 chunk를 이어간다. 자연 speech end는 pending range로 보관됐다가 merge gap 이후 emit된다.

샘플 단위로는 `sampleBuffer[startIndex..<endIndex]`를 잘라 chunk를 만들며, overlap은 없다. `MINTO_VAD_MERGE_MAX_SEC=60`이 주입된 실시간 실행이라면 이 위치가 "60초 강제 플러시"의 코드상 위치다.

**근거 (Evidence):**

- [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L270-L298: speech start/end event로 active range와 pending final range를 관리한다.
- [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L300-L308: active speech가 `mergeMaxSeconds` 이상이면 `end = start + mergeMaxSeconds`에서 final chunk를 만들고 다음 active start를 `end`로 바꾼다.
- [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L310-L338: pending final range는 merge gap이 지난 뒤 emit된다.
- [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L350-L370: chunk samples는 `sampleBuffer[startIndex..<endIndex]`로 생성된다.

### 파일 import의 fixed chunk

파일 import는 VAD가 아니라 고정 `chunkSeconds` 크기로 sample array를 자른다. 현재 기본은 30초다. 이 경로도 silence alignment와 overlap이 없다.

**근거 (Evidence):**

- [FileAudioExtractor.swift](../../Sources/Minto/Services/FileAudioExtractor.swift) L81-L120: `chunkSeconds * sampleRate`로 chunk size를 계산하고 extractor가 chunk를 순서대로 emit한다.
- [FileAudioExtractor.swift](../../Sources/Minto/Services/FileAudioExtractor.swift) L336-L363: accumulator가 `chunkSize`만큼 정확히 잘라 `FileAudioChunk`를 만든다.
- [MeetingFileImportUseCase.swift](../../Sources/Minto/Services/MeetingFileImportUseCase.swift) L301-L337: 각 file chunk를 독립 STT하고, 필요하면 이전 5개 context로 교정한 뒤 segment로 append한다.

### 경계 단어 유실 메커니즘

확인된 사실:

- VAD flush 자체가 buffer 안의 샘플을 버리는 코드는 확인되지 않는다.
- hard boundary에는 overlap이 없고, STT는 chunk 단위 독립 호출이다. 이전/다음 chunk audio나 text가 WhisperKit decode input으로 들어가지 않는다.
- WhisperKit 결과는 segment별 avgLogprob/compressionRatio/빈 문자열/bracket prefix 필터를 통과한 text만 이어 붙인다.
- live final 결과가 비면 `TranscriptionViewModel`은 기존 preview를 유지하고 `committedSegments`에는 append하지 않는다.

정확한 메커니즘:

- 1차 메커니즘은 "VAD가 긴 buffer 샘플을 삭제한다"가 아니라 "단어/문장 중간 hard boundary를 overlap 없이 둘로 자른 뒤 각 조각을 독립 STT window로 보내는 것"이다.
- 단어 앞부분은 이전 chunk 끝에, 뒷부분은 다음 chunk 시작에 갈라진다. WhisperKit은 각 window 안의 acoustic context만 보고 decode하므로, 경계 단어가 양쪽 어느 window에서도 안정적으로 token화되지 않을 수 있다.
- 한쪽 chunk가 empty final이 되거나, WhisperKit segment 후필터에서 text가 skip되면 그쪽 조각은 `committedSegments`에 남지 않는다.
- `TranscriptionState.advanceWindow`의 중복 방지는 "비슷한 마지막 segment skip" 수준이라 suffix/prefix를 재조립하지 않는다. 따라서 경계 단어를 되살리는 merge 단계가 없다.

미확인:

- 현재 코드만으로 특정 실측 단어가 WhisperKit decode 실패인지, 후필터 skip인지, `minSpeechSamples` 미만 잔여 발화 drop인지까지는 확정할 수 없다. word timestamp가 꺼져 있어 per-word boundary 원인도 직접 관찰되지 않는다.

**근거 (Evidence):**

- [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L271-L276: final STT text가 비면 `committedSegments`에 append하지 않고 loop를 계속한다.
- [WhisperKitSTTEngine.swift](../../Sources/Minto/Services/WhisperKitSTTEngine.swift) L58-L73: word timestamp 없이 독립 decode options로 chunk를 전사한다.
- [WhisperKitSTTEngine.swift](../../Sources/Minto/Services/WhisperKitSTTEngine.swift) L75-L91: WhisperKit segment 중 low avgLogprob, high compressionRatio, 빈 text, bracket prefix를 skip한다.
- [WhisperKitSTTEngine.swift](../../Sources/Minto/Services/WhisperKitSTTEngine.swift) L101-L106: 결과 segment duration은 전달 samples 길이 기반이며, 이전 chunk text/audio는 입력하지 않는다.
- [TranscriptionState.swift](../../Sources/Minto/Models/TranscriptionState.swift) L8-L17: commit 단계는 마지막 segment와 비슷하면 skip하고 아니면 append할 뿐, boundary suffix/prefix stitching은 하지 않는다.

### 교정 context가 boundary stitching에 충분하지 않은 이유

현재 교정은 "이전 context를 참고해 현재 인식 결과만 교정"하는 구조다. 특히 prompt가 직전 발화 맥락을 출력에 옮기거나 이어붙이지 말라고 금지한다. 따라서 교정 context는 경계 문장을 이해하는 힌트는 될 수 있지만, 이전 segment tail과 현재 segment head를 하나의 문장으로 합치는 기능은 아니다.

또한 live 교정 batch는 30초 누적 기준이다. 사용자가 제시한 60초급 segment라면 segment 하나만으로 `correctionWindowSeconds`를 넘기므로 경계 앞/뒤 chunk가 같은 correction batch에 들어가기 어렵다.

교정 provider가 꺼져 있으면 이 단계 자체가 no-op이다. provider가 켜져 있어도 batch 밖의 이전 context는 `replaceRange` 병합 대상이 아니므로, 경계 앞 segment를 수정하거나 합칠 권한이 없다.

**근거 (Evidence):**

- [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L62-L72: correction window는 30초, context는 직전 5 segment다.
- [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L375-L391: 교정 대상 batch text는 `segmentsToCorrect`만 join하고, context는 batch 이전 text만 넘긴다.
- [LLMCorrectionService.swift](../../Sources/Minto/Services/LLMCorrectionService.swift) L47-L59: `correct(text:context:)`는 `previousText`에 context를 넣어 `CorrectionPrompt`로 전달한다.
- [LLMCorrectionService.swift](../../Sources/Minto/Services/LLMCorrectionService.swift) L63-L64: provider가 `.none`이거나 text가 비면 교정은 수행되지 않는다.
- [CorrectionPrompt.swift](../../Sources/Minto/Services/CorrectionPrompt.swift) L33-L36: 의미/길이 보존, current result에 없는 구절 생성 금지, context를 출력에 이어붙이지 말라는 규칙이 있다.
- [CorrectionPrompt.swift](../../Sources/Minto/Services/CorrectionPrompt.swift) L53-L56: prompt user content는 `직전 발화 맥락`과 `현재 인식 결과`를 분리한다.
- [TranscriptionState.swift](../../Sources/Minto/Models/TranscriptionState.swift) L34-L56: 같은 correction batch의 여러 segment는 `replaceRange`로 하나의 segment가 될 수 있지만, batch 밖 이전 context는 병합 대상이 아니다.

### benchmark와 corpus 하니스

`docs/benchmark/`에는 현재 local LLM benchmark 결과가 주로 저장되어 있고, STT/VAD benchmark 결과는 `docs/stt-overall-work-plan.md`, `docs/stt-meeting-benchmark-runner.md`, 임시 benchmark 산출물 경로 기록으로 남아 있다.

국회 회의 코퍼스 하니스는 존재한다.

주의: 과거 결과 경로의 `silero-060`은 60초가 아니라 threshold 0.60 표기다. 60초 smoke 자체는 `--max-seconds 60`으로 첫 60초만 평가한 기록이다. 향후 60초급 실시간 경계를 재현하려면 현재 앱 실행 환경의 `MINTO_VAD_ENGINE`, `MINTO_VAD_MERGE_MAX_SEC`, 실제 build commit을 먼저 고정해야 한다.

**근거 (Evidence):**

- [README.md](../benchmark/local-llm/README.md) L1-L38: `docs/benchmark`의 현 주요 보관물은 로컬 LLM 후보 실행 결과다.
- [MeetingCorpusTests.swift](../../Tests/MintoTests/MeetingCorpusTests.swift) L5-L20: 국회 영상회의록 sample/meeting 코퍼스로 CER를 측정하는 manual test가 있다.
- [MeetingCorpusTests.swift](../../Tests/MintoTests/MeetingCorpusTests.swift) L43-L56: SMI caption을 window 단위로 병합하고 1.5초 gap을 창 분리 기준으로 둔다.
- [MeetingCorpusTests.swift](../../Tests/MintoTests/MeetingCorpusTests.swift) L57-L245: window별 STT, micro/global CER, empty count, RTF, JSON metrics를 기록한다.
- [VADBenchmarkTests.swift](../../Tests/MintoTests/VADBenchmarkTests.swift) L133-L182: sample/meeting VAD baseline metric을 생성한다.
- [VADBenchmarkTests.swift](../../Tests/MintoTests/VADBenchmarkTests.swift) L184-L424: VAD chunk STT CER, empty final, false-positive text, repair telemetry를 측정한다.
- [scripts/run_meeting_vad_benchmarks.py](../../scripts/run_meeting_vad_benchmarks.py) L30-L78: VAD/STT benchmark runner는 max seconds, merge gap/max, Silero threshold, repair pad knobs를 받는다.
- [scripts/run_meeting_vad_benchmarks.py](../../scripts/run_meeting_vad_benchmarks.py) L165-L211: runner가 Swift test 환경변수로 VAD/STT 설정을 전달한다.
- [scripts/run_meeting_stt_benchmarks.py](../../scripts/run_meeting_stt_benchmarks.py) L34-L48: STT corpus runner는 window seconds, max windows, engine/filter를 설정한다.
- [STTG2Tests.swift](../../Tests/MintoTests/STTG2Tests.swift) L5-L20: AI Hub G2 corpus CER manual test도 존재한다.
- [StreamingChunkBenchmarkTests.swift](../../Tests/MintoTests/StreamingChunkBenchmarkTests.swift) L264-L341: transcript normalizer A/B는 CER와 가독성 지표를 분리한다.
- [stt-meeting-benchmark-runner.md](../stt-meeting-benchmark-runner.md) L231-L243: VAD chunk STT mode의 60초 smoke 실행 예시는 `--max-seconds 60`으로 첫 60초 평가를 지정한다.

## 2. 옵션 비교

| 옵션 | 변경 지점 | 위험 | 예상 효과 | 측정 방법 |
| --- | --- | --- | --- | --- |
| A. 침묵 정렬 분할 | [VADProcessor.swift](../../Sources/Minto/Services/VADProcessor.swift) L121-L132의 즉시 forced flush를 soft cap으로 바꾸고, L115-L120 silence flush를 우선시한다. [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L300-L308의 max duration 즉시 emit을 soft cap + hard cap(+15초 등)으로 나눈다. 60초 실측이 `MINTO_VAD_MERGE_MAX_SEC=60` 때문이면 같은 지점이 변경 대상이다. | final latency가 soft cap 이후 최대 +15초 증가한다. 발화가 끊기지 않는 회의에서는 hard cap에서 결국 자른다. 긴 chunk가 WhisperKit empty/high-CER를 늘릴 수 있다. | 문장 중간 cut rate와 dangling ending이 줄 가능성이 가장 직접적이다. 중복 병합 로직이 필요 없어 B보다 단순하다. | SMI 기준 boundary가 caption interval 내부에 떨어지는 비율, `TranscriptNormalizer.isLikelyIncompleteEnding` 기반 dangling ending rate, chunk duration p50/p95/max, first/final latency, VAD chunk STT full-reference CER, empty final count. |
| B. 오버랩 윈도우 | Energy: [VADProcessor.swift](../../Sources/Minto/Services/VADProcessor.swift) L167-L195에서 drain 후 tail 1~2초를 다음 chunk 앞에 보존하거나 원본 ring buffer에서 chunk start를 앞당긴다. Silero: [SileroVADProcessor.swift](../../Sources/Minto/Services/SileroVADProcessor.swift) L350-L370에서 chunk 생성 시 start를 overlap만큼 앞당긴다. 병합은 [TranscriptionState.swift](../../Sources/Minto/Models/TranscriptionState.swift) L8-L17의 full-segment similarity보다 정교한 suffix/prefix dedupe가 필요하다. | 중복 텍스트, timestamp overlap, 같은 단어 두 번 기록, 요약/검색 index 중복. 한국어 suffix/prefix fuzzy dedupe가 틀리면 문장을 훼손할 수 있다. `minSpeechSamples` 미만 경계 잔여를 살리려면 overlap 범위와 emit 조건을 함께 설계해야 한다. | 침묵을 기다릴 수 없는 장시간 연속 발화에서도 경계 acoustic context를 제공한다. 경계 단어 유실에는 A보다 강할 수 있다. | boundary word retention rate, adjacent duplicate n-gram rate, dedupe edit distance, global CER, false-positive chars, manual boundary QA. |
| C. 경계 stitching 교정 패스 | [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L475-L483 `finalizeMeeting()`에서 최종 요약 전, 또는 [MeetingRecordFactory.swift](../../Sources/Minto/Services/MeetingRecordFactory.swift) L14 이전에 인접 segment tail/head만 대상으로 별도 pass를 둔다. 기존 [CorrectionPrompt.swift](../../Sources/Minto/Services/CorrectionPrompt.swift) L33-L36은 이어붙이기 금지라 새 prompt가 필요하다. | LLM이 없는 내용을 추가할 수 있다. 원문 보존과 수정본을 분리하지 않으면 CER/감사 가능성이 흐려진다. 종료 시간이 늘고 provider 실패/timeout 처리가 필요하다. | STT 재실행 없이 읽기 좋은 회의록을 만들 수 있다. 이미 잘린 문장 경계를 사용자-facing transcript에서 완화한다. | CER와 분리해서 boundary sentence split rate, dangling ending 감소율, paragraph count, LLM insertion length ratio, raw-preservation diff, 수동 QA를 본다. |
| D. targeted boundary repair 확장 | 기존 [EmptyFinalRepairPolicy.swift](../../Sources/Minto/ViewModels/EmptyFinalRepairPolicy.swift) L18-L41, L68-L124와 [TranscriptionViewModel.swift](../../Sources/Minto/ViewModels/TranscriptionViewModel.swift) L415-L428, L463-L470을 활용한다. 현재는 empty final에만 retry한다. 확장 시 incomplete-ending 또는 low-confidence 후보만 원본 buffer에서 앞뒤 padding으로 1회 재전사한다. | false-positive text와 peak memory 증가가 이미 관찰됐다. 현재 STT engine이 boundary confidence를 공개하지 않아 guard가 text heuristic에 의존할 수 있다. | 완전한 재분할보다 좁고 rollback이 쉽다. empty final/경계 단어 유실에 직접 대응한다. | 기존 repair telemetry: repair attempt/accepted, repair false positive, repair dB/duration, empty final, CER, RTF, peak memory. |

## 3. 권장안과 단계

### 1단계: 측정 하니스 먼저 확장

코드 동작 변경 전, 국회 회의 코퍼스/VAD chunk metrics에 boundary 전용 지표를 추가한다.

검증 기준:

- 기존 `VADBenchmarkTests/vadChunkSTTCER` 결과에 boundary cut rate와 adjacent duplicate rate를 추가할 수 있다.
- 60초 실측을 재현하려면 먼저 현재 앱 실행 환경의 `MINTO_VAD_ENGINE`, `MINTO_VAD_MERGE_MAX_SEC`, build commit을 기록한다. 현재 checkout의 기본 live 경로는 15초 hard cap이고, 60초급 후보는 Silero env override 또는 이전 build/config다.
- CER, empty final, false-positive text와 별도로 dangling ending/boundary split 지표를 출력한다.

### 2단계: A를 feature flag로 실험

가장 먼저 제품 기본값이 아니라 benchmark/product hidden flag로 "soft cap 이후 침묵 정렬, hard cap +15초"를 실험한다.

이유:

- 중복 텍스트 병합이 필요 없어 B보다 위험이 낮다.
- LLM provider 유무와 무관해 C보다 재현성이 높다.
- 현재 경계 문제의 근본 원인인 hard boundary를 직접 줄인다.

중단 기준:

- chunk p95/max가 과도하게 늘어 STT empty/high-CER가 증가한다.
- final latency가 사용자가 체감할 정도로 악화된다.
- full-reference CER 또는 empty final이 기준보다 나빠진다.

### 3단계: D는 empty-only 기본 off를 유지하고 guard만 검증

이미 있는 empty final repair는 기본 off를 유지한다. boundary 전체로 확대하기 전, repair false-positive와 peak memory가 줄어드는 guard를 찾는다.

**근거 (Evidence):**

- [EmptyFinalRepairPolicy.swift](../../Sources/Minto/ViewModels/EmptyFinalRepairPolicy.swift) L21-L31: product flag가 켜진 경우에만 retry policy가 활성화된다.
- [stt-meeting-benchmark-runner.md](../stt-meeting-benchmark-runner.md) L409-L432: all7 full-duration에서 repair는 weighted CER/empty를 개선했지만 false-positive text, RTF, peak memory를 증가시켰다.

### 4단계: C는 저장/export용 후처리로 제한

경계 stitching LLM pass는 "STT 정확도 개선"으로 부르지 않고, 저장/export 회의록 가독성 개선으로 제한한다. raw committed segments는 보존하고 stitched transcript는 별도 산출물로 둔다.

### 5단계: B는 A/D 결과 후 보류 판단

오버랩은 효과 가능성이 있지만 dedupe 실패 비용이 크다. A가 경계 cut rate를 충분히 낮추지 못하고, D가 empty/유실만 좁게 해결하지 못할 때 검토한다.

## 4. 측정 계획

### CER 계열

- `micro_cer`, `macro_cer`, `global_cer`, `full_reference_global_cer`를 분리한다.
- VAD 후보 판단에는 emitted chunk 기준 `global_cer`보다 missed speech를 벌점 처리하는 `full_reference_global_cer`를 우선한다.
- LLM correction/stitching의 가독성 개선을 CER 개선으로 보고하지 않는다.

**근거 (Evidence):**

- [MeetingCorpusTests.swift](../../Tests/MintoTests/MeetingCorpusTests.swift) L152-L175: per-window micro CER와 global CER를 분리한다.
- [VADBenchmarkTests.swift](../../Tests/MintoTests/VADBenchmarkTests.swift) L333-L365: VAD chunk STT는 covered global과 full reference global을 별도로 기록한다.
- [stt-overall-work-plan.md](../stt-overall-work-plan.md) L669-L680: STT 기본값 변경 기준은 전체 sample/meeting CER, latency, memory, short utterance, 반복 실행을 요구한다.

### Boundary 전용 지표

추가할 지표:

- `hard_cap_boundary_count`: 침묵 flush가 아니라 hard cap으로 emit된 chunk 수. Energy는 `forced`, Silero는 `mergeMaxSeconds` while branch 기준으로 센다.
- `boundary_inside_caption_rate`: chunk boundary가 SMI caption interval 내부에 떨어지는 비율. 문장/발화 중간 cut의 proxy.
- `boundary_gap_seconds_p50/p95`: 인접 chunk boundary 주변 SMI gap 분포. gap이 짧을수록 hard speech cut 가능성이 높다.
- `dangling_ending_rate`: segment가 조사/연결어/ellipsis 등 불완전 ending으로 끝나는 비율.
- `adjacent_stitch_candidate_count`: 이전 segment tail과 다음 segment head를 함께 봐야 자연스러운 경계 수.
- `boundary_word_retention_proxy`: boundary 전후 reference text가 있는데 hyp 양쪽 중 한쪽이 empty/짧은 경우의 비율.
- `boundary_empty_side_rate`: reference가 있는 경계 앞/뒤 chunk 중 한쪽 STT가 empty인 비율. 경계 유실과 empty final을 연결해 본다.
- `runtime_boundary_config`: `VAD engine`, `merge max`, `speech padding`, `repair pad`, `STT engine/model`, build commit. 실측 60초 재현 여부를 metric 파일 metadata에 남긴다.

**근거 (Evidence):**

- [TranscriptNormalizer.swift](../../Sources/Minto/Services/TranscriptNormalizer.swift) L33-L61: incomplete ending 판정 로직이 이미 있다.
- [StreamingChunkBenchmarkTests.swift](../../Tests/MintoTests/StreamingChunkBenchmarkTests.swift) L317-L340: raw/normalized dangling ending과 CER 동일성 검증 패턴이 있다.
- [VADBenchmarkTests.swift](../../Tests/MintoTests/VADBenchmarkTests.swift) L749-L754: VAD chunk 시간 범위로 SMI reference text를 추출한다.
- [VADBenchmarkTests.swift](../../Tests/MintoTests/VADBenchmarkTests.swift) L373-L393: VAD/STT 설정과 repair telemetry를 metric metadata에 남긴다.

### 유실/중복/환각 지표

- `empty_final_count`: STT가 비어 있는 final 수.
- `false_positive_transcript_chars`: reference가 없는 구간에서 나온 텍스트 글자 수.
- `adjacent_duplicate_ngram_rate`: overlap/dedupe 도입 시 인접 segment 중복률.
- `repair_false_positive_count`: repair가 accepted됐지만 reference 없는 텍스트를 만든 수.
- `llm_insertion_ratio`: stitching/correction 후 raw 대비 글자 수가 20% 이상 증가한 boundary 수.

**근거 (Evidence):**

- [VADBenchmarkTests.swift](../../Tests/MintoTests/VADBenchmarkTests.swift) L225-L331: empty, false positive, repair telemetry를 segment metric으로 모은다.
- [STTBenchmarkMetrics.swift](../../Tests/MintoTests/STTBenchmarkMetrics.swift) L183-L290: segment metric schema에 repair telemetry 필드가 있다.
- [stt-meeting-benchmark-runner.md](../stt-meeting-benchmark-runner.md) L113-L119: segment diagnostics는 VAD overlap과 repair FP를 분리해 보도록 설계되어 있다.

### 성능/UX 지표

- final latency p50/p95
- RTF
- peak memory
- chunk duration p50/p95/max
- preview가 final empty 뒤 사라지지 않는지
- 저장/export transcript가 raw를 잃지 않는지

**근거 (Evidence):**

- [StreamingChunkBenchmarkTests.swift](../../Tests/MintoTests/StreamingChunkBenchmarkTests.swift) L176-L239: streaming benchmark는 latency, RTF, preview/final metrics를 기록한다.
- [TranscriptionViewModelStopTests.swift](../../Tests/MintoTests/TranscriptionViewModelStopTests.swift) L119-L143: empty final이면 preview를 즉시 지우지 않는 테스트가 있다.
- [TranscriptNormalizerTests.swift](../../Tests/MintoTests/TranscriptNormalizerTests.swift) L94-L123: 요약이 없어도 저장/export가 전사를 보존하는 테스트가 있다.

## 5. 롤백 전략

### 문서 변경 롤백

이 커밋은 문서만 변경한다. 문제 발생 시 이 커밋을 revert하면 된다.

### 향후 구현 롤백

- A/B/D는 기본값을 바꾸지 않고 feature flag 또는 benchmark knob로 먼저 둔다.
- feature flag off 상태에서 기존 VAD/STT 결과가 byte-for-byte 또는 metric-equivalent로 유지되는 테스트를 둔다.
- C는 raw transcript를 덮어쓰지 않고 stitched transcript를 별도 산출물로 둔다. provider 실패 시 raw transcript로 fallback한다.
- `false_positive_transcript_chars`, `llm_insertion_ratio`, `peak_memory_mb`, `RTF` 중 하나라도 기준보다 악화되면 default 승격을 중단한다.
- 저장 schema를 바꾸는 구현이 필요해지면 별도 ADR과 migration/rollback 계획을 작성한다.

**근거 (Evidence):**

- [AGENTS.md](../../AGENTS.md) L62-L71: 저장 schema, 실행 모델, privacy 범위, 책임 경계 변경은 ADR 대상이다.
- [stt-empty-repair-implementation-plan.md](../stt-empty-repair-implementation-plan.md) L19-L33: 기존 empty final repair도 feature flag와 guard를 전제로 한다.
