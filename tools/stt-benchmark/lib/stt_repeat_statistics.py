"""ADR 0004 항목⑤: STT 반복측정 통계 집계 (순수 함수).

ANE(Apple Neural Engine) 비결정성으로 같은 오디오·엔진도 런마다 CER이 흔들린다(±8pp
관측). 단일 측정은 신뢰할 수 없으므로 같은 측정을 N회 반복해 평균·표준편차·신뢰구간을
낸다. 이 모듈은 **순수 집계 함수만** 제공한다 — N회 실행 오케스트레이션(실측)과
metric_summary/decision 게이트 연결은 실제 재실행 데이터 확보 후 이 함수를 호출해 채운다.

critic 경고 반영: N을 ±8pp 가정으로 고정하면 순환논증이 된다. 따라서 이 함수는 N을
입력으로 받지 않고, 주어진 측정값들의 분산·CI를 그대로 계산해 반환한다.
"""

import math
import statistics

# Student t 0.975 분위(양측 95% CI), 자유도 df=1..29.
# 반복측정은 보통 N=3~10회로 작아, 정규근사(1.96)는 CI를 과소추정해 신뢰성을
# 과대평가한다(예: df=2면 t=4.303 vs 1.96 → 실제 CI의 45%로 축소). scipy 의존을
# 추가하지 않으려고 임계값을 테이블로 둔다. df>=30은 정규근사(1.96)로 수렴.
_T_CRITICAL_0975 = {
    1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571,
    6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
    11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131,
    16: 2.120, 17: 2.110, 18: 2.101, 19: 2.093, 20: 2.086,
    21: 2.080, 22: 2.074, 23: 2.069, 24: 2.064, 25: 2.060,
    26: 2.056, 27: 2.052, 28: 2.048, 29: 2.045,
}


def _t_critical_95(degrees_of_freedom):
    if degrees_of_freedom in _T_CRITICAL_0975:
        return _T_CRITICAL_0975[degrees_of_freedom]
    return 1.96  # df>=30: 정규 근사로 수렴


def summarize_repeat_cers(cer_values):
    """반복 측정된 weighted CER 값들의 통계를 집계한다.

    입력 ``cer_values``는 각 반복 런의 **이미 계산된 weighted CER** 값이어야 한다
    (이 함수는 weighted 계산을 하지 않고 산술 통계만 낸다). 숫자가 아닌 값(None, bool,
    문자열 등)은 측정 미완으로 보고 제외한다.

    반환: run_count, cer_mean, cer_std, cer_ci95_half_width.
    측정 0개면 모두 None, 1개면 분산을 알 수 없어 std/CI는 None(단일 측정 불신).
    2개 이상은 t분포 임계값으로 95% CI 반너비를 낸다(작은 N에서 정직하게 넓은 CI).
    """
    measured = [
        value
        for value in cer_values
        if isinstance(value, (int, float)) and not isinstance(value, bool)
    ]
    run_count = len(measured)
    if run_count == 0:
        return {
            "run_count": 0,
            "cer_mean": None,
            "cer_std": None,
            "cer_ci95_half_width": None,
        }
    mean = sum(measured) / run_count
    if run_count == 1:
        return {
            "run_count": 1,
            "cer_mean": mean,
            "cer_std": None,
            "cer_ci95_half_width": None,
        }
    # 표본 표준편차(n-1): 반복 런은 분포의 표본이므로 stdev 사용(pstdev 아님).
    std = statistics.stdev(measured)
    # t분포 임계값으로 95% CI 반너비. 작은 N에서 정규근사(1.96)는 CI를 과소추정한다.
    t_critical = _t_critical_95(run_count - 1)
    ci95_half_width = t_critical * std / math.sqrt(run_count)
    return {
        "run_count": run_count,
        "cer_mean": mean,
        "cer_std": std,
        "cer_ci95_half_width": ci95_half_width,
    }
