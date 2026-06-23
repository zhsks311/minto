#!/usr/bin/env python3
"""ADR 0004 항목⑤ B-반복실행: 같은 엔진을 N회 측정한 metric_summary들을 1개로 집계한다.

ANE(Apple Neural Engine) 비결정성으로 같은 오디오·엔진도 런마다 weighted_cer이 흔들린다
(±8pp 관측). 단일 측정은 신뢰할 수 없으므로 같은 엔진을 N회 전사해 metric_summary를 N개
만들고, 이 스크립트로 weighted_cer을 ``stt_repeat_statistics``로 집계해 평균·CI를 낸 뒤
대표 metric_summary 하나에 ``weighted_cer=cer_mean`` + ``cer_ci95_half_width``를 주입한다.
이 CI가 regression/decision 게이트의 ``is_significant_improvement`` 판정에 공급된다(A 배선).

설계 결정:
- **placeholder/실패 런 제외**: ``metric_placeholder=True``이거나 weighted_cer이 숫자가
  아닌 런은 집계에서 뺀다. 실패 런의 PLACEHOLDER_CER(1.0)이 평균을 오염시키면 신뢰성이
  무너진다. 측정된 런이 0개면 대표 metric을 placeholder 그대로 두고 CI를 붙이지 않는다.
- **base metric 보존**: 카운트(empty_final 등)·user_impact는 첫 *측정* 런 metric을
  골격으로 쓰고, CER 통계만 덮어쓴다. 반복 런은 같은 입력이라 카운트는 거의 동일하다.
- **CI > 1.0 보수적 suppress**: 스키마(require_ratio)는 cer_ci95_half_width를 [0,1]로
  제한한다. N=2 고분산이면 t·std/√N가 1을 넘을 수 있는데, 이는 "측정이 너무 흔들려 CI를
  신뢰할 수 없다"는 신호다. clamp(축소 보고)는 금지 — CI 필드를 빼서 게이트가 2pp
  fallback으로 강등되게 하고 이유를 ``ci_suppressed_reason``에 남긴다(단일 측정 불신과 같은 결).
"""
import argparse
import copy
import json
from pathlib import Path

import stt_repeat_statistics as repeat_stats
import validate_stt_benchmark_manifest as validator


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Aggregate N repeat metric_summary files for one engine into a CI-enriched metric_summary."
    )
    parser.add_argument(
        "--metric-summary",
        type=Path,
        action="append",
        required=True,
        help="A repeat-run metric_summary.json (give one per repeat; all must be the same engine).",
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def read_json(path):
    return json.loads(path.expanduser().read_text(encoding="utf-8"))


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def is_measured(metric):
    # placeholder 런은 weighted_cer이 PLACEHOLDER_CER(1.0)이라 집계에서 빼야 한다.
    if metric.get("metric_placeholder") is True:
        return False
    value = metric.get("weighted_cer")
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def aggregate(metrics):
    """N개 metric_summary dict를 받아 CI를 주입한 대표 metric_summary dict를 만든다.

    metrics는 같은 엔진의 반복 런 metric_summary들이어야 한다(엔진 식별은 호출자 보장 —
    metric_summary 자체엔 engine_id가 없다). 측정된 런이 없으면 첫 metric을 그대로 돌려준다.
    """
    if not metrics:
        raise ValueError("at least one metric_summary is required")

    measured = [metric for metric in metrics if is_measured(metric)]
    base = copy.deepcopy(measured[0] if measured else metrics[0])

    summary = repeat_stats.summarize_repeat_cers(
        [metric.get("weighted_cer") for metric in measured]
    )
    base["run_count"] = summary["run_count"]

    # 측정 런이 0개: placeholder 골격 그대로, CI 미부착(게이트는 2pp fallback).
    if summary["run_count"] == 0:
        base.pop("cer_std", None)
        base.pop("cer_ci95_half_width", None)
        return base

    base["weighted_cer"] = summary["cer_mean"]

    half_width = summary["cer_ci95_half_width"]
    std = summary["cer_std"]
    # N=1은 분산을 알 수 없어 std/CI가 None — CI 미부착(단일 측정 불신).
    # cer_std도 스키마 require_ratio(0~1) 검증을 받는다. weighted_cer이 [0,1]이면 표본
    # std는 최대 ~0.707(N=2)이라 1을 넘기 어렵지만, 지표 범위가 바뀔 미래를 대비해 CI와
    # 같은 보수적 처리를 한다 — 1을 넘으면 신뢰 못 할 분산이므로 빼서 스키마 위반을 막는다.
    if std is not None and std <= 1.0:
        base["cer_std"] = std
        base.pop("std_suppressed_reason", None)
    else:
        base.pop("cer_std", None)
        if std is not None:
            # CI suppress와 대칭: 도달은 사실상 불가하나 진단 일관성을 위해 이유를 남긴다.
            base["std_suppressed_reason"] = "cer_std_exceeds_unit_interval"
    if half_width is not None and half_width <= 1.0:
        base["cer_ci95_half_width"] = half_width
        base.pop("ci_suppressed_reason", None)
    else:
        base.pop("cer_ci95_half_width", None)
        if half_width is not None:
            # CI가 [0,1]을 벗어남: 측정이 너무 흔들려 CI를 신뢰할 수 없다 → 보수적 강등.
            base["ci_suppressed_reason"] = "ci_half_width_exceeds_unit_interval"
    return base


def run(args):
    metrics = [read_json(path) for path in args.metric_summary]
    payload = aggregate(metrics)
    errors = validator.validate_manifest(payload)
    if errors:
        for error in errors:
            print(f"validation error: {error}")
        raise SystemExit("aggregated metric_summary is invalid")

    output_path = args.output.expanduser().resolve()
    write_json(output_path, payload)
    print(f"wrote: {output_path}")
    print(f"run_count: {payload.get('run_count')}")
    print(f"weighted_cer: {payload.get('weighted_cer')}")
    print(f"cer_ci95_half_width: {payload.get('cer_ci95_half_width')}")
    return {"payload": payload, "output_path": output_path}


def main(argv=None):
    # run()은 성공 시 dict를 반환하고 실패는 내부에서 SystemExit으로 던진다.
    run(parse_args(argv))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
