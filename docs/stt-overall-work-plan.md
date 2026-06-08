# STT 전체 작업 계획

작성일: 2026-06-08

## 목적

Minto를 비싼 회의록 앱의 무료/로컬 우선 대안으로 만든다. 핵심은 STT 엔진, 실시간 표시, 회의록 후처리를 섞지 않고 각각 숫자로 검증하는 것이다.

- 한국어 회의 전사의 CER를 낮춘다.
- 녹음 중에는 빠르게 반응하고, 녹음 종료 시에는 마지막 발화가 사라지지 않게 한다.
- 모델별 CER, RTF, latency, peak memory를 같은 기준으로 비교한다.
- 회의록 정리는 개인 OAuth LLM 또는 로컬 LLM을 선택하게 하되, STT 정확도 평가와 분리한다.
- 기본값 변경은 느낌이 아니라 `sample/meeting` 전체 결과로 결정한다.

## 현재 확정된 상태

현재 브랜치는 구조 개선을 시작할 수 있는 상태다. 대수술보다 측정 가능한 개선을 작은 단위로 쌓는 쪽이 맞다.

- `STTService`는 앱이 보는 facade 역할을 한다.
- `SpeechTranscriptionEngine`이 있고, WhisperKit, SpeechAnalyzer, SFSpeech 구현이 분리되어 있다.
- 현재 기본 fallback은 `openai_whisper-large-v3-v20240930_turbo` 기반 WhisperKit turbo다.
- `VoiceActivityDetector` 경계와 `VADProcessor.flushPending()`이 있다.
- `stopRecordingAndDrain()`은 VAD 잔여 청크를 final 전사까지 drain하도록 테스트가 고정되어 있다.
- final STT가 empty일 때 기존 preview를 즉시 지우지 않는 테스트가 있다.
- `TranscriptNormalizer`가 저장/export 경로에 붙어 있고, 원문 chunk를 그대로 회의록 줄로 저장하는 문제를 줄인다.
- VAD/STT benchmark는 per-chunk CER뿐 아니라 global CER와 aggregate RTF를 봐야 한다.

## 2026-06-08 측정 업데이트

`sample/meeting` 전체 7개 샘플을 같은 조건으로 짧게 자른 120초 기준선을 먼저 만들었다. 전체 회의 실행 전 리소스와 runner 경로를 검증하기 위한 중간 기준선이다.

- 실행 범위: `sample/meeting/raw` 7샘플, `MEETING_MAX_WINDOWS=6`, 20초 window.
- 실행 엔진: `whisper_accurate` / `openai_whisper-large-v3-v20240930_turbo`.
- 결과 위치: `/private/tmp/minto2-bench-whisper-120s`.
- 결과: 7/7 성공, weighted CER 49.1%, macro CER 50.1%, mean global CER 43.7%, RTF 0.144, peak memory 710.688MB, empty final 6, false-positive chars 0.
- 해석: 초반 120초 window는 자막 비verbatim, 의사진행 발화, 짧은 창, 빈 출력 영향이 커서 절대 품질 결론으로 쓰면 안 된다. 같은 조건의 엔진 간 A/B 비교 기준선으로만 사용한다.

추가로 가장 짧은 샘플 `본회의_20260428`을 full-duration으로 돌려 전체 실행 리스크를 확인했다.

- 실행 범위: `본회의_20260428`, 51/51 window, `MEETING_MAX_WINDOWS=0`.
- 결과 위치: `/private/tmp/minto2-bench-whisper-full-smoke`.
- 결과: 1/1 성공, weighted CER 50.9%, macro CER 50.9%, computed global CER 48.1%, RTF 0.129, peak memory 196.016MB, empty final 14, false-positive chars 0.
- 해석: 같은 샘플의 120초 결과와 micro CER는 거의 같지만, full run에서는 empty final이 1개에서 14개로 늘었다. 다음 개선 축은 모델 교체만이 아니라 empty final 원인 분해와 segmentation/VAD 비교도 포함해야 한다.
- `scripts/summarize_stt_benchmarks.py --write-segments`로 empty final과 high-CER window를 `segments.md` / `segments.csv`로 뽑을 수 있다. `본회의_20260428` full smoke에서는 긴 참조문을 통째로 빈 출력한 구간이 상위 진단 목록에 반복적으로 잡혔다.
- segment 진단은 duration, reference chars/sec, hypothesis chars/sec를 함께 보여준다. ref density가 높은 empty row는 단순 무음보다 subtitle boundary, window density, chunking 정책 문제 후보로 본다.

short3 full-duration final-only 기준선도 같은 WhisperKit turbo로 확인했다.

- 실행 범위: `본회의_20260428`, `본회의_20260508`, `재정경제기획위원회_20260430`, `MEETING_MAX_WINDOWS=0`, 20초 window.
- 결과 위치: `/private/tmp/minto2-meeting-full-whisper-final-short3-unsandboxed`.
- 결과: 3/3 성공, weighted CER 56.5%, macro CER 52.9%, mean global CER 48.4%, RTF 0.135, peak memory 300.0MB, empty final 75, false-positive chars 0.
- 샘플별 global CER: `본회의_20260428` 45.5%, `본회의_20260508` 41.0%, `재정경제기획위원회_20260430` 58.7%.
- 샘플별 empty final: `본회의_20260428` 12개, `본회의_20260508` 22개, `재정경제기획위원회_20260430` 41개.
- 해석: 같은 short3에서 Silero VAD chunk STT는 repair 없이 weighted CER 37.9%, global CER 28.8%, empty 42개였고, empty-only repair는 weighted CER 30.7%, global CER 22.4%, empty 9개였다. 따라서 현재 구조에서 단순 20초 final-only window는 기준선으로만 남기고, 제품 품질 개선은 VAD/segmentation과 empty repair 쪽을 우선한다.
- 실행 주의: 샌드박스 안에서는 CoreML/E5RT가 `~/Library/Caches/swiftpm-testing-helper`에 cache bundle을 만들지 못해 `.pixelBufferFailed`가 발생했다. full-duration WhisperKit benchmark는 해당 cache 쓰기가 가능한 환경에서 실행해야 한다.

long4 full-duration final-only 기준선도 같은 조건으로 확인했다.

- 실행 범위: `재정경제기획위원회_20260429`, `haengan_20260526`, `외교통일위원회_20260520`, `본회의_20260423`, `MEETING_MAX_WINDOWS=0`, 20초 window.
- 결과 위치: `/private/tmp/minto2-meeting-full-whisper-final-long4-unsandboxed`.
- 결과: 4/4 성공, weighted CER 56.6%, macro CER 56.4%, RTF 0.137, peak memory 719.5MB, empty final 531, false-positive chars 0.
- 샘플별 CER/empty: `재정경제기획위원회_20260429` 55.5%/109개, `haengan_20260526` 51.4%/101개, `외교통일위원회_20260520` 55.0%/106개, `본회의_20260423` 63.8%/215개.
- 주의: long4는 Swift global CER를 skip했다. long4 실행 자체는 약 56.9분이 걸렸고, 4개 run 모두 return code 0으로 끝났다.
- 해석: 긴 회의에서는 20초 final-only window의 empty final이 크게 누적된다. false-positive text가 0이라는 점은 장점이지만, 회의록 품질 관점에서는 "없는 말을 추가하지 않는 대신 긴 참조 구간을 통째로 놓치는" 형태다.

short3와 long4를 합친 all7 final-only 기준선도 같은 summarizer schema로 고정했다.

- 집계 방식: short3와 long4의 7개 `*_metrics.json`을 `/private/tmp/minto2-meeting-full-whisper-final-all7-from-short3-long4` 아래로 모아 `scripts/summarize_stt_benchmarks.py --write --write-segments --segment-min-cer 0.8`로 다시 계산했다.
- 결과: 7/7 성공, weighted CER 56.6%, macro CER 54.9%, RTF 0.137, peak memory 719.5MB, empty final 606, false-positive chars 0.
- Global CER 주의: all7 summary의 48.4%는 global CER가 있는 short3만의 평균이다. long4는 full-duration global Levenshtein 비용 때문에 skip했으므로 all7 판단에는 weighted CER, macro CER, empty final, false-positive chars, RTF, peak memory를 우선한다.
- 비교 기준: 같은 all7에서 Silero VAD chunk STT는 repair 없이 weighted CER 46.1%, empty 329, false-positive text 508 chars였고, empty-only repair는 weighted CER 42.6%, empty 133, false-positive text 628 chars였다.
- 해석: final-only 20초 window는 이제 전체 7샘플 기준선으로 충분하다. 다음 개선의 주된 방향은 final-only window 유지가 아니라 VAD/segmentation, targeted empty repair, true streaming 후보의 partial/final 구조 비교다.

같은 샘플에 Energy VAD baseline도 돌려 VAD와 STT 실패 구간을 겹쳐 볼 수 있게 했다.

- 실행 범위: `본회의_20260428`, `VAD_MAX_SECONDS=720`, `VAD_ENGINE=energy`.
- 결과 위치: `/private/tmp/minto2-vad-full-smoke`.
- 결과: chunk 40개, speech recall 62.2%, missed speech 175.8초, false-positive 104.2초, short recall 37/61.
- `scripts/summarize_stt_benchmarks.py --vad-root /private/tmp/minto2-vad-full-smoke --write-segments`로 STT 실패 window와 VAD overlap을 함께 볼 수 있다.
- 해석: low VAD overlap empty row는 segmentation miss 후보이고, high VAD overlap empty row는 WhisperKit decode/model failure 후보로 분리한다.

7개 샘플 120초 기준선에도 Energy VAD를 겹쳐 확인했다.

- 실행 범위: `sample/meeting/raw` 7샘플, `VAD_MAX_SECONDS=120`, `VAD_ENGINE=energy`.
- 결과 위치: `/private/tmp/minto2-vad-120s-energy`.
- VAD 결과: 7/7 성공, chunk 55개, speech recall 65.0%, short recall 62.7%, missed speech 162.2초, false-positive 204.2초, false-positive ratio 40.4%.
- STT 결과 위치: `/private/tmp/minto2-bench-whisper-120s`.
- STT/VAD bucket 결과: empty final 6개는 high VAD overlap 2개, mid VAD overlap 2개, low VAD overlap 2개로 나뉘었다. high-CER non-empty 3개는 high VAD overlap 2개, low VAD overlap 1개였다.
- 해석: 120초 기준 실패는 VAD miss만으로 설명되지 않는다. VAD/segmentation 개선과 WhisperKit decode failure 진단을 병렬로 봐야 한다. Energy VAD의 recall 자체도 낮으므로 Silero 또는 merge 정책은 검증 가치가 있지만, false-positive text와 global CER를 같이 봐야 한다.

Energy VAD merge 정책도 같은 7개 120초 기준선에서 확인했다.

- `merge gap=1.1초`, `merge max=15초`: baseline과 동일했다. chunk 55개, speech recall 65.0%, short recall 62.7%, false-positive 204.2초.
- `merge gap=1.1초`, `merge max=30초`: chunk는 54개로 1개 줄었지만 speech recall 65.0%, short recall 62.7%로 동일했고, false-positive는 205.3초로 늘었다.
- 해석: 현재 누락은 단순히 가까운 chunk를 이어 붙여 해결되는 문제가 아니다. 15초 chunk 상한을 유지한 merge gap 조정은 우선순위가 낮고, 다음 VAD 실험은 Energy threshold 계열 또는 Silero VAD처럼 speech/non-speech 판정 자체가 달라지는 후보를 봐야 한다.

Energy threshold와 Silero VAD도 같은 7개 120초 기준선에서 확인했다.

- Energy `noise offset=6dB`: chunk 55개, speech recall 72.8%, short recall 73.1%, missed speech 126.2초, false-positive 217.2초, false-positive ratio 39.1%.
- Silero default `threshold=0.5`: chunk 93개, speech recall 91.3%, short recall 97.0%, missed speech 40.2초, false-positive 219.8초, false-positive ratio 34.2%.
- 해석: Energy threshold 하향은 baseline보다 낫지만 Silero만큼은 아니다. Silero는 VAD coverage 기준으로 가장 강한 후보지만 chunk 수가 55개에서 93개로 늘었다. 기본값 후보가 되려면 VAD chunk STT에서 false-positive transcript와 global CER가 같이 좋아지는지 확인해야 한다.

Silero `threshold=0.6`, `merge gap=1.1초` 후보는 full-duration 7개 샘플까지 확인했다.

- 실행 범위: `sample/meeting` 전체 7개 샘플, `--max-seconds 0`, `--engines silero`.
- 실행 엔진: `whisper_accurate` / `openai_whisper-large-v3-v20240930_turbo`.
- 결과 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-all7`.
- 결과: 7/7 성공, measured chunk 3030/3546(raw), weighted CER 46.1%, macro CER 42.0%, RTF 0.121, peak memory 1120.359MB, empty final 329, false-positive text 508 chars.
- 주의: 긴 샘플은 Swift global CER를 skip했기 때문에 집계표의 Global CER와 Full Global CER는 전체 7개 기준값이 아니다. full-duration 판단에는 micro/macro CER, empty final, false-positive text, RTF, peak memory를 우선 사용한다.
- 해석: 120초 기준선에서는 Silero가 유망했지만, 전체 길이에서는 empty final이 329개까지 누적되고 상위 진단에도 reference가 있는 chunk가 빈 hypothesis로 끝나는 문제가 반복된다. 따라서 Silero를 기본값으로 올리는 판단은 보류하고, empty final 원인 분해와 final-only baseline 비교를 먼저 한다.

empty final 원인 분해를 위해 `WhisperEmptyClipDiagnosticsTests`에 full-duration Silero probe set을 고정했다.

- probe set: 전체 7개 샘플에서 reference length가 큰 empty final chunk를 샘플별로 1개씩 고른 7개 clip.
- 실행 옵션: `WHISPER_DIAG_PROBE_SET=sileroFullDuration`, `WHISPER_DIAG_PATH=direct|service|both`, `WHISPER_DIAG_LABELS=...`, `WHISPER_DIAG_MAX_CLIPS=...`.
- `STTService` path 7개 probe smoke 결과: 4개는 재실행 시 non-empty로 복구됐고, 3개는 여전히 empty였다.
- direct CPU-only path에서 service-empty 3개를 재실행한 결과: 2개는 `<|endoftext|>` empty segment로 끝났고, 1개는 non-empty로 복구됐다.
- `logProbNil` variant는 안전한 해법이 아니다. 2개 probe 중 1개는 여전히 empty였고, 1개는 텍스트가 나오지만 avgLogprob가 매우 낮고 문장이 심하게 깨졌다.
- 해석: empty final은 단순 VAD 누락이 아니다. 일부는 WhisperKit/turbo decode의 저신뢰 fallback 문제이고, 일부는 compute path 또는 반복 실행 상태에 따라 흔들린다. 전역 threshold 완화보다 probe 반복 측정, compute path 비교, padding/segmentation 조정이 다음 순서다.

`scripts/run_whisper_empty_probe_matrix.py`로 service-empty 3개 probe의 variant/path matrix도 고정했다.

- 결과 위치: `/private/tmp/minto2-whisper-empty-probe-matrix-20260608`.
- direct baseline: empty 1/3. 이전 수동 실행과 달라져 단일 run으로 판단하면 안 된다.
- direct `logProbNil`: empty 0/3이지만 preview text가 심하게 깨진다. 전역 완화 후보로 부적합하다.
- direct `tempFallback0`: empty 3/3. fallback 제거는 기각한다.
- direct `windowClip0`: empty 3/3. window clip time 0은 기각한다.
- service baseline: empty 2/3. production path에서도 같은 probe의 empty가 재현된다.
- baseline 반복 결과 위치: `/private/tmp/minto2-whisper-empty-probe-baseline-repeat-20260608`.
- baseline 3회 반복: direct는 label별 empty 3/3, 2/3, 3/3이고, service는 3/3, 3/3, 1/3이다. 따라서 다음 실험은 최소 3회 반복 또는 전체 sample metric으로 판단해야 한다.
- service path probe matrix는 앱 내부 skip 사유도 함께 기록한다. `service_skip_count`, `service_skip_reasons`, `service_skip_details`로 raw WhisperKit empty와 `energy_gate`, `avg_logprob`, `compression_ratio`, `low_energy_short_phantom` 필터를 구분한다.
- 검증 결과 위치: `/private/tmp/minto2-whisper-empty-probe-service-skip-reasons-20260608`.
- 결과: service baseline probe 3개 모두 empty였고, 3개 모두 `service_skip_count=0`이었다. RMS도 -24.6dB, -25.5dB, -26.7dB라 energy gate 대상이 아니다.
- 해석: 이 3개 probe의 empty는 앱 내부 skip 필터가 만든 빈 출력이 아니라 WhisperKit service path가 최종 텍스트를 내지 않은 경우다. 따라서 다음 실험은 skip threshold 완화가 아니라 direct/service compute path, decode option, chunk boundary 재분할을 우선한다.
- 전체 7개 service probe 결과 위치: `/private/tmp/minto2-whisper-empty-probe-service-skip-reasons-all7-20260608`.
- 결과: 7개 중 4개가 empty, 3개가 non-empty였고, 7개 모두 `service_skip_count=0`이었다. non-empty 3개 중 1개는 `-` 한 글자라 실질 복구로 보기 어렵다.
- 해석: full-duration에서 empty였던 probe 일부는 단독 재실행 시 non-empty로 복구된다. 하지만 이 흔들림도 앱 skip 필터 때문이 아니다. 따라서 전역 energy/logprob/compression threshold를 완화하는 변경은 근거가 약하고, chunk 경계와 WhisperKit compute/decode path 반복성을 먼저 비교해야 한다.
- direct CPU-only all7 반복은 비용이 크다. 결과 위치 `/private/tmp/minto2-whisper-empty-probe-path-repeat-all7-20260608`에서 direct baseline repeat1은 7개 중 4개 empty였고 346.8초가 걸렸다. 3회 반복은 리소스 대비 효율이 낮아 중단했다.
- service baseline all7 3회 반복 결과 위치: `/private/tmp/minto2-whisper-empty-probe-service-repeat-all7-20260608`.
- service repeat별 empty: 2/7, 3/7, 4/7. 앱 실제 경로에서도 단일 실행 결과가 흔들린다.
- service label별 empty: `silero-empty-jaegyeong-20260429-097` 3/3, `silero-empty-plenary-20260423-411` 3/3, `silero-empty-haengan-20260526-154` 0/3, `silero-empty-plenary-20260428-041` 0/3, 나머지 3개는 1/3.
- 해석: empty final probe는 "항상 실패하는 clip"과 "단독 재실행에서 회복되는 clip"으로 나뉜다. 다음 실험은 항상 실패하는 2개 label을 우선 대상으로 삼고, padding/window boundary/decode option을 반복 측정한다. direct CPU-only는 원인 분석용으로만 제한적으로 사용한다.
- padding probe 결과: 항상 service-empty였던 2개 label에 `pad=0.5초`를 적용하면 empty가 1/2, 2/2, 2/2로 안정적이지 않았다. 결과 위치는 `/private/tmp/minto2-whisper-empty-probe-service-pad05-always-empty2-20260608`.
- 같은 2개 label에 `pad=1.0초`를 적용하면 3회 모두 0/2 empty였다. 결과 위치는 `/private/tmp/minto2-whisper-empty-probe-service-pad10-always-empty2-20260608`.
- 해석: 적어도 일부 empty final은 너무 타이트한 chunk boundary와 관련이 있다. 다만 `pad=1.0초` 출력은 reference보다 길어지고 주변 문맥을 포함하므로, 기본 적용 전에는 전체 VAD chunk STT에서 empty 감소와 CER/중복 증가를 같이 재측정해야 한다.
- 120초 전체 7샘플에서 `speech padding=1.0초`를 3회 반복했다. 결과 위치는 `/private/tmp/minto2-vad-stt-120s-silero-pad100`, `/private/tmp/minto2-vad-stt-120s-silero-pad100-repeat2`, `/private/tmp/minto2-vad-stt-120s-silero-pad100-repeat3`.
- `speech padding=1.0초` 반복 결과: weighted CER 37.3%, 39.8%, 37.6%; Full Global CER 19.6%, 21.5%, 20.0%; empty 8, 8, 7; false-positive text 18 chars 고정; peak memory 1066.6MB, 1123.0MB, 1239.7MB.
- 기준 조건 `speech padding=0.12초`: weighted CER 36.9%, Full Global CER 19.9%, empty 9, false-positive text 41 chars, peak 849.0MB.
- 해석: `speech padding=1.0초`는 empty와 false-positive text를 줄이지만, Full Global CER 평균이 20.4%로 기준보다 나쁘고 peak memory도 크게 오른다. 따라서 기본 VAD padding으로 승격하지 않는다. 대신 empty가 의심되는 chunk에만 제한적으로 재전사할 수 있는 targeted boundary repair 후보로 남긴다.
- benchmark-only targeted boundary repair를 추가했다. `VAD_STT_REPAIR_PAD_SEC`가 0보다 클 때만, 첫 전사 결과가 empty인 chunk를 앞뒤로 확장해 한 번 더 전사한다. 제품 기본 경로와 일반 benchmark 기본값은 바뀌지 않는다.
- 120초 전체 7샘플에서 `speech padding=0.12초`, `repair pad=1.0초`를 3회 반복했다. 결과 위치는 `/private/tmp/minto2-vad-stt-120s-silero-pad012-repair100`, `/private/tmp/minto2-vad-stt-120s-silero-pad012-repair100-repeat2`, `/private/tmp/minto2-vad-stt-120s-silero-pad012-repair100-repeat3`.
- repair 반복 결과: weighted CER 34.2%, 33.8%, 33.9%; Full Global CER 16.2%, 16.8%, 16.9%; empty 6, 5, 5; false-positive text 41 chars 고정; RTF 0.122, 0.128, 0.119; peak memory 904.4MB, 912.7MB, 1238.3MB.
- 해석: empty-only repair는 120초 기준에서 기준 조건과 전체 padding 1.0초보다 명확히 낫다. 다만 peak memory가 한 번 크게 튀었고, false-positive text는 줄지 않았다. 따라서 기본 제품 기능으로 바로 넣지 말고 short3 full-duration에서 empty 감소, CER, RTF, peak memory를 재검증한다.
- short3 full-duration에서도 `speech padding=0.12초`, `repair pad=1.0초`를 확인했다. 결과 위치는 `/private/tmp/minto2-vad-full-silero-060-gap11-repair100-short3`.
- short3 repair 결과: weighted CER 30.7%, macro CER 29.3%, covered global CER 22.4%, Full Global CER 14.8%, empty 9, false-positive text 35 chars, RTF 0.140, peak memory 420.8MB.
- 같은 short3 기준선 `repair 없음`: weighted CER 37.9%, macro CER 35.1%, covered global CER 28.8%, Full Global CER 21.9%, empty 42, false-positive text 22 chars, RTF 0.113, peak memory 419.3MB.
- 샘플별 Full Global CER는 `본회의_20260428` 17.2%에서 13.0%, `본회의_20260508` 8.2%에서 6.8%, `재정경제기획위원회_20260430` 30.8%에서 19.6%로 모두 개선됐다.
- repair 시도/채택은 38회/29회였다. empty final은 크게 줄었지만 false-positive text와 RTF는 증가했다. 따라서 제품 기본값이 아니라 `sample/meeting` 전체 full-duration 검증으로 승격한다.
- 전체 7샘플 full-duration에서도 `speech padding=0.12초`, `repair pad=1.0초`를 순차 실행했다. 결과 위치는 `/private/tmp/minto2-vad-full-silero-060-gap11-repair100-all7`.
- all7 repair 결과: 7/7 성공, weighted CER 42.6%, macro CER 37.9%, empty 133, false-positive text 628 chars, RTF 0.129, peak memory 1673.3MB.
- 같은 all7 기준선 `repair 없음`: weighted CER 46.1%, macro CER 42.0%, empty 329, false-positive text 508 chars, RTF 0.121, peak memory 1120.4MB.
- repair 시도/채택은 337회/204회였다. 샘플 7개 모두 weighted CER와 empty final은 개선됐지만, false-positive text는 508에서 628 chars로 늘었고 peak memory는 1673.3MB까지 상승했다.
- 해석: all7 기준에서도 empty-only repair는 정확도와 empty final 문제를 실질적으로 줄인다. 하지만 비용과 부작용이 확인됐으므로 제품 기본값으로 승격하지 않는다. 다음은 `repair pad=1.0초` 그대로 제품 적용이 아니라, feature flag 전제의 더 좁은 guard 또는 더 작은 repair pad sweep을 먼저 검증한다.
- 제품 경로에는 기본 off인 `MINTO_EMPTY_FINAL_REPAIR=1` feature flag로 empty-only repair 훅을 추가했다. live audio 원본 PCM을 짧게 보관하고, final STT가 empty일 때만 `startSeconds/endSeconds` 앞뒤 padding 구간을 한 번 재전사한다.
- 제품 repair 기본 guard는 `pad=1.0초`, `min chunk=2.0초`, `min audio=-35dB`, `buffer=45초`다. 기본값은 off이므로 기존 녹음 UX와 기본 benchmark 경로는 바뀌지 않는다.
- `repair pad=0.75초`도 120초 전체 7샘플에서 3회 반복했다. 결과 위치는 `/private/tmp/minto2-vad-stt-120s-silero-pad012-repair075`, `/private/tmp/minto2-vad-stt-120s-silero-pad012-repair075-repeat2`, `/private/tmp/minto2-vad-stt-120s-silero-pad012-repair075-repeat3`.
- `repair pad=0.75초` 반복 결과: weighted CER 34.2%, 34.6%, 34.1%; Full Global CER 17.5%, 17.5%, 16.4%; empty 4, 4, 6; false-positive text 46, 46, 41 chars; RTF 0.124, 0.118, 0.126; peak memory 1238.2MB, 1239.7MB, 1036.8MB.
- `repair pad=1.0초` 3회 평균은 weighted CER 34.0%, Full Global CER 16.6%, empty 5.3, false-positive text 41 chars, RTF 0.123, peak memory 1018.5MB다.
- 해석: 0.75초는 empty 평균만 1.0초보다 약간 낮지만, Full Global CER, false-positive text, peak memory가 모두 더 나쁘다. 따라서 0.75초를 short3/full 후보로 올리지 않는다. 다음은 padding 크기 축이 아니라 repair retry가 어떤 chunk에서 false-positive를 만드는지 계측하고 RMS/duration/confidence guard를 검증한다.
- repair retry telemetry를 추가했다. segment diagnostics는 원본 audio dB, repair 시도/채택 여부, repair duration, repair audio dB, reference 유무, accepted repair의 false-positive 여부를 보여준다.
- telemetry smoke 결과 위치는 `/private/tmp/minto2-vad-stt-telemetry-smoke`다. `재정경제기획위원회_20260430` 첫 120초에서 repair는 3회 시도, 2회 채택, repair false-positive 0회로 기록됐고 `segments.md`/`segments.csv`에서 컬럼이 확인됐다.
- 첫 guard 후보도 120초 전체 7샘플에서 3회 반복했다. 조건은 `repair pad=1.0초`, `min chunk=2.0초`, `min audio=-35dB`다.
- guard 반복 결과: weighted CER 33.9%, 34.4%, 34.3%; Full Global CER 17.1%, 15.5%, 15.6%; empty 5, 7, 7; false-positive text 41 chars 고정; RTF 0.166, 0.258, 0.160; peak memory 526.1MB, 520.6MB, 751.0MB.
- guard는 세 run 모두 5개 retry를 skip했고 repair false-positive는 0이었다. 하지만 no-guard `repair pad=1.0초` 평균 대비 empty final은 약간 나쁘고 RTF도 명확히 좋아지지 않았다. 따라서 short3 full-duration으로 승격하지 않고, 같은 batch에서 no-guard 대조 또는 다른 guard threshold 후보를 먼저 본다.
- 약한 guard 후보 A도 120초 전체 7샘플에서 1회 확인했다. 조건은 `min chunk=1.0초`, `min audio=-45dB`다. 결과는 weighted CER 36.0%, Full Global CER 18.4%, empty 7, false-positive text 41 chars, RTF 0.158, peak 605.3MB, retry 9회, accepted 6회, guard skipped 4회였다.
- 후보 A는 no-guard보다 retry를 조금 줄였지만 empty final을 줄이지 못했고, 기존 `2.0초/-35dB` guard repeat1보다 CER/empty가 나쁘다. 따라서 현재는 repeat2/repeat3를 돌리지 않고 prune한다.
- guard 후보 B도 120초 전체 7샘플에서 1회 확인했다. 조건은 `min chunk=2.0초`, `min audio=-45dB`다. 결과는 weighted CER 35.0%, Full Global CER 17.5%, empty 6, false-positive text 41 chars, RTF 0.157, peak 670.3MB, retry 6회, accepted 5회, guard skipped 5회였다.
- 후보 B는 후보 A보다는 낫지만 기존 `2.0초/-35dB` guard repeat1과 no-guard repair repeat1보다 정확도 이득이 약하다. 따라서 repeat2/repeat3를 돌리지 않고 prune한다.
- guard 후보 C도 120초 전체 7샘플에서 1회 확인했다. 조건은 `min chunk=1.0초`, `min audio=-35dB`다. 결과는 weighted CER 34.1%, Full Global CER 17.2%, empty 5, false-positive text 41 chars, RTF 0.146, peak 590.2MB, retry 6회, accepted 5회, guard skipped 5회였다.
- 후보 C는 기존 `2.0초/-35dB` guard repeat1과 거의 비슷하지만, no-guard repair repeat1의 Full Global CER 16.2%보다는 나쁘다. guard의 목적을 정확도 개선이 아니라 peak memory와 retry 폭주 억제로 둘 때만 추가 반복 가치가 있다.

Silero segmentation small sweep도 같은 7개 120초 기준선에서 확인했다.

- 기준 조건: `threshold=0.6`, `merge gap=1.1초`, `merge max=15초`, `speech padding=0.12초`, `min speech=0.25초`.
- 기준 결과: weighted CER 36.9%, Full Global CER 19.9%, empty final 9, false-positive text 41 chars, RTF 0.107, peak 849.0MB.
- `speech padding=0.30초`: weighted CER 40.5%, Full Global CER 24.0%, empty final 10, false-positive text 41 chars, RTF 0.109, peak 802.8MB.
- `min speech=0.50초`: weighted CER 37.0%, Full Global CER 20.1%, empty final 8, false-positive text 41 chars, RTF 0.111, peak 719.0MB.
- `merge max=20초`: weighted CER 34.0%, Full Global CER 19.5%, empty final 9, false-positive text 41 chars, RTF 0.097, peak 687.3MB.
- 해석: padding 증가는 기각한다. min speech 증가는 empty 1개를 줄였지만 CER가 개선되지 않아 기본 후보로는 약하다. `merge max=20초`는 120초 기준에서 CER/RTF/peak memory가 좋아졌지만 empty는 줄지 않았다. 따라서 바로 기본값 변경이 아니라, `merge max=20초`만 반복 측정과 short3 full-duration 재검증 후보로 올린다.

`merge max=20초` 반복 측정 결과, short3 full-duration 재검증은 보류한다.

- 실행 범위: `sample/meeting` 7개 샘플, 각 120초, `threshold=0.6`, `merge gap=1.1초`, `merge max=20초`.
- repeat1: weighted CER 34.0%, Full Global CER 19.5%, empty final 9, false-positive text 41 chars, RTF 0.097, peak 687.3MB.
- repeat2: weighted CER 36.0%, Full Global CER 21.6%, empty final 10, false-positive text 41 chars, RTF 0.099, peak 930.2MB.
- repeat3: weighted CER 34.1%, Full Global CER 19.5%, empty final 9, false-positive text 41 chars, RTF 0.124, peak 911.4MB.
- 기준 조건 `merge max=15초`: weighted CER 36.9%, Full Global CER 19.9%, empty final 9, false-positive text 41 chars, RTF 0.107, peak 849.0MB.
- 해석: weighted CER는 반복 3회 모두 기준 조건보다 낮지만, VAD 정책 판단의 1차 지표인 Full Global CER는 repeat2에서 기준보다 나빠졌고 3회 평균도 20.2%로 기준 19.9%보다 낮지 않다. empty final도 줄지 않는다. 따라서 `merge max=20초`는 기본값 후보로 승격하지 않고, full-duration short3 실행도 리소스 대비 근거가 약해 보류한다.
- 다음 순서: merge 길이 조정보다 empty final 원인 분해, low-energy skip 정책, true streaming 가능 엔진의 partial/final 구조 비교를 우선한다.

같은 runner로 Apple 엔진 smoke도 확인했다.

- `sf_speech_on_device`: 현재 시스템에서 "Apple 음성 인식 권한이 거부" 상태라 1샘플 smoke가 load 단계에서 실패했다.
- `speech_analyzer`: 현재 테스트 플랫폼은 `arm64e-apple-macos14.0`이고, 한국어 SpeechAnalyzer 지원을 찾지 못해 1샘플 smoke가 load 단계에서 실패했다.
- 결론: 이 Mac의 현재 상태에서는 WhisperKit turbo만 재현 가능한 benchmark 대상이다. SFSpeech는 권한/Dictation 상태를 풀고 다시 측정해야 하고, SpeechAnalyzer는 macOS 26+ 지원 환경에서 다시 측정해야 한다.

## 핵심 판단

true streaming은 일부 streaming 지원 엔진에만 적용한다.

- WhisperKit, SFSpeech file/request, Nemotron offline sidecar는 one-shot final 엔진이다.
- WhisperKit rolling preview는 반복 재전사 기반 preview이지 true streaming이 아니다.
- SpeechAnalyzer streaming, sherpa streaming, FluidAudio streaming 계열처럼 session cache와 partial/final event를 제공하는 엔진만 streaming 경로에 태운다.
- one-shot과 streaming을 하나의 protocol에 억지로 맞추면 기존 안정성이 흔들린다.
- STT 정확도 개선, transcript 가독성 개선, LLM 회의록 품질 개선은 서로 다른 metric으로 평가한다.

## 목표 구조

목표 파이프라인은 다음 형태다.

> AudioSource
> → Segmenter/VAD
> → TranscriptionCoordinator
> → one-shot engine 또는 streaming engine
> → TranscriptAssembler
> → raw transcript store
> → TranscriptNormalizer
> → LLM correction / summary / export

역할은 이렇게 나눈다.

- `STTService`: 엔진 선택, 로딩 상태, availability, fallback, cache recovery를 담당한다.
- `SpeechTranscriptionEngine`: one-shot final 전사 경계다. WhisperKit, SFSpeech, SpeechAnalyzer final-only, Nemotron sidecar가 이쪽이다.
- `StreamingTranscriptionEngine`: true streaming 엔진 전용 경계다. continuous sample input, partial callback, final callback, finish/reset lifecycle을 가진다.
- `VoiceActivityDetector`: 음성 구간 후보를 만든다. Energy VAD와 Silero VAD를 같은 계약으로 비교한다.
- `TranscriptionCoordinator`: VAD chunk, one-shot final, streaming event를 한 곳에서 조율한다. 지금 `TranscriptionViewModel`에 있는 흐름을 점진적으로 옮길 대상이다.
- `TranscriptAssembler`: preview/final 전환, empty final, partial revision, timestamp 보존을 담당한다.
- `TranscriptNormalizer`: 저장/export용 문단 정리다. CER 개선으로 계산하지 않는다.
- `MeetingNoteProcessor`: 개인 OAuth LLM 또는 로컬 LLM 후처리다. STT 엔진과 분리한다.

## 우선순위

### P0. 현재 기준선 고정

**상태**

- 완료에 가깝다. 지금은 이 기준선을 깨지 않는 것이 중요하다.

**목표**

- WhisperKit turbo 기본 경로를 유지한다.
- stop/drain, preview empty-final, normalizer, benchmark metric 테스트를 기준선으로 고정한다.
- 미추적 보고서/디자인 파일은 별도 산출물로 두고 코드 변경과 섞지 않는다.

**검증**

- `swift test --disable-sandbox`
- `git diff --check`

**성공 기준**

- 기존 기본 엔진이 `openai_whisper-large-v3-v20240930_turbo`로 유지된다.
- stop 직전 짧은 발화가 drain된다.
- final empty가 preview를 조용히 지우지 않는다.
- 저장/export는 `TranscriptNormalizer`를 지난다.

### P1. benchmark 하니스 표준화

**상태**

- 진행 중이다. 엔진 논쟁을 끝내려면 먼저 측정 형식을 고정해야 한다.
- `STTBenchmarkRunMetric` / `STTBenchmarkSegmentMetric` schema v1을 추가했다.
- `MeetingCorpusTests`, `VADBenchmarkTests`의 STT 측정, `StreamingChunkBenchmarkTests`는 같은 top-level schema로 JSON을 쓴다.
- `peak_memory_mb`는 macOS `getrusage` 기반 peak RSS 스냅샷으로 기록한다.
- `scripts/run_meeting_stt_benchmarks.py`로 `sample/meeting` 샘플과 엔진을 순차 실행할 수 있다.
- `scripts/summarize_stt_benchmarks.py`로 실행 결과를 엔진별 weighted CER/RTF/peak memory 표로 요약할 수 있다.
- `scripts/run_meeting_vad_benchmarks.py`로 VAD baseline 또는 VAD chunk STT를 `sample/meeting` 전체에 순차 실행할 수 있다.
- `scripts/summarize_vad_benchmarks.py`로 VAD speech recall, short recall, missed speech, false-positive seconds를 엔진별로 요약할 수 있다.
- full-duration 실행에서 Swift global CER를 skip한 경우, `scripts/summarize_stt_benchmarks.py --compute-missing-global-cer`로 작은 ref/hyp 파일에 한해 global CER를 후계산할 수 있다.
- `scripts/summarize_stt_benchmarks.py --write-segments --vad-root ...`로 empty final과 high-CER window를 샘플/시간대/duration/reference density/VAD overlap/bucket/참조문/가설문 기준으로 정렬해 볼 수 있다.
- VAD overlap bucket은 low-overlap empty를 VAD/segmentation miss 후보로, high-overlap empty를 ASR empty decode 후보로 나눈다.

**작업**

- 모든 STT benchmark output을 같은 schema로 맞춘다.
- 결과는 `tmp/`에 저장하고, 사람이 읽는 요약만 `docs/`에 남긴다.
- 긴 샘플은 병렬 수를 제한해 메모리 폭주를 막는다.
- 전체 회의 실행에서는 Swift global CER를 자동 skip하고, per-window micro/macro CER와 peak memory를 먼저 본다.
- benchmark runner는 같은 샘플을 다음 축으로 분리해 실행한다.
  - 60초 smoke
  - 120초 비교
  - `sample/meeting` 전체
  - streaming chunk 실험

**공통 metric**

- engine id
- model id
- sample id
- reference length
- hypothesis length
- per-sample CER
- macro CER
- micro CER
- global CER
- empty final count
- false-positive transcript chars
- elapsed seconds
- RTF
- aggregate RTF
- peak memory
- supports preview

**streaming metric**

- first partial latency
- partial revision count
- final latency
- final CER
- unstable partial ratio
- long session memory growth

**검증**

- WhisperKit turbo, SpeechAnalyzer, SFSpeech on-device가 같은 schema를 생성한다.
- preview 미지원 엔진은 실패하지 않고 `supports_preview=false`로 기록된다.
- 메모리 부족으로 Mac이 꺼지지 않도록 동시 실행 수 제한이 동작한다.

**성공 기준**

- "어떤 엔진이 낫다"는 판단을 같은 샘플, 같은 metric으로 재현할 수 있다.

### P2. final-only 엔진 제품 후보 결정

**목표**

- 현재 제품 기본 경로는 final-only 품질부터 안정화한다.
- macOS 26 이상은 SpeechAnalyzer를 1순위 후보로 보되, 기본값 변경은 전체 샘플 결과 이후로 미룬다.

**작업**

- WhisperKit turbo를 baseline으로 고정한다.
- SpeechAnalyzer final-only 경로의 availability gate를 제품 UX와 연결한다.
  - OS 버전
  - Korean locale 지원
  - language asset 설치 상태
  - 권한 상태
- SFSpeech on-device는 보조 Apple-native 후보로만 둔다.
- unsupported 환경은 WhisperKit turbo fallback으로 간다.
- 모델 선택 UI에는 "왜 비활성인지"를 설명 가능한 상태로 노출한다.

**검증**

- `sample/meeting` 전체 CER
- 10분 이상 긴 파일 batch
- asset 미설치 상태
- OS 미지원 상태
- 권한 거부 상태
- 실제 앱 녹음 종료 flow

**성공 기준**

- SpeechAnalyzer가 지원 환경에서 WhisperKit turbo보다 CER 또는 latency가 명확히 좋다.
- 미지원 환경에서 조용히 실패하지 않고 fallback이 동작한다.
- SFSpeech는 1분 제한, on-device 가능 여부, 긴 파일 안정성 검증 없이는 기본값으로 올리지 않는다.

### P3. VAD와 segmentation 개선

**목표**

- 짧은 발화와 stop 직전 발화 누락을 줄인다.
- 잡음 chunk 증가와 hallucination 증가를 막는다.

**작업**

- Energy VAD를 현재 기본값으로 유지한다.
- Silero VAD는 후보 adapter로만 붙인다.
- empty final이 난 chunk만 원본 audio boundary를 확장해 한 번 재전사하는 targeted boundary repair를 검증한다.
- short utterance probe set을 유지한다.
  - 0.5초 미만
  - 0.8초 전후
  - 짧은 대답
  - 말 끝이 바로 녹음 종료되는 케이스
- chunk merge 정책을 명시적으로 분리한다.
  - min duration
  - max duration
  - merge gap
  - speech probability threshold
- ASR-aware segmentation을 실험한다. VAD recall이 좋아도 STT CER가 나빠지면 기본값으로 올리지 않는다.

**현재 60초 smoke 결과**

- energy VAD + WhisperKit turbo: chunk CER 35.8%, global CER 31.2%, empty final 1, false-positive text 1 chunk / 13 chars.
- Silero VAD + gap merge 1.1초 + WhisperKit turbo: chunk CER 54.5%, global CER 31.8%, empty final 1, false-positive text 0.
- 해석: Silero는 false-positive를 줄일 가능성이 있지만, chunk 경계가 잘게 나뉘면 WhisperKit final CER가 나빠질 수 있다. 기본값 변경은 아직 금지다.
- 2026-06-08 재현 조건: `haengan_20260526` 첫 60초, `openai_whisper-large-v3-v20240930_turbo`, 로컬 `WHISPER_MODEL_FOLDER`, `scripts/run_meeting_vad_benchmarks.py --mode stt`.
- 실행 주의: WhisperKit/CoreML STT smoke는 E5RT cache를 `~/Library/Caches/swiftpm-testing-helper`에 쓰므로 샌드박스 안에서는 `.pixelBufferFailed`로 실패할 수 있다. 같은 명령을 샌드박스 밖에서 실행하면 통과했다.
- 요약 주의: VAD chunk STT 결과는 같은 `engine_id`라도 VAD config가 다르면 별도 후보로 봐야 한다. `scripts/summarize_stt_benchmarks.py`는 VAD metadata가 있는 결과를 VAD/threshold/merge config별로 분리해 요약한다.

**현재 7샘플 120초 결과**

- 재현 조건: `sample/meeting` 7개 샘플 첫 120초, `openai_whisper-large-v3-v20240930_turbo`, 로컬 `WHISPER_MODEL_FOLDER`, Energy default vs Silero `threshold=0.5`, `merge gap=1.1초`.
- Energy default: weighted CER 52.0%, covered global CER 43.0%, Full Global CER 47.8%, RTF 0.136, peak 1078.8MB, empty final 8, false-positive text 78 chars.
- Silero + gap merge: weighted CER 39.7%, covered global CER 30.5%, Full Global CER 22.5%, RTF 0.120, peak 1238.9MB, empty final 12, false-positive text 42 chars.
- 해석: 전체 reference 기준으로 missed speech를 deletion 처리해도 Silero가 크게 이긴다. 다만 empty final은 8개에서 12개로 늘고 peak memory도 약 160MB 증가했다. Silero는 기본값 후보로 승격하되, 바로 기본값으로 바꾸기 전에 empty final 원인과 threshold/merge sweep을 추가로 본다.
- 측정 주의: VAD별 chunk가 다르면 기존 `global_cer`는 emitted chunk reference만 비교하므로 missed speech를 벌점 처리하지 못한다. VAD 후보 결정에는 `full_reference_global_cer`를 우선한다.

**현재 Silero threshold/merge sweep 결과**

- 재현 조건: 같은 7개 샘플 첫 120초, Silero VAD, WhisperKit turbo, `vad-stt-max-chunks=0`.
- `threshold=0.6`, `merge gap=1.1초`: weighted CER 36.9%, covered global CER 28.6%, Full Global CER 19.9%, RTF 0.107, peak 849.0MB, empty final 9, false-positive text 41 chars.
- `threshold=0.6`, `merge gap=1.8초`: weighted CER 37.1%, covered global CER 28.4%, Full Global CER 20.2%, RTF 0.107, peak 854.1MB, empty final 9, false-positive text 41 chars.
- `threshold=0.7`, `merge gap=1.1초`: weighted CER 36.7%, covered global CER 28.8%, Full Global CER 21.3%, RTF 0.097, peak 1238.8MB, empty final 10, false-positive text 41 chars.
- 해석: 현재 최선 후보는 `threshold=0.6`, `merge gap=1.1초`다. 0.5보다 Full Global CER와 empty final이 모두 좋아졌고, 0.7은 속도는 빠르지만 Full Global CER가 밀린다. merge gap 1.8초는 1.1초 대비 실질 이득이 없다.
- 다음 판단: Silero `threshold=0.6`, `merge gap=1.1초`를 feature-flagged adapter 후보로 구현하고, 전체 길이 또는 더 긴 window에서 반복 실행해 ANE/CoreML 비결정성에도 이 우위가 유지되는지 본다.

**현재 코드 반영 방향**

- Silero는 바로 기본값으로 바꾸지 않고 `MINTO_VAD_ENGINE=silero` 환경값으로만 켠다.
- 로컬 FluidAudio/Silero 모델 bundle이 없으면 기존 Energy VAD로 fallback한다.
- 현재 후보 기본값은 `threshold=0.6`, `merge gap=1.1초`다.
- app 기본 경로는 기존 Energy VAD를 유지한다. 따라서 기본 녹음 UX는 이번 실험 코드만으로 바뀌지 않는다.
- feature flag로 붙인 뒤 `sample/meeting` 전체 길이 VAD chunk STT를 다시 돌려 Full Global CER, empty final, false-positive text, peak memory를 확인한다.

**현재 full-duration 운영 보정과 short3 결과**

- `scripts/run_meeting_vad_benchmarks.py --max-seconds 0`이 실제 full-duration이 아니라 내부 기본 120초로 되돌아가는 문제를 확인했다. 이제 `0`은 no cap, 양수는 cap, 미지정은 기존 120초 smoke로 고정한다.
- full-duration VAD chunk STT에서는 긴 회의의 global Levenshtein이 O(n*m)으로 터질 수 있다. runner에 `--skip-swift-global-cer auto`를 추가해 `--max-seconds 0`일 때는 global/full-global CER를 자동 skip할 수 있게 한다.
- 전체 샘플을 한 번에 돌릴 때 긴 파일이 먼저 잡히면 첫 결과까지 너무 오래 걸린다. runner에 `--sort duration`을 추가해 full run은 짧은 파일부터 처리한다.
- 실제 full-duration short3 재현 조건: `본회의_20260428` 724초, `본회의_20260508` 1069초, `재정경제기획위원회_20260430` 1560초, Silero `threshold=0.6`, `merge gap=1.1초`, WhisperKit turbo, `--skip-swift-global-cer never`.
- 결과 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-short3`.
- 결과: 3/3 성공, weighted CER 37.9%, macro CER 35.1%, covered global CER 28.8%, Full Global CER 21.9%, RTF 0.113, peak memory 419.3MB, empty final 42, false-positive text 22 chars.
- 샘플별 Full Global CER: `본회의_20260428` 17.2%, `본회의_20260508` 8.2%, `재정경제기획위원회_20260430` 30.8%.
- 같은 short3의 WhisperKit turbo 20초 final-only baseline은 weighted CER 56.5%, mean global CER 48.4%, empty final 75개였다.
- 해석: Silero 0.6/gap1.1은 짧은 full 샘플에서도 단순 20초 final-only보다 정확도와 empty final이 모두 낫다. 다만 긴 구간으로 갈수록 empty final이 누적된다. 특히 `재정경제기획위원회_20260430`에서 133 chunk 중 29개가 empty final이라 기본값 승격 전 empty final 원인 분해가 필요하다.
- 실제 full-duration long1 재현 조건: `재정경제기획위원회_20260429` 6846초, Silero `threshold=0.6`, `merge gap=1.1초`, WhisperKit turbo, `--skip-swift-global-cer auto`.
- 결과 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-20260429`.
- 결과: 1/1 성공, measured chunk 594/594(raw 643), weighted CER 49.3%, macro CER 49.3%, global CER skip, RTF 0.126, peak memory 1021.4MB, empty final 87, false-positive text 103 chars, wall time 857.2초.
- 해석: 첫 긴 샘플에서도 속도는 실시간보다 충분히 빠르지만 정확도는 short3보다 악화됐다. empty final 비율은 87/594, 약 14.6%로 short3의 42/285, 약 14.7%와 거의 같다. 따라서 문제는 특정 짧은 파일 하나의 우연이 아니라 Silero chunk + WhisperKit decode 조합에서 반복되는 empty final 패턴으로 본다.
- segment 진단: `segments.md` 상위 항목은 대부분 reference density가 높은 13.8초 chunk에서 hypothesis가 완전히 빈 경우다. VAD가 무음을 잘못 넣은 false positive라기보다, speech chunk가 WhisperKit final empty로 빠지는 문제를 우선 의심한다.
- 실제 full-duration long2 재현 조건: `haengan_20260526` 7378초, Silero `threshold=0.6`, `merge gap=1.1초`, WhisperKit turbo, `--skip-swift-global-cer auto`.
- 결과 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-haengan`.
- 결과: 1/1 성공, measured chunk 681/681(raw 889), weighted CER 40.3%, macro CER 40.3%, global CER skip, RTF 0.124, peak memory 1120.4MB, empty final 55, false-positive text 149 chars, wall time 851.1초.
- 해석: long2는 long1보다 CER와 empty final 비율이 낮다. empty final 비율은 55/681, 약 8.1%다. 다만 `segments.md` 상위 항목은 long1과 마찬가지로 reference가 있는 chunk가 완전히 빈 hypothesis로 끝난 케이스가 반복된다.
- 실제 full-duration long3 재현 조건: `외교통일위원회_20260520` 7555초, Silero `threshold=0.6`, `merge gap=1.1초`, WhisperKit turbo, `--skip-swift-global-cer auto`.
- 결과 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-diplomacy`.
- 결과: 1/1 성공, measured chunk 679/679(raw 798), weighted CER 53.8%, macro CER 53.8%, global CER skip, RTF 0.112, peak memory 755.9MB, empty final 75, false-positive text 9 chars, wall time 845.3초.
- 해석: long3는 false-positive text는 낮지만 weighted CER가 가장 높다. empty final 비율은 75/679, 약 11.0%다. 따라서 Silero 후보의 문제는 false-positive 증가 하나로 설명되지 않고, reference가 있는 speech chunk의 empty final과 non-empty high-CER chunk가 함께 작동한다.
- 실제 full-duration long4 재현 조건: `본회의_20260423` 11608초, Silero `threshold=0.6`, `merge gap=1.1초`, WhisperKit turbo, `--skip-swift-global-cer auto`.
- 결과 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-plenary-20260423`.
- 결과: 1/1 성공, measured chunk 791/791(raw 884), weighted CER 45.5%, macro CER 45.5%, global CER skip, RTF 0.127, peak memory 1071.8MB, empty final 70, false-positive text 225 chars, wall time 909.6초.
- 해석: long4도 같은 패턴이다. 속도는 RTF 0.127로 충분히 빠르지만, empty final 비율은 70/791, 약 8.8%다. 상위 segment 진단은 reference density가 높은 speech chunk가 빈 출력으로 끝나는 행을 반복해서 보여준다.
- 전체 7개 full-duration 집계 위치: `/private/tmp/minto2-vad-full-silero-060-gap11-all7`.
- 전체 7개 결과: measured chunk 3030/3546(raw), weighted CER 46.1%, macro CER 42.0%, RTF 0.121, peak memory 1120.4MB, empty final 329, false-positive text 508 chars.
- 전체 7개 해석: Silero 0.6/gap1.1은 빠르고 VAD coverage 후보로는 유효하지만, 현재 chunk 경계와 WhisperKit final decode 조합에서는 empty final이 약 10.9%까지 누적된다. 따라서 다음 판단은 "Silero default 승격"이 아니라 "empty final 원인 분해 후 재측정"이다.

**검증**

- short utterance recall
- false-positive chunk count
- false-positive transcript chars
- empty final count
- per-chunk CER
- covered global CER
- Full Global CER
- stop/drain 누락 여부
- 전체 샘플 VAD recall과 short recall
- STT 실패 segment의 VAD overlap bucket 분포

**성공 기준**

- 짧은 발화 recall이 오른다.
- global CER가 악화되지 않는다.
- false-positive transcript가 늘지 않는다.
- empty-only repair가 전체 padding보다 낮은 CER와 낮은 empty final을 유지한다.
- repair retry가 peak memory와 latency를 장시간 회의에서 위험하게 만들지 않는다.

### P4. 녹음 종료와 후처리 안정성

**목표**

- 사용자가 본 preview, 저장된 final, correction, summary, export가 종료 시점에 서로 어긋나지 않게 한다.

**현재 고정된 것**

- `stopRecordingAndDrain()`은 audio stop 이후 VAD `flushPending()`을 호출하고 final chunk를 전사 queue에 넣는다.
- final STT가 empty이면 기존 preview를 즉시 지우지 않는다.
- `finalizeMeeting()`은 마지막 correction task를 기다린 뒤 최종 summary를 만든다.

**남은 작업**

- correction batch flush 이후 summary incremental이 진행 중일 때 종료 UX가 어떻게 보이는지 테스트한다.
- LLM provider가 none, 실패, timeout일 때 저장/export가 원문 fallback으로 끝나는지 테스트한다.
- finalizing 상태에서 사용자가 다시 녹음을 시작하거나 창을 닫는 경로를 테스트한다.
- stop 직전 enqueue된 main queue audio buffer가 실제 기기에서도 누락되지 않는지 수동 QA한다.

**검증**

- stop 직전 0.5초/0.8초 발화 저장 여부
- preview-only 상태 유지 여부
- correction 실패 fallback
- summary 실패 fallback
- 저장 record와 report export의 transcript 일치

**성공 기준**

- 짧은 마지막 말이 사라지지 않는다.
- final empty 때문에 UI가 비어 보이지 않는다.
- LLM 실패가 회의 저장 실패로 번지지 않는다.

### P5. true streaming 경로 추가

**목표**

- streaming 지원 엔진만 session lifecycle을 사용한다.
- one-shot 엔진의 기존 성능과 안정성을 유지한다.

**현재 고정된 것**

- `StreamingTranscriptionEngine` / `StreamingTranscriptionSession` protocol scaffold를 추가했다.
- streaming event는 `partial`과 `final`을 구분하고 revision을 기록한다.
- `SpeechEngineID.supportsTrueStreaming`을 추가했다. 현재 등록된 WhisperKit, SpeechAnalyzer final-only, SFSpeech on-device 엔진은 모두 `false`다.
- WhisperKit rolling preview는 `supportsPreviewTranscription=true`지만 true streaming은 아니다.
- `TranscriptionCoordinatorPlan` scaffold를 추가했다. 현재 엔진은 `oneShotVADChunks`, true streaming capability는 `trueStreamingSession`으로 route된다.
- `TranscriptionCoordinator` hidden runner를 추가했다. 제품 경로 밖에서 streaming session `accept` / `finish`와 partial/final event metric을 검증할 수 있다.
- `SpeechAnalyzerStreamingEngine` hidden PoC를 추가했다. 16kHz mono Float32 chunk를 `AnalyzerInput`으로 변환하고 progressive result를 streaming event로 바꾼다.
- 현재 로컬 수동 smoke는 한국어 SpeechAnalyzer availability에서 skip된다. 지원 환경에서는 같은 `RUN_SPEECH_ANALYZER_STREAMING_POC=1` smoke로 session을 확인한다.
- 아직 `STTService`나 `TranscriptionViewModel`의 제품 경로에 streaming session을 연결하지 않았다.

**작업**

- 지원 환경에서 `SpeechAnalyzerStreamingEngine` manual smoke를 재실행해 실제 partial/final event를 확인한다.
- `TranscriptionCoordinator` runtime을 제품 경로에 점진적으로 연결한다.
  - one-shot: VAD chunk final + optional rolling preview
  - streaming: continuous samples + engine partial/final event
- rolling preview metric과 true streaming metric을 분리한다.
- 참고 구현은 SpeechAnalyzer streaming, sherpa streaming, FluidAudio streaming 구조를 본다.

**검증**

- first partial latency
- partial revision count
- final latency
- final CER
- long session memory growth
- stop/drain 누락

**성공 기준**

- streaming-capable engine은 chunk 재전사 없이 partial/final을 낸다.
- one-shot engine은 기존 benchmark 결과가 악화되지 않는다.
- streaming이 정확도를 망치면 UI preview 실험에만 남기고 기본값으로 올리지 않는다.

### P6. Nemotron MLX sidecar 연구

**목표**

- Nemotron은 앱 기본 엔진이 아니라 고정확도 연구 엔진으로 검증한다.
- Python/MLX sidecar로 붙일 때의 현실성을 숫자로 판단한다.

**작업**

- Python sidecar를 앱 밖 프로세스로 둔다.
- Swift 앱은 localhost HTTP, stdin/stdout, 또는 Unix domain socket 중 하나로 요청한다.
- 처음에는 final chunk 전용으로만 붙인다.
- 8-bit 또는 더 작은 quantized 모델을 우선 검증한다.
- worker warm-up, queue limit, timeout, crash restart를 둔다.
- peak memory와 cold start latency를 필수 metric으로 기록한다.

**검증**

- `sample/meeting` 전체 CER
- current VAD chunk CER
- 60초 offline chunk CER와 실제 앱 chunk CER 차이
- cold start latency
- warm start latency
- peak memory
- 30분 반복 실행
- worker crash 후 WhisperKit fallback

**성공 기준**

- WhisperKit/SpeechAnalyzer 대비 CER 이득이 실제 앱 chunk에서도 유지된다.
- 메모리 사용량이 사용자 Mac에서 안전하다.
- sidecar 장애가 앱 UI를 멈추지 않는다.

**중단 기준**

- peak memory가 과도하다.
- dependency 설치와 모델 관리가 일반 사용자가 감당하기 어렵다.
- crash isolation이 안 된다.
- 정확도 이득이 전체 샘플에서 재현되지 않는다.

### P7. transcript normalization과 회의록 후처리

**목표**

- 원문 transcript와 사용자에게 보여줄 회의록 문단을 분리한다.
- STT 정확도와 회의록 가독성을 따로 개선한다.

**작업**

- 현재 `TranscriptNormalizer`를 유지하되, sample 기반 regression set을 늘린다.
- 원문 segment는 그대로 보존한다.
- 저장/export 문단만 병합, 줄바꿈, 문장 정리를 적용한다.
- LLM correction은 별도 단계로 둔다.
- 개인 OAuth LLM과 로컬 LLM을 후처리 옵션으로 둔다.
- LLM 비용이 없는 경로에서도 기본 회의록이 읽을 만해야 한다.

**검증**

- 원문 보존 여부
- normalized paragraph 수
- 너무 긴 줄/너무 짧은 줄 비율
- dangling ending 감소율
- export 수동 QA
- LLM 실패 시 원문 fallback

**성공 기준**

- CER는 그대로여도 읽기 좋은 회의록이 된다.
- "정확도가 좋아졌다"와 "읽기 좋아졌다"를 분리해서 설명할 수 있다.

### P8. diarization PoC

**목표**

- 회의록 앱에서 중요한 "누가 말했는가"를 STT 다음 축으로 검증한다.

**작업**

- audio offset을 모든 segment에 보존한다.
- offline diarization을 먼저 붙인다.
- speaker timeline과 transcript segment를 overlap으로 매칭한다.
- FluidAudio diarization 또는 다른 local diarization 후보를 benchmark 전용으로 비교한다.
- streaming diarization은 후순위로 둔다.

**검증**

- speaker segment 수
- speaker switch 탐지
- transcript-speaker overlap matching
- 수동 label 샘플 품질
- speaker label이 틀렸을 때 UI/export가 망가지지 않는지

**성공 기준**

- speaker label이 틀려도 원문 transcript를 훼손하지 않는다.
- 저장/export 단계에서 최소한 유용한 speaker 구분을 제공한다.

## 기본값 변경 기준

STT 기본값은 아래 조건을 모두 만족할 때만 바꾼다.

- `sample/meeting` 전체 micro CER가 WhisperKit turbo보다 명확히 낮다.
- 같은 샘플에서 global CER도 개선된다.
- first final latency와 RTF가 현재 UX를 해치지 않는다.
- peak memory가 장시간 회의에서 안전하다.
- 미지원 OS, 권한, 모델 오류에서 fallback이 확실하다.
- preview/final 상태가 흔들리지 않는다.
- 짧은 발화 누락률이 증가하지 않는다.
- 동일 조건에서 최소 2회 재실행해 큰 변동이 없다.

## 채택 판단표

| 후보 | 지금 역할 | 바로 default 가능 여부 | 다음 판단 기준 |
| --- | --- | --- | --- |
| WhisperKit turbo | 기본 fallback | 유지 | 전체 sample/meeting baseline 고정 |
| SpeechAnalyzer | macOS 26+ 1순위 후보 | 아직 보류 | 전체 CER, asset/locale fallback, final-only 안정성 |
| SFSpeech on-device | Apple-native 보조 후보 | 보류 | 긴 파일 안정성, 권한/asset 상태, 1분 제한 확인 |
| Silero VAD | VAD 후보 | 보류 | empty final 원인 분해 후 전체 CER 재측정 |
| Empty-only boundary repair | VAD chunk STT 보정 후보 | 보류 | repair telemetry 기반 guard 후보의 CER, empty final, false-positive, peak memory 재검증 |
| Nemotron MLX | 고정확도 연구 후보 | 불가 | peak memory, sidecar 안정성, 전체 CER 재현 |
| FluidAudio ASR | streaming/Swift 구조 참고 후보 | 불가 | 한국어 CER, RTF, memory, 실제 streaming 지표 |
| diarization | 회의록 UX 후보 | 불가 | speaker label 품질과 transcript 매칭 안정성 |

## 바로 다음 작업 순서

1. repair guard sweep은 일단 멈춘다. 후보 A/B는 prune하고, 후보 C는 정확도 개선 후보가 아니라 memory guard 후보로만 남긴다.
2. 제품 기본 후보는 no-guard empty-only repair가 아니라 feature-flagged empty-only repair다. 기본 off 제품 훅은 추가됐고, no-guard는 CER/empty 개선이 가장 뚜렷하지만 all7 full-duration에서 false-positive text와 peak memory가 증가했다.
3. 리소스 안전성을 우선하면 `min chunk=2.0초`, `min audio=-35dB` guard만 short3 full-duration으로 올린다. 이 후보는 3회 반복에서 peak memory를 낮췄지만 empty/RTF 이득이 명확하지 않으므로 default 승격 기준은 아니다.
4. 정확도 우선이면 guard 추가 반복보다 WhisperKit turbo final-only 전체 baseline, Apple 엔진 smoke 복구, high-overlap empty segment 원인 분해를 먼저 한다.
5. short3에서도 통과한 repair 후보만 제품 코드에 기본값이 아니라 feature flag와 안전 조건으로 붙인다. 현재 제품 훅은 붙었지만 default는 off다.
   - 첫 전사 결과가 empty일 때만 retry한다.
   - VAD speech chunk, 충분한 RMS, 충분한 chunk duration, retry 1회 제한 같은 조건을 둔다.
   - retry 결과가 비어 있거나 low confidence면 기존 preview/final 안정성 규칙을 유지한다.
6. probe matrix는 후보마다 최소 3회 반복하고, 단일 run의 empty/non-empty만으로 채택하지 않는다.
7. WhisperKit turbo window baseline도 `sample/meeting` 전체 duration으로 순차 실행해 VAD chunk STT와 final-only 기준선을 분리한다.
8. low VAD overlap empty row와 high VAD overlap empty row를 분리해 VAD miss와 WhisperKit decode failure를 따로 센다.
9. decode threshold 전역 완화는 g2와 non-speech probe까지 통과하기 전에는 적용하지 않는다.
10. true streaming은 `StreamingTranscriptionEngine`을 지원하는 엔진에만 적용하고, WhisperKit one-shot 경로는 기존 `SpeechTranscriptionEngine`으로 유지한다.
11. SFSpeech 권한/Dictation 상태를 복구한 뒤 같은 120초 runner로 다시 smoke를 돌린다.
12. macOS 26+ 환경에서 SpeechAnalyzer 한국어 asset 상태를 확인하고 같은 120초 runner로 smoke를 돌린다.
13. Apple 엔진 smoke가 통과한 환경에서 `sample/meeting` 전체를 WhisperKit turbo, SpeechAnalyzer, SFSpeech on-device 기준으로 안전한 동시성에서 다시 측정한다.
14. SpeechAnalyzer final-only 제품 gate를 UI/설정 상태와 연결한다.
15. correction/summary/export 종료 flow 회귀 테스트를 추가한다.
16. `StreamingTranscriptionEngine` protocol, `TranscriptionCoordinatorPlan`, hidden streaming runner/metric scaffold, `SpeechAnalyzerStreamingEngine` hidden PoC는 추가했다. 다음은 지원 환경에서 `RUN_SPEECH_ANALYZER_STREAMING_POC=1` smoke로 실제 event를 확인한다.
17. Nemotron MLX sidecar는 별도 worker로 benchmark만 붙이고, 앱 기본 엔진 후보와 분리한다.
18. diarization은 audio offset 보존 작업 이후 offline PoC로 시작한다.

## 당장 하지 않을 것

- Silero VAD를 바로 기본값으로 바꾸지 않는다.
- Nemotron을 앱 내부 Swift 엔진처럼 바로 붙이지 않는다.
- WhisperKit을 true streaming 엔진처럼 포장하지 않는다.
- LLM correction 결과를 CER 개선으로 보고하지 않는다.
- 60초 또는 120초 샘플만 보고 default를 바꾸지 않는다.
- 여러 무거운 모델을 무제한 병렬 실행하지 않는다.
- 유료 클라우드 STT를 기본 전제에 넣지 않는다.

## 최종 제품 방향

- macOS 26 이상: SpeechAnalyzer를 우선 후보로 제시하고, 실패하면 WhisperKit turbo fallback.
- macOS 14-25: WhisperKit turbo를 안정 기본값으로 유지하고, SFSpeech on-device는 선택지로 검증.
- 고정확도 실험 모드: Nemotron MLX sidecar를 사용자가 명시적으로 켤 수 있게 검토.
- 전사 이후: 원문 보존 + normalizer + 개인 OAuth LLM/로컬 LLM 회의록 정리.
- 장기 목표: true streaming 엔진이 충분히 정확해질 때만 session 기반 실시간 경로를 제품 기본 경험으로 승격.
