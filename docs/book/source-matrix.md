# Minto2 음성 AI 책 출처 매트릭스

조회일: 2026-06-26 (KST)

이 문서는 `docs/book/minto2-speech-ai-study-book.md`의 근거 목록이다. 책 본문은 쉬운 설명을 우선하지만, 주요 기술 주장과 비교표는 이 매트릭스의 출처를 따라가야 한다.

## 검증 원칙

- 1차 출처 우선순위: 공식 문서 / 공식 repo / 논문 / 모델 카드.
- 벤더 벤치마크는 "vendor/self-reported"로 표시한다.
- CER, WER, DER, RTF는 서로 다른 지표다. 수치 비교에는 데이터셋, 언어, 하드웨어, 평가 프로토콜을 같이 적는다.
- Apple 문서는 JavaScript 게이트가 있어 페이지 본문이 안 보일 수 있다. OS availability는 Xcode SDK 헤더 또는 실제 빌드 환경으로 재확인한다.
- Core ML, coremltools, MLX, ONNX Runtime은 같은 계층이 아니다.

## 프로젝트 로컬 출처

| ID | 범위 | 파일 | 책에서 쓰는 주장 | 확인 상태 |
|---|---|---|---|---|
| P01 | 앱 목적 | `docs/service-definition.md` | Minto2는 회의 전사, 교정, 요약, 검색, 문서 연결을 목표로 한다. | 확인 |
| P02 | 사용자 흐름 | `docs/service-definition.md` | 회의 시작 시 주제, 용어, 참고 문서를 입력하고 전사/화자 라벨/요약으로 이어진다. | 확인 |
| P03 | 현재 기능 | `docs/service-definition.md` | WhisperKit/Apple STT, VAD, 화자분리, LLM 교정/요약, 검색/embedding, export가 현재 기술 표면이다. | 확인 |
| P04 | 데이터 원칙 | `docs/service-definition.md` | 원본 전사, 교정 전사, 요약, export 결과를 구분하고 CER 측정과 읽기용 정규화를 분리한다. | 확인 |
| P05 | 후보 기술 | `docs/stt-candidate-registry.md` | 한국어 STT/화자분리 후보는 한국어 지원과 Apple Silicon on-device 가능성을 우선한다. | 확인 |
| P06 | 지표 주의 | `docs/stt-candidate-registry.md` | 한국어 ASR은 CER 중심으로 보고, WER과 직접 비교하지 않는다. | 확인 |
| P07 | 후보 기술 | `docs/stt-candidate-registry.md` | Qwen3-ASR, sherpa-onnx, MLX, SpeakerKit, Parakeet, whisper.cpp 등은 후보 기술로 다룬다. | 확인 |
| P08 | 아키텍처 경계 | `docs/service-definition.md` | Domain/Core, Application/Use-case, Infrastructure/Adapter, UI 경계를 분리한다. | 확인 |
| P09 | humanize | 작성 워크플로 규칙 | 윤문은 factual draft 이후 적용하고, 기술 의미가 바뀌지 않는지 재검토한다. | 확인 |

## 웹 1차 출처

| ID | 범위 | 출처 | 확인한 사실 | 책에서 쓰는 위치 | stale risk |
|---|---|---|---|---|---|
| W01 | Whisper 논문 | https://arxiv.org/abs/2212.04356 | Whisper는 대규모 다국어/멀티태스크 약지도 학습 기반 ASR 연구다. | STT 기본 원리, WhisperKit 장 | 낮음 |
| W02 | Whisper repo | https://github.com/openai/whisper | Whisper는 multilingual speech recognition, translation, language identification 등을 수행하는 general-purpose speech recognition model로 설명된다. | Whisper 계열 설명 | 중간 |
| W03 | Argmax OSS / WhisperKit | https://github.com/argmaxinc/argmax-oss-swift | Argmax OSS Swift는 Apple Silicon on-device speech AI SDK 계열이며 WhisperKit/SpeakerKit/TTSKit 맥락을 확인한다. | on-device STT/diarization 후보 | 중간 |
| W04 | Apple Speech | https://developer.apple.com/documentation/speech | Apple Speech 문서는 JS가 필요하므로 페이지 존재만 확인했다. API availability는 SDK로 재확인해야 한다. | Apple STT 주의 | 높음 |
| W05 | Apple Core ML | https://developer.apple.com/documentation/coreml | Core ML 문서는 JS가 필요하므로 페이지 존재만 확인했다. 세부 API는 SDK/공식 문서 재확인 대상이다. | macOS 시스템 설계 | 높음 |
| W06 | MLX Swift | https://github.com/ml-explore/mlx-swift | MLX Swift는 Apple silicon용 MLX의 Swift API이며 연구/실험과 Swift 앱 통합 경로로 볼 수 있다. | 다음 기술 선택 기준 | 중간 |
| W07 | ONNX Runtime | https://onnxruntime.ai/docs/ | ONNX Runtime은 여러 언어와 mobile/on-device deployment 문서를 제공하는 범용 추론 런타임이다. | 다음 기술 선택 기준 | 중간 |
| W08 | Silero VAD | https://github.com/snakers4/silero-vad | Silero VAD는 pre-trained VAD 프로젝트다. | VAD 장 | 중간 |
| W09 | Qwen3-ASR repo | https://github.com/QwenLM/Qwen3-ASR | Qwen3-ASR은 0.6B/1.7B ASR 모델, 52개 언어/방언 지원, offline/streaming inference를 내세운다. | 다음 기술 선택 기준 | 높음 |
| W10 | Qwen3-ASR report | https://arxiv.org/abs/2601.21337 | Qwen3-ASR 기술 보고서. 최신 모델카드와 함께 확인해야 한다. | 다음 기술 선택 기준 | 높음 |
| W11 | sherpa-onnx | https://github.com/k2-fsa/sherpa-onnx | sherpa-onnx는 STT, TTS, diarization, VAD 등을 ONNX Runtime 기반으로 제공한다고 설명한다. | 다음 기술 선택 기준 | 중간 |
| W12 | pyannote.audio | https://github.com/pyannote/pyannote-audio | pyannote.audio는 speaker diarization용 neural building blocks와 pipeline 계열을 제공한다. | 화자분리 장 | 중간 |
| W13 | EEND 논문 | https://arxiv.org/abs/2003.02966 | EEND는 speaker diarization을 multi-label classification으로 재구성하고 overlap 처리를 강조한다. | EEND/화자분리 장 | 낮음 |
| W14 | LS-EEND 논문 | https://arxiv.org/abs/2410.06670 | LS-EEND는 long-form streaming EEND와 online attractor extraction을 다룬다. | 라이브 화자분리 장 | 중간 |
| W15 | VBx 논문 | https://arxiv.org/abs/2012.14952 | VBx는 x-vector sequence에 대한 Bayesian HMM clustering 방식이다. | 저장 시 확정/클러스터링 장 | 낮음 |
| W16 | VBx repo | https://github.com/BUTSpeechFIT/VBx | VBx 구현 repo다. 논문과 함께 확인한다. | 저장 시 확정/클러스터링 장 | 중간 |
| W17 | RAG 논문 | https://arxiv.org/abs/2005.11401 | RAG는 parametric memory와 dense vector index 기반 non-parametric memory를 결합한다. | 검색/RAG 장 | 낮음 |
| W18 | OpenAI embeddings | https://developers.openai.com/api/docs/guides/embeddings | embedding API와 벡터화 개념을 확인한다. | 검색/RAG 장 | 높음 |
| W19 | OpenAI retrieval | https://developers.openai.com/api/docs/guides/retrieval | file search/retrieval 개념과 도구 문서를 확인한다. | 검색/RAG 장 | 높음 |
| W20 | OpenAI text generation | https://developers.openai.com/api/docs/guides/text | text generation API 표면을 확인한다. | LLM 교정/요약 장 | 높음 |
| W21 | mlx-audio-swift | https://github.com/Blaizzy/mlx-audio-swift | Apple Silicon용 MLX 기반 Swift audio SDK이며 STT, TTS, VAD/diarization module을 제공한다고 설명한다. | 다음 기술 선택 기준 | 높음 |
| W22 | speakrs | https://github.com/avencera/speakrs | Rust 기반 speaker diarization 프로젝트이며 Apple Silicon/CUDA 실시간 배속과 pyannote급 정확도를 주장한다. | 다음 기술 선택 기준 | 높음 |
| W23 | Raon-Speech | https://arxiv.org/abs/2605.23912 | Raon-Speech 기술 보고서. 한국어/영어 speech model 후보로, 공개 artifact와 on-device 경로는 별도 확인해야 한다. | 다음 기술 선택 기준 | 높음 |
| W24 | HyperCLOVA X 8B Omni | https://arxiv.org/abs/2601.01792 | NAVER의 text/audio/vision 입출력 omnimodal model 기술 보고서로, 한국어와 영어 평가를 포함한다. | 다음 기술 선택 기준 | 높음 |

## 장별 근거 배치

| 장 | 라벨 | 주요 로컬 출처 | 주요 웹 출처 |
|---|---|---|---|
| 1. 프로젝트 개요 | 프로젝트 로컬 | P01, P02, P03, P04 | 없음 |
| 2. 소리에서 텍스트까지 | 프로젝트 로컬 + 외부 검증 | P02, P03 | W08 |
| 3. STT/ASR 기본 원리 | 외부 검증 | P06 | W01, W02, W09 |
| 4. Minto2 STT 후보 | 프로젝트 로컬 + 후보 기술 | P05, P06, P07 | W01, W02, W03, W04, W09, W10, W11 |
| 5. VAD와 chunking | 프로젝트 로컬 + 외부 검증 | P03 | W08 |
| 6. 화자분리 | 프로젝트 로컬 + 외부 검증 | P03, P07 | W12, W13, W14, W15, W16 |
| 7. 보이스프린트 | 프로젝트 로컬 | P03 | W12 |
| 8. 교정과 요약 | 프로젝트 로컬 + 외부 검증 | P03, P08 | W20 |
| 9. 검색과 답변 | 프로젝트 로컬 + 외부 검증 | P03, P08 | W17, W18, W19 |
| 10. macOS 시스템 설계 | 프로젝트 로컬 + 외부 검증 | P01, P08 | W04, W05 |
| 11. 다음 기술을 고를 때 보는 기준 | 후보 기술 | P05, P07 | W03, W06, W07, W09, W10, W11, W12, W21, W22, W23, W24 |

## 비교 금지 / 주석 필요 항목

- Whisper repo의 모델별 속도/메모리는 A100 기준 영어 전사 상대 속도이므로 Minto2 macOS 한국어 회의 RTF로 해석하지 않는다.
- Qwen3-ASR의 WER/CER 수치는 모델카드/논문/데이터셋을 다시 확인하기 전에는 후보 소개 이상으로 쓰지 않는다.
- SpeakerKit, pyannote, FluidAudio, VBx의 DER은 collar, overlap, dataset subset 차이를 주석 없이 순위화하지 않는다.
- Apple Speech/SpeechAnalyzer는 문서 페이지 존재와 실제 SDK availability를 분리한다.
