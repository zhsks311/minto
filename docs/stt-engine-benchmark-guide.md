# STT 엔진 벤치마크 — 한 명령 사용법

새 STT 엔진을 후보로 넣었을 때, **한 명령으로 측정 → 비교 → 채택 판정 → 리포트**까지 돌리는 방법.

> 신뢰성 설계의 근거(왜 반복측정·신뢰구간·sanity 상한인가)는 [ADR 0004](adr/0004-stt-benchmark-reliability-methodology.md)를 본다. 이 문서는 "어떻게 돌리나"만 다룬다.

## 한 줄 요약

```bash
python3 scripts/run_stt_official_benchmark.py \
  --engines whisper_accurate,speech_analyzer \
  --baseline-engine whisper_accurate \
  --reference-version seed-smi-2026-06-12 \
  --reference-manifest docs/fixtures/stt-benchmark/minimal_reference_manifest.json \
  --manual-review-manifest docs/fixtures/stt-benchmark/minimal_manual_review_manifest.json \
  --raw-dir <샘플 오디오 디렉터리> \
  --repeats 5 \
  --output-root <결과 저장 위치>
```

- `--engines`: 측정·순위 매길 엔진 목록(쉼표 구분). 예: `whisper_accurate`, `speech_analyzer`, `sf_speech_on_device`, `nemotron`, `sherpa`.
- `--baseline-engine`: **현 제품 엔진**(교체 판정의 비교 기준).
- `--candidate-engine`: 채택 판정 대상. 생략하면 baseline이 아닌 유일 엔진이 자동 선택된다(2엔진이면 안 써도 됨).
- `--raw-dir`: `<id>_full.wav` + `<id>_smi.json` 쌍이 든 디렉터리. (이 repo의 회의 코퍼스는 `sample/meeting/raw/`)
- `--repeats N`: **같은 엔진을 N회 전사**해 신뢰구간(CI)을 낸다. ANE 비결정성(±8pp)을 흡수하는 핵심. 잠정 기본 5(첫 실측 후 목표 CI에서 역산 — ADR D-N).
- `--output-root`: 모든 산출물이 쌓이는 루트.

## 무슨 일이 일어나나 (7단계)

> 엔진 전사(1) → 공식 번들 변환(2) → 반복측정 CI 집계(3) → 엔진 순위/무승부(4) → 악화·개선 신호(5) → 채택 판정(6) → 리포트(7)

| 단계 | 스크립트 | 산출물 |
|---|---|---|
| 1. 전사(N회) | `run_meeting_stt_pipeline.py` | `transcribe/<engine>/rep<k>/` |
| 2. 번들 변환 | `convert_stt_pipeline_to_official_bundle.py` | `bundle/<engine>/rep<k>/` |
| 3. CI 집계 | `aggregate_stt_repeat_metric.py` | `aggregate/<engine>/metric_summary.json` |
| 4. 순위 매트릭스 | `build_stt_engine_lane_matrix.py` | `lane_matrix/engine_lane_matrix.{json,csv,md}` |
| 5. 악화/개선 신호 | `run_stt_regression_gate.py` | `regression/regression_report.json` |
| 6. 채택 판정 | `run_stt_benchmark_decision_gate.py` | `decision/official_stt_decision_manifest.json` |
| 7. 리포트 | `render_stt_official_benchmark_report.py` | `report/stt_official_benchmark_report.{md,html}` |

## 결과 읽는 법

핵심은 `decision/official_stt_decision_manifest.json`의 `decision_state`:

| decision_state | 의미 | 언제 |
|---|---|---|
| `default_allowed` | **제품 default로 교체 권장** | candidate가 baseline보다 CI 기준 **확실히 우수**(신뢰구간 비겹침) + product_path·user_impact 충족 |
| `experimental_flag_only` | 실험 플래그로만, default 유지 | 차이가 노이즈 안(무승부) / product_path·user_impact 미충족 |
| `rejected` | 채택·실험 모두 불가 | CI 기준 **확실히 악화**, 또는 CER이 sanity 상한(기본 0.70) 초과 |

`regression/regression_report.json`의 `improvement_signal`이 판정의 근거:
- `significant_improvement` — candidate CI 상단 < baseline CI 하단 (확실히 개선)
- `significant_regression` — 그 반대 (확실히 악화)
- `tie` — CI 겹침 (무승부, 노이즈 안)
- `unknown_ci` — 한쪽이라도 CI 없음(단일 런) → 기존 2pp 임계로 fallback

> **"확실히 나을 때만 교체"** 규칙이 게이트에 강제돼 있다. CER 1등이라도 2등과 CI가 겹치면 `default_allowed`가 안 나온다.

## 새 엔진 추가

`--engines`에 한 줄 더 넣으면 끝이다(엔진 러너가 이미 지원하는 경우). 파이프라인 raw engine id가 공식 비교 id와 다르면 `--engine-id-alias RAW=CANONICAL`로 매핑한다.

## 옵션

- `--samples a,b,c`: 특정 샘플만(기본: raw-dir의 모든 쌍). 빠른 스모크에 유용.
- `--max-windows N`: 샘플당 window 상한(작게=빠른 스모크, 기본 0=전체). **주의: 작게 주면 CER이 전체 reference 대비 과대평가돼 1.0 부근으로 degenerate한다 — 배선 확인용이지 품질 비교용이 아니다.**
- `--product-path`: adoption run. 모든 엔진을 product_path로 측정·라벨 → candidate가 `default_allowed` 도달 가능 + 이종 엔진 비교가능. **기본은 OFF(비교/랭킹 모드)**: realistic CER로 엔진 우열을 보고, decision은 `experimental_flag_only`까지만 나온다. ⚠️ product-path 측정 하니스가 현재 under-transcribe한다(아래 주의 참조) — adoption에 쓰기 전 점검할 것.
- `--sanity-cer-cap`: sanity 상한(기본 0.70). 이걸 넘는 CER은 "측정이 깨졌거나 품질이 쓸 수 없다"로 보고 거부.
- `--dry-run`: 엔진 구동 없이 배선만 검증(파이프라인에 `--dry-run` 전달). 산출물 흐름·게이트 연결을 빠르게 확인.

## 재개 (멱등성)

각 단계는 산출물이 이미 있으면 건너뛴다. 긴 N회 전사가 중단돼도 **같은 명령을 다시 실행하면 끝난 단계는 skip하고 이어서** 돈다. 처음부터 다시 돌리려면 `--no-skip-existing`.

## 실측 예시

이 repo 코퍼스의 한 샘플(`본회의_20260428`, 8분 회의)을 **기본 모드(비교/랭킹)** `--repeats 3`로 돌린 실제 결과:

| 엔진 | rep1 | rep2 | rep3 | cer_mean | 95% CI(±) |
|---|---|---|---|---|---|
| whisper_accurate (baseline) | 0.4650 | 0.4751 | 0.4591 | 0.4664 | 0.0201 |
| speech_analyzer (candidate) | 0.2857 | 0.2857 | 0.2857 | 0.2857 | 0.0 |

- whisper가 3런에 걸쳐 **흔들렸다**(0.459~0.475) → 실제 신뢰구간(±0.0201). 단일 측정이었다면 이 불확실성이 안 보였다 — **반복측정의 존재 이유**.
- speech_analyzer의 CI 상단(0.2857)이 whisper의 CI 하단(0.4664−0.0201=0.4463)보다 한참 낮다 → `improvement_signal=significant_improvement`("이 샘플에선 speech_analyzer가 확실히 우수").
- `decision_state=experimental_flag_only`: 비교 모드라 채택(default 교체)은 product-path 검증을 거쳐야 한다. CI로 우열은 가렸지만 교체는 보류 — 의도된 안전 동작.

> whisper의 절대 CER(~0.47)이 SMI non-verbatim floor(40~50%)에 닿아 있다 — 정상 범위. (`--product-path` 모드로 돌리면 현재 product-path 하니스가 under-transcribe해 CER이 0.85+로 부풀려지고 sanity 상한 0.70에 걸려 거부된다. **이건 측정 프레임워크가 아니라 product-path 측정 경로의 품질 문제이며, 별도 과제다.** 그래서 비교 기본값은 non-product-path다.)
