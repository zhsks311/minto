# STT 엔진 벤치마크 — 자체 완결형 테스트 프레임워크

새 STT 엔진을 넣었을 때 **측정 → 비교 → 채택 판정 → 리포트**를 한 명령으로 돌리는 모듈.
앱(`Sources/`, Swift)과 **분리**되어 있다 — 순수 Python이며 자체 테스트로 검증된다.

> 신뢰성 설계의 근거(왜 반복측정·신뢰구간·sanity 상한인가)는 [ADR 0004](../../docs/adr/0004-stt-benchmark-reliability-methodology.md).

## 구조

```
tools/stt-benchmark/
├── lib/        12개 순수 Python 모듈 (판정·집계·게이트·오케스트레이터)
├── tests/      대응 테스트 (전부 순수 Python, Swift 불필요)
└── fixtures/   manifest 픽스처
```

핵심 모듈: `validate_stt_benchmark_manifest`(스키마), `stt_engine_verdict`(순위·무승부),
`stt_repeat_statistics`(반복측정 CI), `aggregate_stt_repeat_metric`(CI 주입),
`build_stt_engine_lane_matrix`(순위), `run_stt_regression_gate`(개선/악화 신호),
`run_stt_benchmark_decision_gate`(채택 판정), `convert/render/check_*`,
`run_stt_official_benchmark`(오케스트레이터).

## 테스트

```bash
cd tools/stt-benchmark && python3 -m pytest tests/ -q
```

앱 빌드 없이 1초 내 완료된다 — 모듈이 Swift에 묶이지 않음을 보장한다.

## 한 명령 실행

repo 루트에서(전사 러너가 이 repo `scripts/`에 있다):

```bash
python3 tools/stt-benchmark/lib/run_stt_official_benchmark.py \
  --engines whisper_accurate,speech_analyzer \
  --baseline-engine whisper_accurate \
  --reference-version seed-smi-2026-06-12 \
  --reference-manifest tools/stt-benchmark/fixtures/minimal_reference_manifest.json \
  --manual-review-manifest tools/stt-benchmark/fixtures/minimal_manual_review_manifest.json \
  --transcribe-cmd "python3 $(pwd)/scripts/run_meeting_stt_pipeline.py" \
  --raw-dir "$(pwd)/sample/meeting/raw" \
  --samples 본회의_20260428 \
  --repeats 5 \
  --output-root /tmp/stt-bench-run
```

> 실측 확인됨(2026-06-23, main): 위 명령이 한 번에 전사→비교→판정→리포트까지 수행한다.
> `--samples`를 빼면 raw-dir의 전체 코퍼스, `--repeats`를 늘리면 신뢰구간이 좁아진다.

### 전사 경계 — `--transcribe-cmd`

실제 STT 전사는 앱의 Swift 엔진에서 일어나므로, 모듈은 전사를 **외부 러너로 주입**받는다:

- **`--transcribe-cmd` 지정**: 오케스트레이터가 그 명령에 `--engines`/`--output-root`와 옵션 플래그를 붙여 호출한다. 러너는 `<output-root>/transcribe/<engine>/rep<k>/pipeline_manifest.json`을 써야 한다. 이 repo의 `scripts/run_meeting_stt_pipeline.py`가 이 규약을 따른다(실제 STT는 앱 Swift 엔진 호출). → 한 명령 end-to-end.
- **생략(분석 전용)**: 전사를 건너뛰고 미리 만든 pipeline manifest를 입력으로 받아 비교·판정만 한다. 없으면 명확한 오류로 중단한다.

## 7단계

> 전사(N회, 외부 러너) → 번들 변환 → 반복측정 CI 집계 → 엔진 순위/무승부 → 개선/악화 신호 → 채택 판정 → 리포트

## 결과 읽는 법

`decision/official_stt_decision_manifest.json`의 `decision_state`:

| state | 의미 |
|---|---|
| `default_allowed` | 제품 default 교체 권장 (CI 기준 확실히 우수 + product_path·user_impact 충족) |
| `experimental_flag_only` | 실험만, default 유지 (무승부 / product_path 미검증) |
| `rejected` | 채택·실험 불가 (CI 기준 확실히 악화, 또는 CER이 sanity 상한 0.70 초과) |

**"확실히 나을 때만 교체"**: CER 1등이라도 2등과 신뢰구간이 겹치면 `default_allowed`가 안 나온다.

## 주요 옵션

- `--repeats N`: 같은 엔진을 N회 전사해 CI를 낸다(ANE 비결정성 ±8pp 흡수). 잠정 기본 5.
- `--product-path`: adoption run(전 엔진 product_path → `default_allowed` 도달 + 비교가능). **기본 OFF = 비교/랭킹**(realistic CER). ⚠️ product-path 측정 하니스가 현재 under-transcribe하니 점검 후 사용.
- `--samples`, `--max-windows`: 빠른 스모크용 스코프 제한(max-windows를 작게 주면 CER이 degenerate).
- `--no-skip-existing`: 처음부터 재실행(기본은 출력 존재 시 skip=재개).

## 실측 예시 (기본 비교 모드)

`본회의_20260428` 샘플, `--repeats 3`:

| 엔진 | cer_mean | 95% CI(±) |
|---|---|---|
| whisper_accurate (baseline) | 0.4664 | 0.0201 |
| speech_analyzer (candidate) | 0.2857 | 0.0 |

→ whisper가 3런에 걸쳐 흔들려(0.459~0.475) 실제 CI(±0.020)가 잡혔다. speech_analyzer가 CI 비겹침으로 `significant_improvement`. `decision_state=experimental_flag_only`(비교 모드라 교체는 product-path 검증 후).
