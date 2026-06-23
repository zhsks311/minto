#!/usr/bin/env python3
"""ADR 0004 B-통합 래퍼: 새 STT 엔진을 한 명령으로 측정→비교→판정→리포트.

"새 모델을 넣으면 한 번에 신뢰성 있게 우열을 본다"가 목표다. 단계:
  (1) 엔진별 N회 전사(외부 러너 --transcribe-cmd)    — ANE 비결정성을 N회로 흡수
  (2) 각 런을 공식 번들로 변환(convert_*)            — metric_summary 생성
  (3) 엔진별 N개 metric을 CI로 집계(aggregate_*)      — weighted_cer 평균 + cer_ci95
  (4) lane matrix로 전 엔진 순위/무승부(build_*)
  (5) regression gate(후보 vs baseline) → improvement_signal
  (6) decision gate → 채택 판정(default_allowed/experimental/rejected)
  (7) 리포트(md/html)

설계 결정(2026-06-22 design doc):
- **D-b1 .py 오케스트레이터**: 단계 간 산출물 경로를 런타임에 발견해야 해서(.sh로는 취약)
  파이썬으로 짠다. 외부 스크립트는 subprocess로 호출하되, 호출기(invoke)를 주입 가능하게 해
  엔진 실제 구동 없이 테스트한다.
- **D-b2 skip(재개) 멱등성**: 각 단계는 출력이 이미 있으면 건너뛴다(``--no-skip-existing``로
  강제 재실행). 긴 N회 전사가 중단돼도 이어서 돌릴 수 있다.
- **D-b3 N=5 잠정**: critic 경고대로 목표 CI에서 역산해야 하나, 잠정 기본값 5.

엔진 실제 구동은 실측 환경에서 일어난다. 이 스크립트는 배선·순서·CI 집계·판정 연결을
소유하고, dry-run(``--dry-run``)으로 산출물 흐름만 검증할 수 있다.

decision/regression의 baseline은 현 제품 엔진(``--baseline-engine``)이고, 판정 대상은
``--candidate-engine``(생략 시 baseline이 아닌 유일 엔진을 자동 선택)이다.
"""
import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="One-command STT engine benchmark: measure (N runs) -> compare -> judge -> report."
    )
    parser.add_argument("--engines", required=True, help="Comma-separated engines to transcribe and rank.")
    parser.add_argument("--baseline-engine", required=True, help="Current product engine (regression baseline).")
    parser.add_argument("--candidate-engine", help="Engine judged by regression/decision (default: the non-baseline engine).")
    parser.add_argument("--reference-version", required=True)
    parser.add_argument("--reference-manifest", type=Path, required=True, help="Reference manifest for the decision gate.")
    parser.add_argument("--manual-review-manifest", type=Path, required=True, help="Manual review manifest for the decision gate.")
    parser.add_argument(
        "--transcribe-cmd",
        help=(
            "Transcription runner command (e.g. 'python3 /path/to/run_meeting_stt_pipeline.py'). The "
            "orchestrator appends --engines/--output-root and the flags below. The runner must write "
            "<output-root>/transcribe/<engine>/rep<k>/pipeline_manifest.json. OMIT for analysis-only: "
            "then transcription is skipped and pre-existing pipeline manifests are required."
        ),
    )
    parser.add_argument("--raw-dir", type=Path, help="Audio raw dir passed to the transcription runner.")
    parser.add_argument("--samples", help="Comma-separated sample ids passed to the runner (default: all pairs in raw-dir).")
    parser.add_argument("--max-windows", type=int, help="Cap benchmark windows per sample (small = quick smoke; default 0 = full).")
    parser.add_argument("--repeats", type=int, default=5, help="Repeat transcription N times per engine for CI (D-b3).")
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--sample-set", help="Sample set label passed to convert.")
    parser.add_argument("--engine-id-alias", action="append", default=[], metavar="RAW=CANONICAL")
    parser.add_argument("--sanity-cer-cap", type=float, default=0.70, help="Decision gate sanity ceiling (default 0.70).")
    parser.add_argument("--weighted-cer-regression-pp", type=float, default=2.0)
    parser.add_argument(
        "--product-path",
        action="store_true",
        help=(
            "Adoption run: measure/label ALL engines as product_path so the decision gate can reach "
            "default_allowed AND heterogeneous engines stay comparable. Default OFF = comparison/ranking "
            "(realistic CER; decision caps at experimental_flag_only). NOTE: the product-path harness "
            "currently under-transcribes vs the default route (413 vs 1813 chars on a sample) — "
            "inspect before relying on it for adoption."
        ),
    )
    parser.add_argument("--no-skip-existing", action="store_true", help="Re-run every step even if its output exists.")
    parser.add_argument("--dry-run", action="store_true", help="Pass --dry-run to the pipeline runner (no real engines).")
    return parser.parse_args(argv)


# ── 설정/파생 ──────────────────────────────────────────────────────────────

class Config:
    def __init__(self, args):
        self.engines = [part.strip() for part in args.engines.split(",") if part.strip()]
        self.baseline_engine = args.baseline_engine
        self.candidate_engine = resolve_candidate_engine(self.engines, args.baseline_engine, args.candidate_engine)
        self.reference_version = args.reference_version
        self.reference_manifest = args.reference_manifest
        self.manual_review_manifest = args.manual_review_manifest
        self.transcribe_cmd = args.transcribe_cmd
        self.raw_dir = args.raw_dir
        self.samples = args.samples
        self.max_windows = args.max_windows
        self.repeats = args.repeats
        self.output_root = args.output_root.expanduser().resolve()
        self.sample_set = args.sample_set
        self.engine_id_alias = list(args.engine_id_alias or [])
        self.alias_map = parse_alias_map(self.engine_id_alias)
        self.sanity_cer_cap = args.sanity_cer_cap
        self.weighted_cer_regression_pp = args.weighted_cer_regression_pp
        # 기본 OFF = 비교/랭킹(realistic CER). --product-path는 adoption opt-in(default_allowed
        # 도달 + 이종 엔진 비교가능). product-path 하니스가 현재 under-transcribe하므로 기본에서 제외.
        self.product_path = args.product_path
        self.skip_existing = not args.no_skip_existing
        self.dry_run = args.dry_run


def parse_alias_map(aliases):
    # convert가 --engine-id-alias로 받는 RAW=CANONICAL을 dict로 파싱한다. convert가 bundle의
    # engine_id를 CANONICAL로 바꾸므로, 오케스트레이터도 같은 매핑으로 매칭해야 한다.
    mapping = {}
    for item in aliases:
        if "=" not in item:
            raise SystemExit(f"--engine-id-alias must be RAW=CANONICAL; got {item!r}")
        raw, canonical = item.split("=", 1)
        raw, canonical = raw.strip(), canonical.strip()
        if not raw or not canonical:
            raise SystemExit(f"--engine-id-alias must be RAW=CANONICAL; got {item!r}")
        mapping[raw] = canonical
    return mapping


def canonical_engine(config, engine):
    return config.alias_map.get(engine, engine)


def resolve_candidate_engine(engines, baseline_engine, explicit):
    if explicit:
        if explicit not in engines:
            raise SystemExit(f"--candidate-engine {explicit!r} is not in --engines")
        return explicit
    others = [engine for engine in engines if engine != baseline_engine]
    if len(others) == 1:
        return others[0]
    raise SystemExit(
        "--candidate-engine is required when there is not exactly one non-baseline engine "
        f"(non-baseline engines: {others})"
    )


def validate_config(config):
    if config.repeats < 1:
        raise SystemExit("--repeats must be >= 1")
    if config.baseline_engine not in config.engines:
        raise SystemExit(f"--baseline-engine {config.baseline_engine!r} is not in --engines")


# ── 경로 레이아웃 ───────────────────────────────────────────────────────────

def transcribe_dir(config, engine, repeat):
    return config.output_root / "transcribe" / engine / f"rep{repeat}"


def pipeline_manifest_path(config, engine, repeat):
    return transcribe_dir(config, engine, repeat) / "pipeline_manifest.json"


def bundle_dir(config, engine, repeat):
    return config.output_root / "bundle" / engine / f"rep{repeat}"


def bundle_manifest_path(config, engine, repeat):
    return bundle_dir(config, engine, repeat) / "engine_run_bundle_manifest.json"


def aggregate_metric_path(config, engine):
    return config.output_root / "aggregate" / engine / "metric_summary.json"


def lane_matrix_dir(config):
    return config.output_root / "lane_matrix"


def regression_dir(config):
    return config.output_root / "regression"


def decision_dir(config):
    return config.output_root / "decision"


def report_dir(config):
    return config.output_root / "report"


# ── command 빌더(순수) ─────────────────────────────────────────────────────

def script(name):
    return str(SCRIPTS_DIR / name)


def pipeline_command(config, engine, repeat):
    # 전사 러너는 외부 주입(--transcribe-cmd). 모듈은 실제 STT 엔진(앱 Swift)에 묶이지 않는다.
    # 러너는 표준 플래그를 받아 <output-root>/transcribe/<engine>/rep<k>/pipeline_manifest.json을 써야 한다.
    command = shlex.split(config.transcribe_cmd) + [
        "--engines", engine,
        "--output-root", str(transcribe_dir(config, engine, repeat)),
    ]
    if config.raw_dir is not None:
        command += ["--raw-dir", str(config.raw_dir)]
    if config.samples:
        command += ["--samples", config.samples]
    if config.max_windows is not None:
        command += ["--max-windows", str(config.max_windows)]
    # adoption run이면 실제 측정 경로도 product-path여야 라벨과 측정이 일치한다(거짓 라벨 금지).
    if config.product_path:
        command.append("--product-path")
    if config.dry_run:
        command.append("--dry-run")
    return command


def convert_command(config, engine, repeat):
    command = [
        sys.executable,
        script("convert_stt_pipeline_to_official_bundle.py"),
        "--pipeline-manifest", str(pipeline_manifest_path(config, engine, repeat)),
        "--reference-version", config.reference_version,
        "--output-root", str(bundle_dir(config, engine, repeat)),
    ]
    if config.sample_set:
        command += ["--sample-set", config.sample_set]
    for alias in config.engine_id_alias:
        command += ["--engine-id-alias", alias]
    # adoption run: 모든 엔진을 product_path_final로 통일. 이래야 (1) candidate가 decision
    # gate의 product_path=true 요구를 충족해 default_allowed에 도달 가능하고, (2) 이종 엔진의
    # benchmark_kind가 같아져 regression gate 비교가능성(not_comparable)을 통과한다.
    if config.product_path:
        command.append("--product-path")
    return command


def aggregate_command(config, engine, metric_paths):
    command = [
        sys.executable,
        script("aggregate_stt_repeat_metric.py"),
        "--output", str(aggregate_metric_path(config, engine)),
    ]
    for metric_path in metric_paths:
        command += ["--metric-summary", str(metric_path)]
    return command


def lane_matrix_command(config, engine_specs):
    command = [sys.executable, script("build_stt_engine_lane_matrix.py"), "--output-root", str(lane_matrix_dir(config))]
    for spec in engine_specs:
        command += [
            "--benchmark-run-manifest", str(spec["benchmark"]),
            "--metric-summary", str(spec["metric"]),
            "--engine-manifest", str(spec["engine"]),
        ]
    return command


def regression_command(config, candidate_spec, baseline_spec):
    return [
        sys.executable,
        script("run_stt_regression_gate.py"),
        "--candidate-benchmark-run-manifest", str(candidate_spec["benchmark"]),
        "--candidate-metric-summary", str(candidate_spec["metric"]),
        "--baseline-benchmark-run-manifest", str(baseline_spec["benchmark"]),
        "--baseline-metric-summary", str(baseline_spec["metric"]),
        "--output-root", str(regression_dir(config)),
        "--weighted-cer-regression-pp", str(config.weighted_cer_regression_pp),
    ]


def decision_command(config, candidate_spec):
    return [
        sys.executable,
        script("run_stt_benchmark_decision_gate.py"),
        "--benchmark-run-manifest", str(candidate_spec["benchmark"]),
        "--metric-summary", str(candidate_spec["metric"]),
        "--engine-manifest", str(candidate_spec["engine"]),
        "--manual-review-manifest", str(config.manual_review_manifest),
        "--reference-manifest", str(config.reference_manifest),
        "--regression-report", str(regression_dir(config) / "regression_report.json"),
        "--output-root", str(decision_dir(config)),
        "--sanity-cer-cap", str(config.sanity_cer_cap),
    ]


def report_command(config):
    return [
        sys.executable,
        script("render_stt_official_benchmark_report.py"),
        "--decision-manifest", str(decision_dir(config) / "official_stt_decision_manifest.json"),
        "--output-root", str(report_dir(config)),
    ]


# ── 실행 ───────────────────────────────────────────────────────────────────

def default_invoke(command):
    completed = subprocess.run(command)
    if completed.returncode != 0:
        raise SystemExit(f"step failed (exit {completed.returncode}): {' '.join(command)}")


def run_step(config, label, command, output_path, invoke):
    # flush=True: 자식 subprocess 출력과 섞여도 진행상황을 실시간으로 보이게 한다(긴 전사 추적).
    if config.skip_existing and output_path.exists():
        print(f"skip (exists): {label} -> {output_path}", flush=True)
        return
    print(f"run: {label}", flush=True)
    invoke(command)
    if not output_path.exists():
        raise SystemExit(f"{label} did not produce expected output: {output_path}")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def bundle_metric_path_for(config, engine, repeat):
    """해당 엔진 런의 metric_summary 절대경로(집계 입력)."""
    return _bundle_run_paths(config, engine, repeat)["metric"]


def _bundle_run_paths(config, engine, repeat):
    """변환된 번들에서 해당 엔진 런의 manifest 절대경로들을 찾는다.

    convert가 만든 디렉터리명은 엔진/benchmark_kind에 따라 달라 예측이 취약하다. 대신
    bundle manifest의 runs[].*(번들 루트 상대경로)를 읽어 발견한다. alias가 적용되면 bundle의
    engine_id는 CANONICAL이므로 같은 매핑으로 매칭한다.
    """
    manifest = read_json(bundle_manifest_path(config, engine, repeat))
    root = bundle_dir(config, engine, repeat)
    target = canonical_engine(config, engine)
    for run in manifest.get("runs", []):
        if run.get("engine_id") == target:
            return {
                "benchmark": root / run["benchmark_run_manifest"],
                "metric": root / run["metric_summary"],
                "engine": root / run["engine_manifest"],
            }
    raise SystemExit(f"no run for engine {target!r} in {bundle_manifest_path(config, engine, repeat)}")


def bundle_specs_for(config, engine, repeat):
    """lane matrix/regression/decision용 대표 (benchmark, metric, engine) 경로 묶음."""
    return _bundle_run_paths(config, engine, repeat)


def orchestrate(config, invoke=default_invoke):
    # (1)+(2) 엔진별 N회 전사 + 번들 변환.
    for engine in config.engines:
        for repeat in range(1, config.repeats + 1):
            manifest = pipeline_manifest_path(config, engine, repeat)
            if config.transcribe_cmd:
                run_step(
                    config, f"transcribe {engine} rep{repeat}",
                    pipeline_command(config, engine, repeat),
                    manifest, invoke,
                )
            elif not manifest.exists():
                # 분석 전용 모드: 러너 없이는 전사를 못 한다. 미리 만든 산출물이 있어야 한다.
                raise SystemExit(
                    f"no --transcribe-cmd and no existing transcription at {manifest}. "
                    "Provide --transcribe-cmd to run engines, or pre-produce pipeline manifests."
                )
            else:
                print(f"skip (analysis-only, exists): transcribe {engine} rep{repeat}", flush=True)
            run_step(
                config, f"convert {engine} rep{repeat}",
                convert_command(config, engine, repeat),
                bundle_manifest_path(config, engine, repeat), invoke,
            )

    # (3) 엔진별 N개 metric → CI 집계.
    for engine in config.engines:
        aggregate_output = aggregate_metric_path(config, engine)
        # 재개 시 집계가 이미 끝났으면 bundle manifest를 읽지 않는다 — 번들이 정리/손상된
        # 상태에서도 재개가 막히지 않도록(read를 skip 판단 뒤로 미룬다).
        if config.skip_existing and aggregate_output.exists():
            print(f"skip (exists): aggregate {engine} -> {aggregate_output}", flush=True)
            continue
        metric_paths = [
            bundle_metric_path_for(config, engine, repeat)
            for repeat in range(1, config.repeats + 1)
        ]
        run_step(
            config, f"aggregate {engine}",
            aggregate_command(config, engine, metric_paths),
            aggregate_output, invoke,
        )

    # 대표 benchmark/engine manifest는 rep1 번들에서, metric은 집계본(CI 포함)을 쓴다.
    # 번들이 정리/손상돼도 convert 단계(출력=bundle manifest)가 재실행으로 복원하므로 재개 안전.
    specs = {}
    for engine in config.engines:
        base = bundle_specs_for(config, engine, 1)
        specs[engine] = {**base, "metric": aggregate_metric_path(config, engine)}

    # (4) lane matrix(전 엔진).
    run_step(
        config, "lane matrix",
        lane_matrix_command(config, [specs[engine] for engine in config.engines]),
        lane_matrix_dir(config) / "engine_lane_matrix.json", invoke,
    )

    # (5) regression(후보 vs baseline).
    run_step(
        config, "regression gate",
        regression_command(config, specs[config.candidate_engine], specs[config.baseline_engine]),
        regression_dir(config) / "regression_report.json", invoke,
    )

    # (6) decision(채택 판정).
    run_step(
        config, "decision gate",
        decision_command(config, specs[config.candidate_engine]),
        decision_dir(config) / "official_stt_decision_manifest.json", invoke,
    )

    # (7) 리포트.
    run_step(
        config, "report",
        report_command(config),
        report_dir(config) / "stt_official_benchmark_report.md", invoke,
    )
    return {"output_root": config.output_root, "candidate_engine": config.candidate_engine}


def run(args):
    config = Config(args)
    validate_config(config)
    result = orchestrate(config)
    print(f"done: {result['output_root']}")
    print(f"candidate: {result['candidate_engine']}")
    decision_path = decision_dir(config) / "official_stt_decision_manifest.json"
    if decision_path.exists():
        decision = read_json(decision_path)
        print(f"decision_state: {decision.get('decision_state')}")
        print(f"default_change: {decision.get('default_change')}")
    return result


def main(argv=None):
    # run()은 성공 시 dict를 반환하고 실패는 내부/하위 단계에서 SystemExit으로 던진다.
    run(parse_args(argv))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
