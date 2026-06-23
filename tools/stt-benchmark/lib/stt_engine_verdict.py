"""ADR 0004: STT 엔진 우열 판정 규칙 (순수 함수).

신뢰성 제일 = ANE 노이즈(±8pp)를 우열로 착각하지 않는다. 엔진별 (cer_mean, 95% CI
반너비)를 받아:
  (1) rank_with_ties: cer_mean 오름차순 순위. 인접 엔진과 CI가 겹치면 무승부(tie)로 묶음.
  (2) is_significant_improvement: 후보 CI 상단 < 기준(현 제품) CI 하단일 때만 '확실히 우수'.

CI(cer_ci95_half_width)는 반복측정(stt_repeat_statistics)에서 나온다. CI가 없으면
(단일 측정 등) 비교를 보수적으로 처리한다(점구간). 실제 CI 채움은 N회 실행(재실행) 후.
"""


def _mean_and_half(entry):
    """(cer_mean, half) 추출. mean이 숫자가 아니면 None, half 없으면 None(점구간)."""
    mean = entry.get("cer_mean")
    if not isinstance(mean, (int, float)) or isinstance(mean, bool):
        return None
    half = entry.get("cer_ci95_half_width")
    if not isinstance(half, (int, float)) or isinstance(half, bool):
        half = None
    return (mean, half)


def rank_with_ties(entries):
    """엔진을 cer_mean 오름차순 순위화하되, CI가 겹치는 연속 엔진은 무승부(tie)로 묶는다.

    entries: [{engine_id, cer_mean, cer_ci95_half_width}, ...]
    반환: [{rank, tie_group, engine_id, cer_mean, cer_ci95_half_width}], cer_mean 없는 항목 제외.
    rank는 1부터 연속. tie_group은 1부터이며, 직전까지 묶인 그룹의 CI 상단과 이번 엔진의
    CI 하단이 겹치면(전이적) 같은 tie_group. CI(half) None은 폭 0 점구간으로 본다.
    """
    valid = [entry for entry in entries if _mean_and_half(entry) is not None]
    valid.sort(key=lambda entry: (entry["cer_mean"], entry.get("engine_id", "")))
    result = []
    tie_group = 0
    group_upper = None  # 현재 tie 그룹에 속한 엔진들의 최대 CI 상단
    for index, entry in enumerate(valid):
        mean, half = _mean_and_half(entry)
        lower = mean - half if half is not None else mean
        upper = mean + half if half is not None else mean
        if group_upper is not None and lower <= group_upper:
            group_upper = max(group_upper, upper)  # 같은 그룹 유지(겹침)
        else:
            tie_group += 1
            group_upper = upper
        result.append({
            "rank": index + 1,
            "tie_group": tie_group,
            "engine_id": entry.get("engine_id", ""),
            "cer_mean": mean,
            "cer_ci95_half_width": half,
        })
    return result


def is_significant_improvement(candidate, baseline):
    """후보가 기준(현 제품) 엔진보다 '확실히' 우수한가(교체 권장 여부).

    후보 CI 상단 < 기준 CI 하단이면 True(CI 비겹침 = 노이즈 너머 우수). 엄격 부등호이므로
    정확히 맞닿는 경우(상단 == 하단)도 False(완전 분리만 우수로 인정, 보수적).
    어느 한쪽이라도 cer_mean 또는 CI(half)가 없으면 비교 불가로 False(보수적: 확실하지
    않으면 교체하지 않는다).
    """
    candidate_pair = _mean_and_half(candidate)
    baseline_pair = _mean_and_half(baseline)
    if candidate_pair is None or baseline_pair is None:
        return False
    candidate_mean, candidate_half = candidate_pair
    baseline_mean, baseline_half = baseline_pair
    if candidate_half is None or baseline_half is None:
        return False
    return (candidate_mean + candidate_half) < (baseline_mean - baseline_half)
