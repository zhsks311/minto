# STT 엔진 재실행 가이드 (official-reference-draft-2026-06-12)

작성: 2026-06-18. 목적: 버전 불일치(R3) 해소 — 엔진 5개를 `official-reference-draft-2026-06-12` 기준으로 재실행해 실제 비교 수치를 생성한다. ADR: `docs/adr/0004-...`.

## 역할 구분 (중요)
- **framework Python**이 오케스트레이션. 일부 엔진은 framework가 **minto2의 `swift test MeetingCorpusTests`를 호출**해 실제 전사한다.
- nemotron/sherpa는 Swift 비관여, Python 독립 러너.
- 모든 명령 cwd: `/Users/d66hjkxwt9/Idea/private/minto2-official-stt-benchmark-framework`

## 엔진별 실행 위치·의존성

| 엔진 | 전사 위치 | 의존성 | 비고 |
|------|----------|--------|------|
| whisper_accurate | minto2 Swift (MeetingCorpusTests) | WhisperKit 모델(첫 실행 자동 다운로드) | `STT_ENGINE=whisper_accurate` |
| speech_analyzer | minto2 Swift | **macOS 26+** (SpeechAnalyzer) | 미충족 시 skip+CER=1.0 placeholder |
| sf_speech_on_device | minto2 Swift | SFSpeechRecognizer | 미가용 시 skip |
| nemotron | Python sidecar | **mlx-audio**(Apple Silicon) + 모델 + 서버 기동 | localhost:8765 HTTP |
| sherpa | Python | **sherpa-onnx** + 모델(HF 자동) | streaming |

## 단계

### Step 0 — raw_dir에 smi.json 채우기 (블로커, 환경 무관)
현재 `target_reference_raw_dir/raw/`에 WAV 심볼릭만 있고 `*_smi.json`이 없어 전 레인 실패. 다음으로 해소:
```bash
python3 scripts/prepare_stt_reference_manifest_raw_dir.py \
  --reference-manifest /private/tmp/minto2-official-release-workflow-current/action_artifacts/reference_review_default_gate_pack/workflow/applied/reference_manifest.json \
  --output-root /private/tmp/minto2-official-release-workflow-current/action_artifacts/engine_reference_alignment_plan/target_reference_raw_dir
```
(applied manifest = 7 references, version `official-reference-draft-2026-06-12`)

### Step 1+2 — 레인별 추론 → bundle (정확한 명령은 command_template 참조)
권위 있는 명령 원문: `/private/tmp/minto2-official-release-workflow-current/action_artifacts/engine_reference_alignment_plan/engine_reference_alignment_command_template.txt`
레인별 패턴: `run_meeting_stt_pipeline.py --engines <엔진> ...` → `convert_*_to_official_bundle.py --reference-version official-reference-draft-2026-06-12 ...`
- whisper_accurate/speech_analyzer/sf_speech_on_device: `run_meeting_stt_pipeline.py`(swift test 경유)
- nemotron: `nemotron_mlx_sidecar.py --preload`(서버 먼저) → `nemotron_sidecar_bench.py` → `convert_nemotron_summary_to_official_bundle.py`
- sherpa: `pip install --target /private/tmp/minto2-sherpa-python sherpa-onnx` → `run_sherpa_streaming_pipeline.py` → `convert_stt_pipeline_to_official_bundle.py`
  - sherpa convert의 `--sample-set` 인수는 이스케이프 복잡 → command_template 원문 그대로 사용.

### Step 3 — 비교 검증 → decision/regression/release
bundle 생성 후 `check_stt_engine_comparability.py` / `audit_stt_official_engine_evidence.py`로 비교 가능성 확인 → decision/regression/release workflow.

## 환경 선행 체크

### 이 머신 점검 결과 (2026-06-18)
- macOS **26.4.1** → speech_analyzer ✅, arm64(Apple Silicon) ✅
- **바로 실행 가능(3)**: whisper_accurate(WhisperKit 첫 실행 다운로드), speech_analyzer, sf_speech_on_device — 전부 minto2 Swift 경로
- **설치 필요(2)**: nemotron(`pip install mlx-audio` 미설치), sherpa(`/private/tmp/minto2-sherpa-python`에 일부 있으나 `import sherpa_onnx` 확인 필요)

### 명령
- nemotron: `pip install mlx-audio` → `python3 scripts/nemotron_mlx_sidecar.py --check`.
- sherpa: `pip install --target /private/tmp/minto2-sherpa-python sherpa-onnx`.

## ✅ 시범 검증 (2026-06-18)
whisper_accurate × 본회의_20260428(max-windows 4, 앞 2분)로 Step 0→1→2 전 경로 확인:
- Step 1: runs 1, failures 0, CER 17.4%(2분 tight 구간), Empty 0.
- Step 2: bundle 최상위 `reference_version=official-reference-draft-2026-06-12` 정확.
- 실측 gap: bundle에 `decoding_parameters` 없음(convert 미채움, 아래 gap 참조).
→ 경로는 정상. 전체 재실행(7회의 × 5엔진, max-windows 제한 해제)은 사용자 환경에서 진행 가능. (시범 산출물: `/tmp/minto2-rerun-smoke/`)

## ⚠️ 알려진 gap (재실행 전 인지)
- **decoding_parameters 미채움(R6)**: `convert_*_to_official_bundle.py`에 `decoding_parameters`를 채우는 코드가 없다. 재실행해도 이 필드는 빈 채로 bundle 생성(validator는 허용). R6(파라미터 기록)을 실제로 충족하려면 (a) 엔진 전사 시 파라미터를 source artifact(pipeline_manifest)에 기록 + (b) convert가 그걸 읽어 채우도록 보강이 필요. **항목①은 스키마만 완료, "채움" 미연결.**
- **신뢰성 판정 로직 미연결**: decision/regression이 phantom_rate·반복측정·상대비교를 아직 판정에 안 쓴다(ADR 0004 "남은 본체"). 재실행 수치는 현재 단일-런·CER 중심으로만 평가됨.

## 미지수 (조사로 미확인)
- 각 엔진의 실제 실행 시간/리소스.
- macOS 버전·mlx/sherpa 설치 여부(사용자 환경 확인 필요).
