"""6단계: Finding 목록을 사람이 듣기 쉬운 요약 문장으로 만든다.

순서: caution(심각한 것부터) -> missing -> info. 처음 요약에는 최대 3개만 말한다.
"""

from __future__ import annotations

_LEVEL_ORDER = {"caution": 0, "missing": 1, "info": 2}
_SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "info": 3}
_ORDINALS = ["첫째", "둘째", "셋째"]

DISCLAIMER = (
    "최종 판단은 직접 하세요. "
    "정확한 상담은 대한법률구조공단 132나 고용노동부 1350에서 받을 수 있어요."
)


def build_summary(findings: list[dict]) -> str:
    if not findings:
        return f"특별히 확인이 필요한 항목을 찾지 못했어요. {DISCLAIMER}"

    ordered = sorted(
        findings,
        key=lambda f: (
            _LEVEL_ORDER.get(f["level"], 9),
            _SEVERITY_ORDER.get(f.get("severity", "info"), 9),
        ),
    )
    caution_n = sum(1 for f in findings if f["level"] == "caution")
    missing_n = sum(1 for f in findings if f["level"] == "missing")

    parts = [f"확인이 필요한 곳 {caution_n}개, 빠진 항목 {missing_n}개를 찾았어요."]
    for i, f in enumerate(ordered[:3]):
        label = _ORDINALS[i] if i < len(_ORDINALS) else f"{i + 1}번째"
        parts.append(f"{label}, {f['speech']}")

    rest = len(ordered) - 3
    if rest > 0:
        parts.append(f"나머지 {rest}개는 목록에서 들을 수 있어요.")

    parts.append(DISCLAIMER)
    return " ".join(parts)
