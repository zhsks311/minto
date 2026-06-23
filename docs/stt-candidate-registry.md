# 한국어 STT/화자분리 후보 레지스트리

> **성격**: 프로젝트가 선택지로 추적·관리하는 **살아있는 레지스트리**(스냅샷 아님). 새 후보·수치가 나오면 갱신한다.
> **최종 갱신**: 2026-06-23 · **최초 작성**: 2026-06-23
> **필터**: **한국어 지원** + **on-device(Apple Silicon) 우선**. 신규성은 항목별 출시일로 표기(초기 조사는 출시 6개월 이내=2025-12-23 이후 기준이었음).
> **방법**: 다중 소스 웹 검색 + 3표 적대적 검증(deep-research 하니스, 3개 라운드 누적). 한국어 지표는 **CER 우선**(WER만 있으면 비표준으로 라벨 — 아래 비교 주의).
> **맥락**: macOS 회의 기록 앱의 로컬-우선 한국어 STT/화자분리 후보 관리. 함께 볼 문서: `docs/stt-poc-summary.md`(우리가 실측한 CER 비교 표).
>
> 갱신 규칙: 신규 후보는 적절한 Tier/범주 표에 추가하고, 출처 섹션에 1차 링크를, "최종 갱신"을 함께 고친다.

## ⚠️ 비교 주의 (먼저 읽을 것)

- **한국어 ASR의 표준 지표는 CER(문자 오류율)다.** 한국어는 띄어쓰기가 모호해 어절 단위 WER이 불안정하므로 CER로 본다. 우리 `stt-poc-summary.md`도 전부 CER 기준이다.
- **이 문서의 외부 수치 상당수는 출처가 WER로 보고한 값**(예: Qwen3-ASR Fleurs-ko/CommonVoice-ko **WER**)이다. WER은 (1) 한국어 표준 지표가 아니고 (2) **우리 CER과 직접 비교 불가**다. WER→CER 임의 변환은 불가능하므로 **출처 지표를 그대로 라벨링**해 싣는다(보통 한국어는 CER < WER). 각 수치의 지표 표기를 확인할 것.
- 데이터셋·정규화·측정 윈도우도 출처마다 달라, 같은 CER이라도 회의 도메인 우리 값과 자릿수 비교 이상은 금물이다.
- 출시일·한국어 지원 여부는 검증을 통과한 항목만 실었으나, arXiv 등 연구 단계 출처는 **1차 코드/모델 공개와 별개로 실측 재현이 필요**하다.
- "on-device 가능"은 *CoreML/MLX 변환본 존재* 또는 *Apple Silicon 로컬 실행 명시*를 뜻하며, 우리 환경(회의 스트리밍, macOS 14+)에서의 **RTF·스트리밍 적합성은 별도 측정 대상**이다.

---

## TL;DR

1. **헤드라인: Qwen3-ASR(0.6B/1.7B)** — 6개월 이내(2026-01-29), 한국어 공식 지원, Apache-2.0, **CoreML 변환본 존재**, 그리고 **우리가 이미 쓰는 FluidAudio v0.15.4(2026-06-16)에 `Qwen3AsrManager`로 통합**됨 → 신규 의존성 없이 STT 엔진 후보로 평가 가능. 한국어 Fleurs WER 2.57%(1.7B, 원본).
2. **Raon-Speech-9B(KRAFTON), HyperCLOVA X 8B Omni(네이버)** — 한국어 성능 SOTA급이지만 **9B/8B 규모 + on-device 변환본 미확인** → 당장 로컬 후보 아님, 추적 대상.
3. **Parakeet TDT v2** — CoreML O, macOS 14+ O지만 **영어 전용 → 한국어 후보에서 제외**.
4. **moonshine-tiny-ko, Voxtral** — 적합/우수하나 **출시일이 6개월 윈도우 밖** → 참고만.
5. **클라우드 API** — 한국어 지원하나 이번 조사에서 6개월 이내 신규성·수치 검증이 불완전. 프로젝트 방침상 후순위.

---

## Tier 1 — on-device 한국어 후보 (6개월 이내, 실행 경로 있음)

### Qwen3-ASR (0.6B / 1.7B) — **최우선 후보**

| 항목 | 내용 |
|---|---|
| 출시일 | 2026-01-29 (GitHub README "released the Qwen3-ASR series") ✅ 6개월 이내 |
| 한국어 | 공식 지원 (52개 언어/방언 중 ko 포함) |
| 크기 | 0.6B, 1.7B 두 종 |
| 라이선스 | Apache-2.0 (오픈웨이트) |
| 한국어 성능 | Fleurs-ko **WER** 2.57%, CommonVoice-ko **WER** 5.88% (1.7B, arXiv 2601.21337) — ⚠️ **WER이라 한국어 표준 CER 아님·우리 CER과 비교 불가**. CER 별도 확인 필요 |
| on-device | **CoreML 변환본 공개**(`FluidInference/qwen3-asr-0.6b-coreml`). 변환 후 WER 2.11%→**4.4%** 저하(투명 공개) |
| 통합 | **FluidAudio v0.15.4(2026-06-16)에 `Qwen3AsrManager` API** — 우리가 이미 VAD/화자분리로 쓰는 의존성 |
| RTF | 미확인 (측정 필요) |

> **우리 프로젝트 의미 (코드 검증됨)**: `Package.swift`는 `FluidAudio from: "0.12.4"`로 선언, `Package.resolved`는 현재 **0.15.2** 고정. `Qwen3AsrManager`가 들어간 **0.15.4는 기존 `from:` 제약 안** → **새 패키지 없이 마이너 bump(0.15.2→0.15.4+)만으로** Qwen3-ASR 엔진 API 확보. CoreML 변환본 배포 org(`FluidInference`)도 우리 FluidAudio와 **동일 조직**이라 정합성 높음. 신규 dependency·ADR 트리거 없음(엔진 추가는 `STTService` 파사드 경계만 확인). 단 CoreML 정확도 저하(4.4%)·스트리밍 적합성·RTF는 직접 측정 필요.

### speech-swift (툴킷)

| 항목 | 내용 |
|---|---|
| 공개 | 2026-02-04 (repo), 최신 v0.0.21(2026-06-17) ✅ |
| 내용 | Apple Silicon에서 **Qwen3-ASR 0.6B/1.7B, Parakeet TDT 0.6B, Parakeet EOU 120M, Nemotron Streaming 0.6B, Omnilingual ASR** 을 MLX Swift/CoreML로 로컬 실행. "no cloud, no API keys" |
| 한국어 | Qwen3-ASR 경유로 지원 |
| 라이선스 | 오픈소스(repo) |
| ⚠️ 제약 | **macOS 15+(Sequoia) 또는 iOS 18+ 요구** → 우리 CLAUDE.md의 **macOS 14+ 지원 기준과 충돌**. 채택 시 최소 OS 상향 결정 필요 |

> **의미**: 직접 채택보다는 *Qwen3-ASR/Nemotron의 Swift 통합 레퍼런스*로 가치가 크다. macOS 15 요건 때문에 그대로 의존하긴 어렵다.

---

## Tier 2 — 강한 한국어 성능, on-device 경로 미확인 (추적 대상)

### KRAFTON Raon-Speech-9B

| 항목 | 내용 |
|---|---|
| 공개 | 2026-04 (arXiv 2605.23912, 2026-04-08) ✅ 6개월 이내 |
| 한국어 | 영어-한국어 바이링궐 SpeechLM |
| 크기 | **9B** |
| 한국어 성능 | 42개 EN/KO 벤치마크(KVoiceBench, KOpenAudioBench, KMMAU 등)에서 한국어 ASR 최고 CER 주장 |
| on-device | **미확인**(CoreML/MLX/ONNX/GGUF 변환 출처 없음). 9B는 Apple Silicon 메모리 제약 큼 |

### 네이버 HyperCLOVA X 8B Omni

| 항목 | 내용 |
|---|---|
| 공개 | 2026-01 (arXiv 2601.01792, 2026-01-05) ✅ 6개월 이내 |
| 한국어 | 한국어-영어 (omnimodal: 텍스트+오디오+비전 입출력) |
| 크기 | 8B(활성) / 파일명세 11B 표기 |
| 한국어 성능 | KsponSpeech, Fleurs-ko SOTA WER 주장 |
| on-device | **미확인**. 전용 ASR 엔진이 아니라 **omnimodal 통합 모델**(STT 단독 용도엔 과함) |

> **의미**: 둘 다 "한국어를 제일 잘 한다"는 신호는 강하지만, 회의 앱의 로컬-우선·경량 STT 요건과는 거리가 있다. 추후 MLX/GGUF 포팅이 나오면 재평가.

---

## 엔진/툴킷 버전 업데이트 (모델 아닌 인프라)

- **WhisperKit v1.0.0** — 2026-05-01 출시(GitHub releases API 확인). 우리가 현재 쓰는 엔진의 메이저 버전. 한국어는 기반 Whisper 모델 차원에서 지원(99개 언어). **업그레이드 검토 가치** 있음(현재 우리 버전과 격차 확인 필요).
- **FluidAudio v0.15.4** — 2026-06-16, `Qwen3AsrManager` 추가(위 Qwen3-ASR 항목 참조).

---

## argmax 생태계 · Parakeet 패밀리 심층 (2026-06-23 추가)

> 조사 대상: SpeakerKit / NVIDIA Parakeet 전체 변종 / argmax-oss-swift. 검증: 10 주장 확정. **주의: 조사 중 인증(401) 끊김으로 Parakeet 관련 다수 주장이 *기각이 아닌 기권(abstain)* 처리됨** → 한국어 지원은 별도 WebSearch로 직접 재확인함(아래 표기).

### argmax-oss-swift — argmax 오픈소스 Swift SDK (신규·중요)

| 항목 | 내용 |
|---|---|
| 정체 | argmax(WhisperKit 제작사)가 **3개 키트를 묶은 단일 Swift Package** |
| 구성 | **WhisperKit**(STT/Whisper) · **SpeakerKit**(화자분리/Pyannote v4) · **TTSKit**(TTS/Qwen-TTS) |
| 라이선스 | **MIT** (서드파티 컴포넌트는 `NOTICES` 별도 조건) |
| on-device | 3종 모두 **서버 불필요, Apple Silicon 온디바이스** |
| SPM | 개별 product 선택 또는 `ArgmaxOSS` 우산 product |
| 한국어 | **TTSKit만** 한국어 명시(10개 언어). WhisperKit STT·SpeakerKit 화자분리의 한국어는 README에 명시 없음(STT는 Whisper 기반이라 지원, 화자분리는 언어 무관 — 아래) |

> **우리 프로젝트 의미**: 우리는 이미 WhisperKit(STT) + FluidAudio(화자분리)를 쓴다. argmax-oss-swift는 **"WhisperKit + SpeakerKit"를 한 벤더로 묶는** 대안 — 화자분리를 FluidAudio에서 argmax SpeakerKit으로 바꾸는 선택지가 생겼다는 뜻. 단 STT(WhisperKit)는 이미 동일 계보라 새로움 없음.

### SpeakerKit — argmax 화자분리 (오픈소스化됨)

| 항목 | 내용 |
|---|---|
| 정체 | Pyannote v4 기반 화자분리. **"상용 전용"은 기각**(0-3) — 현재 argmax-oss-swift에 MIT로 포함 |
| on-device | iOS 16 / macOS 13+ (블로그 기준), Apple Silicon |
| 통합 | WhisperKit과 결합 시 **화자 구분 전사문(diarized transcript)** 생성, 독립 사용도 가능 |
| 한국어 | 명시 없음. **단 화자분리는 음향 임베딩(목소리 특성) 기반이라 언어 비의존적** — "한국어 표기 없음 ≠ 한국어 안 됨". 우리 회의 한국어 음성으로 DER 직접 측정이 판단 기준 |
| vs 우리 FluidAudio | **둘 다 Pyannote 계보 + ANE/CoreML 온디바이스**. FluidAudio는 Pyannote offline + LS-EEND·Sortformer(온라인) 파이프라인까지 보유. 교체 이득은 DER·실시간성 실측으로만 판가름 |

### NVIDIA Parakeet 패밀리 — 한국어의 역설

| 변종 | 한국어 | on-device(Apple) | 비고 |
|---|:---:|:---:|---|
| Parakeet TDT 0.6B **v2** | ❌ 영어 전용 | ✅ CoreML/MLX 포트 | FluidInference·senstella·mweinbach 포트 존재 |
| Parakeet TDT 0.6B **v3** | ❌ (25개 **유럽어**, ko 없음 — 검증 3-0) | ✅ CoreML/MLX 포트 | v2→다국어 확장이나 한국어 미포함 |
| Parakeet **RNNT 1.1B multilingual** | ✅ **한국어 포함 25개 언어** (RIVA 모델카드, WebSearch 재확인) | ❌ **NVIDIA RIVA/NIM(GPU) 전용** | FastConformer-RNNT, 90K+시간. Apple Silicon 포트 없음 |

> **핵심 결론**: **"한국어 되는 Parakeet"(RNNT-1.1B)와 "맥에서 도는 Parakeet"(TDT v2/v3 CoreML·MLX 포트)의 교집합이 현재 0**이다. 한국어 회의 STT 용도로 Parakeet는 **현 시점 on-device 후보에서 제외**. (TDT 포트들은 영어/유럽어 회의용으로만 유효)

> **Apple Silicon Parakeet 포트 메모**(영어/유럽어용): `FluidInference/parakeet-tdt-0.6b-v3-coreml`(CoreML, **macOS 14+/iOS 17+, ANE/CPU**, Apache-2.0, 0.6B, ~110× RTF on M4 Pro, 25개 유럽어·**한국어 없음**), `parakeet-tdt-0.6b-v2-coreml`(영어), `senstella/parakeet-mlx`(MLX, Apache-2.0, TDT/RNNT/CTC, 청크 120초), `mweinbach/parakeet-coreml-swift`(v3 CoreML).

### Apple Silicon on-device 실측 RTF·메모리 (vendor 벤치마크)

> 출처: soniqo.audio/benchmarks (**M5 Pro / 48GB / macOS 25.5**). ⚠️ **WER 열은 vendor 자체 측정 + 거의 확실히 영어** — 한국어 품질로 읽지 말 것. **RTF·메모리만** on-device 실현성 근거로 사용.

| 모델 | 양자화 | RTF | 속도배수 | 메모리 | WER(영어·vendor) |
|---|---|---:|---:|---:|---:|
| Qwen3-ASR 0.6B | 8-bit | 0.015 | 66× | 1.3GB | 1.82% |
| Qwen3-ASR 1.7B | 5-bit | 0.027 | 36× | 1.92GB | 1.32% |
| Parakeet TDT v3 | INT8 | 0.009 | 117× | 0.9GB | 2.37% |
| WhisperKit Large-v3 | FP16 | 0.084 | 12× | 0.4GB | 1.71% |

> **읽는 법**: Qwen3-ASR 0.6B(RTF 0.015 = 1분 음성을 ~1초에)·메모리 1.3GB로 **실시간 회의 전사에 충분히 빠르다**. 단 메모리는 WhisperKit(0.4GB)보다 크다. 우리 한국어 회의 CER·스트리밍 안정성은 여전히 직접 측정 대상(이 표는 속도/메모리 근거일 뿐).

---

## 화자분리: SpeakerKit vs FluidAudio — 공개 DER + PoC 실현성 (2026-06-23)

### argmax 공개 DER (SDBench/OpenBench, AMI)

| 시스템 | AMI-IHM DER | AMI-SDM DER | 속도(SDM) |
|---|---:|---:|---:|
| pyannoteAI (상용) | 0.16 | 0.18 | 62× |
| **Argmax SpeakerKit** | **0.18** | **0.21** | **458×** |
| pyannote-3.1 (OSS) | 0.19 | 0.23 | 54× |
| Deepgram | 0.35 | 0.42 | 241× |
| AWS Transcribe | 0.29 | 0.37 | 10× |

> SpeakerKit은 pyannote-3.1과 **거의 동급 정확도에 ~8.5배 빠르다**(argmax 자체 벤치이나 SDBench는 오픈·재현 가능). 상용 pyannoteAI가 정확도 1위.

### ⚠️ 우리 FluidAudio 12.0%와 직접 비교 금지

우리 `docs/benchmark/2026-06-22-lseend-vs-vbx-count.md`의 FluidAudio/VBx AMI DER은 **12.0%**(full 16-meeting 10.62%)인데, 위 argmax 표는 같은 AMI-SDM에서 pyannote-3.1을 **23%**로 잰다. 이 격차는 품질차가 아니라 **DER 채점 방법론 차이**(collar 관용구간·overlap 채점 여부·AMI 서브셋)다 — CER 비교 때와 같은 함정. **우리 12%와 SpeakerKit 21%를 우열로 읽으면 틀린다.** FluidAudio offline 자체가 pyannote 계보라 동일 방법론이면 둘은 **같은 정확도 급**이고, 실질 차별점은 **속도·통합·라이선스**다.

### DER PoC 실현성 — 블로커 2개

기존 자산 조사(`SpeakerDiarizationProvider` 프로토콜·eval runner 존재) 결과, **연결은 싸지만 직접 DER 비교엔 2개 블로커가 있다**:

1. **정답 라벨 부재(측정 블로커)**: 한국어 코퍼스에 **RTTM 정답이 없다**. 기존 `DiarizationQualityMetrics`는 DER 공식이 없고 커버리지·overlap·화자수만 계산. → **한국어 직접 DER 산출 불가**. (현재 화자수 정답도 파일명 기반 추정)
2. **새 의존성(거버넌스 블로커)**: SpeakerKit = `argmax-oss-swift` 추가 = CLAUDE.md "ADR 필요 조건" 1번(새 외부 dependency) → **ADR + 다중관점 리뷰 선행**.

### 연결 비용 (조사 결과 — 블로커 해소 후)

- 추가 1: `Sources/Minto/Services/Diarization/SpeakerKitDiarizationProvider.swift`(`SpeakerDiarizationProvider` conform)
- 추가 2: `DiarizationEvalRunnerTests.swift`의 engine 분기에 `"speakerkit"` 케이스 1줄
- 재사용: `TranscriptSpeakerMatcher`·`DiarizationQualityMetrics`·게이트·출력 포맷 그대로
- 제품 경로 연결 시: `MeetingFileImportUseCase.swift:379`가 FluidAudio를 **직접 생성**하므로 이 지점도 변경 필요(eval만이면 불필요)

### 권장 경로 (택1)

| 옵션 | 내용 | 의존성 | 라벨 | 결과물 |
|---|---|:---:|:---:|---|
| A. 공개수치 채택 | argmax SDBench 수치 + 우리 AMI proxy를 **동일 방법론 주석과 함께** 참고 | 0 | 0 | 즉시 (이 문서) |
| B. 화자수·커버리지 비교 | SpeakerKit 끼워 기존 하니스로 한국어 **화자수 정확도·overlap** 비교(DER 아님) | ADR 필요 | 0 | PoC |
| C. 한국어 직접 DER | 샘플 N개 **RTTM 수동 라벨링** + DER 계산 추가 + 양 provider 측정 | ADR 필요 | 라벨링 선행 | 본measurement |

> **추천**: 당장은 **A**로 충분(SpeakerKit≈pyannote급·초고속, FluidAudio와 동급 정확도 추정). **B/C는 화자분리 교체를 실제로 의사결정할 때** ADR과 함께 착수. 교체 트리거가 "속도"면 SpeakerKit 458×가 매력적이나, 우리 FluidAudio도 ANE라 실측 RTF부터 비교해야 한다.

---

## 추가 발굴 도구 (2026-06-23) — 범주별

> 앞서 다룬 것(Qwen3-ASR·Parakeet·WhisperKit·SpeakerKit·FluidAudio·moonshine·Raon·HyperCLOVA·Voxtral·클라우드 일부) 외 추가 발굴. 한국어·on-device 렌즈 유지.

### C. on-device 런타임/프레임워크 (실용 1순위)

| 도구 | 종류 | 한국어 | on-device | 비고 |
|---|---|---|---|---|
| **mlx-audio-swift** (Blaizzy) | Swift SPM + MLX 런타임 | 모델별(Qwen3-ASR=O) | ✅ Apple Silicon M1+, macOS 14+/iOS 17+ | **Qwen3-ASR·Parakeet·Voxtral·Whisper·Nemotron**을 한 패키지로. WhisperKit/FluidAudio 외 제3의 통합 경로. 활발히 유지(2026-06) |
| **sherpa-onnx** (k2-fsa) | ONNX 런타임 + 모델 | ✅ **KsponSpeech Zipformer 2종**(스트리밍/오프라인) | ✅ macOS/iOS Swift API (ONNX/CPU, ANE 없음) | STT+**화자분리 동시 지원**. 한국어 on-device를 한 곳에서. 단 KsponSpeech 기반→회의·자유발화 CER 별도 측정 필요 |
| **whisper.cpp** (ggml) | GGML 런타임 | Whisper 기반 | ✅ Apple Silicon 일급, CoreML **인코더 ANE 3×+** | 디코더는 ANE 이점 없음. medium/large CoreML 변환 비용 큼(40분+/60GB+). 공식 SPM·전체 GPU 추론 클레임은 기각 |

> **의미**: 우리는 WhisperKit(STT)+FluidAudio(VAD/화자분리)에 고정돼 있지만, **mlx-audio-swift는 Qwen3-ASR을 MLX로 직접 돌리는 대안 경로**다(FluidAudio CoreML 경로와 별개). sherpa-onnx는 한국어 스트리밍 STT+화자분리를 단일 의존성으로 제공해 검토 가치가 있다(과거 stt-poc-summary의 sherpa 레이턴시 실험과 연결).

### A. Apple 네이티브 — SpeechTranscriber / SpeechAnalyzer (macOS 26)

- **정체**: macOS 26/iOS 26 신규 on-device 전용 API(SFSpeechRecognizer 대체). **장형식·원거리 오디오(회의·강의) 최적화**, 앱 다운로드/메모리 크기 안 늘림(시스템 저장), watchOS 제외 전 플랫폼.
- **한국어**: 공개 문서엔 지원 언어가 **시각 자료로만** 제시돼 텍스트 출처 없음(미확인). **단 우리 `docs/stt-poc-summary.md`가 SpeechAnalyzer로 ko-KR을 이미 측정**(120s 회의 CER 12.3%, 7샘플 weighted 16.1% — 우리 측정 중 최고). → **한국어 작동은 자체 검증됨**. WER/CER 공식 수치는 미공개.
- **의미**: 이미 우리 PoC의 1순위 통합 후보(`stt-poc-summary.md` "Current decision"). 이 라운드는 그 API의 정체·특성을 외부 출처로 보강.

### E. 화자분리 대안 (FluidAudio 외)

| 도구 | 한국어 | on-device | DER / 비고 |
|---|---|---|---|
| **speakrs** (avencera, 2026-03) | 언어무관(음향) | ✅ **CoreML** | DER **7.1%**(collar=0)·**529× realtime**(M4 Pro), pyannote 동급·~22× 빠름. **self-report·독립재현 없음**. FluidAudio의 Apple Silicon 특화 대안 |
| sherpa-onnx diarization | 언어무관 | ✅ ONNX | 위 sherpa 항목과 동일 패키지 |
| NVIDIA Sortformer streaming (diar_streaming_sortformer_4spk-v2) | 언어무관 | △ (우리 diar-eval 워크트리에 PoC 존재) | 4화자 상한, 스트리밍. 우리 AMI proxy DER 34.3%(앞 측정) |
| 3D-Speaker (modelscope) | 언어무관 | ONNX 변환 가능성 | 화자임베딩/분리 툴킷 |

> speakrs는 collar=0ms 기준(일반 0.25s보다 엄격)이라 7.1%를 SpeakerKit 21%(AMI-SDM)·우리 12%와 직접 비교 불가 — **데이터셋·collar이 모두 다르다**.

### D. 한국어 특화 모델/서비스

- **seastar105/Korean-Whisper** 컬렉션: tiny/base(72.6M)/small(0.2B)/medium(0.8B) 한국어 파인튜닝 Whisper(komixv2), 2025-03·2026-03 업데이트. **공개 CER/WER 미기재(검증 기각)**. WhisperKit/whisper.cpp와 결합하려면 CoreML/GGML 변환 필요. Zeroth 기반 파인튜닝은 깨끗한 낭독체→회의 도메인과 거리.
- **클라우드 한국어 STT**(리턴제로 Sommers·네이버 Clova Speech·ETRI·카카오·SaltLux): **on-device 아님 → 로컬-우선 방침상 범위 밖**. 리턴제로 리더보드(`rtzr/Awesome-Korean-Speech-Recognition`)는 한국어 STT 비교 참고처이나 구체 수치는 이번 검증에서 확정 못 함.

### B. 신규 오픈 ASR — 한국어 미지원(현 스택 부적합)

| 모델 | 한국어 | 비고 |
|---|---|---|
| NVIDIA Canary-1b-v2 | ❌ 25개 유럽어 | GPU 전용, CoreML/MLX 없음 |
| NVIDIA Canary-Qwen-2.5B (2025-07) | ❌ 영어 | |
| Kyutai STT/Moshi | ❌ en/fr만 | |
| Microsoft Phi-4-multimodal | ❌ 공식 8개 언어(한국어 제외) | base Zeroth CER **99.16%**(사실상 불가). 커뮤니티 파인튜닝으로 CER 1.61% 사례는 있음 |

---

## 제외/참고 (조건 미충족 — 합치지 말 것)

| 모델 | on-device | 한국어 | 6개월 이내 | 사유 |
|---|:---:|:---:|:---:|---|
| Parakeet TDT 0.6B v2 | ✅ (CoreML, macOS 14+) | ❌ 영어 전용 | ✅ | **한국어 미지원**으로 제외 |
| moonshine-tiny-ko (27M) | △ ONNX 가능성(미확정) | ✅ 한국어 전용 | ❌ 2025-09 | 날짜 밖. 단 Fleurs CER **8.9%**(Whisper Tiny 15.83% 대비 우수) — 엣지용 참고 가치 큼 |
| Voxtral (Mistral) | △ | ❌ 한국어 미포함(검증 기각) | ❌ 2025-07 | 날짜·한국어 모두 부적합 |

---

## 클라우드 API (별도 카테고리 — 데이터 불완전, 후순위)

> 프로젝트 방침: 유료 클라우드 STT는 이번 라운드 out of scope(`stt-poc-summary.md`). 아래는 조사에서 스친 언급이며 **한국어 수치·6개월 신규성 검증은 미완**이다.

- **Microsoft MAI-Transcribe-1** (Azure AI Foundry, 신규 언급) — 출처 신뢰도 낮음, 한국어/수치 미확인.
- **Deepgram Nova-3 multilingual** — 다국어 WER 개선 블로그. 한국어 별도 수치 미확인.
- **OpenAI gpt-4o-transcribe, Google Cloud STT, Azure STT** — 한국어 지원 알려져 있으나 이번 합성에 검증된 클레임 없음.

→ 필요 시 클라우드 API만 별도 조사 라운드 권장.

---

## 벤치마크 참고 자료

- **KoALa-Bench** (arXiv 2604.19782) — 한국어 Large Audio Language Model 평가 벤치마크. Qwen3-Omni, Gemma-3n, GPT-audio, Gemini-flash 등 6개 모델 평가. 한국어 후보 모델 횡비교 자료로 활용 가능(단 on-device 평가는 아님).
- **rtzr/Awesome-Korean-Speech-Recognition** (리턴제로 큐레이션) — 한국어 ASR 모델·벤치마크 목록 추적용.

---

## 우리 프로젝트 적용 관점 (다음 액션 후보)

1. **Qwen3-ASR을 STT 엔진 후보로 실측**: FluidAudio `Qwen3AsrManager`로 0.6B CoreML을 우리 `sample/meeting/raw/*` 120초 윈도우에 돌려 **우리 기준 CER·RTF·스트리밍 안정성**을 `stt-poc-summary.md` 표에 동일 조건으로 추가. (신규 의존성 없음 → ADR 불필요 가능성 높음, 단 엔진 추가는 `STTService` 파사드 경계 확인)
2. **WhisperKit 현재 버전 ↔ v1.0.0 격차 확인**: 메이저 업이라 API/모델 호환성·한국어 품질 변화 점검.
3. **macOS 최소 버전 정책 재확인**: speech-swift류(macOS 15+) 채택은 CLAUDE.md의 macOS 14+ 기준과 충돌 — 정책 결정 사항.
4. **Tier 2(9B/8B)는 보류**: on-device 경로 생기면 재평가.

## 미해결 질문

- Qwen3-ASR CoreML의 Apple M-시리즈 실측 RTF·**스트리밍(청크) 지원 여부** — 회의 실시간 프리뷰에 쓸 수 있는가?
- moonshine-tiny-ko의 공식 CoreML/ONNX 변환본 제공 여부 (엣지용 초경량 대안)
- Raon-9B / HyperCLOVA-8B의 MLX/GGUF 포팅 계획
- 2026 상반기 리턴제로·카카오·삼성 등 국내 신규 오픈웨이트 한국어 ASR 추가 공개분

## 출처 (1차 우선)

**라운드 1 — 신규 STT 모델**
- Qwen3-ASR: https://github.com/QwenLM/Qwen3-ASR · https://huggingface.co/FluidInference/qwen3-asr-0.6b-coreml · arXiv 2601.21337
- speech-swift: https://github.com/soniqo/speech-swift
- WhisperKit: https://github.com/argmaxinc/WhisperKit
- Parakeet TDT v2 CoreML: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml
- moonshine-tiny-ko: https://huggingface.co/UsefulSensors/moonshine-tiny-ko · arXiv 2509.02523
- Raon-Speech-9B: https://huggingface.co/KRAFTON/Raon-Speech-9B · arXiv 2605.23912
- HyperCLOVA X 8B Omni: https://huggingface.co/naver-hyperclovax/HyperCLOVAX-SEED-Omni-8B · arXiv 2601.01792
- KoALa-Bench: arXiv 2604.19782
- 한국어 ASR 목록: https://rtzr.github.io/Awesome-Korean-Speech-Recognition/

**라운드 2 — argmax 생태계 · Parakeet 패밀리 · 화자분리 DER**
- argmax-oss-swift: https://github.com/argmaxinc/argmax-oss-swift · https://swiftpackageindex.com/argmaxinc/argmax-oss-swift
- SpeakerKit: https://www.argmaxinc.com/blog/speakerkit · https://www.argmaxinc.com/blog/pyannote-argmax
- SDBench/OpenBench(DER 수치): https://github.com/argmaxinc/OpenBench/blob/main/BENCHMARKS.md · arXiv 2507.16136
- Parakeet TDT v3: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 · https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml
- Parakeet RNNT 1.1B multilingual(한국어 포함): https://build.nvidia.com/nvidia/parakeet-1_1b-rnnt-multilingual-asr/modelcard
- Parakeet MLX 포트: https://github.com/senstella/parakeet-mlx · https://github.com/mweinbach/parakeet-coreml-swift
- Apple Silicon RTF 벤치: https://soniqo.audio/benchmarks

**라운드 3 — 추가 발굴 도구**
- mlx-audio-swift: https://github.com/Blaizzy/mlx-audio-swift
- sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx · 한국어 Zipformer: https://huggingface.co/k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16 · https://huggingface.co/k2-fsa/sherpa-onnx-zipformer-korean-2024-06-24 · 화자분리: https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/index.html
- whisper.cpp: https://github.com/ggml-org/whisper.cpp
- Apple SpeechAnalyzer/SpeechTranscriber: https://developer.apple.com/videos/play/wwdc2025/277/ · https://developer.apple.com/documentation/speech/speechanalyzer
- speakrs: https://github.com/avencera/speakrs
- 3D-Speaker: https://github.com/modelscope/3D-Speaker · NVIDIA Sortformer: https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2
- seastar105 Korean-Whisper: https://huggingface.co/collections/seastar105/korean-whisper
- Canary-1b-v2: https://huggingface.co/nvidia/canary-1b-v2 · Kyutai STT: https://kyutai.org/stt · Phi-4-multimodal: https://huggingface.co/microsoft/Phi-4-multimodal-instruct
