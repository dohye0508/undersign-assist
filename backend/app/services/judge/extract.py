"""2단계: 읽기 결과의 글자 값(fields)을 규칙이 비교할 수 있는 숫자(ContractValues)로 바꾼다.

값마다 {"value": ..., "line": 몇 번째 줄에서 찾았는지} 모양으로 둔다.
못 뽑으면 그 키를 아예 넣지 않는다(추측해서 채우지 않는다).
"""

from __future__ import annotations

from . import parse as P

# 읽기 단계 field.label -> 여기서 쓰는 원시 키
_FIELD_ALIASES = {
    "임금": "wage_raw",
    "시간급": "wage_raw",
    "시급": "wage_raw",
    "월급": "wage_raw",
    "급여": "wage_raw",
    "근로 시간": "hours_raw",
    "소정근로시간": "hours_raw",
    "근로시간": "hours_raw",
    "쉬는 날": "holiday_raw",
    "휴일": "holiday_raw",
    "계약 기간": "period_raw",
    "계약기간": "period_raw",
    "보증금": "deposit_raw",
    "차임": "rent_raw",
}


def extract(doc) -> dict[str, dict]:
    raw: dict[str, dict] = {}
    for f in getattr(doc, "fields", []) or []:
        key = _FIELD_ALIASES.get((f.label or "").strip())
        if key and key not in raw:  # 먼저 찾은 값을 쓴다
            raw[key] = {"text": f.value, "line": f.line}

    values: dict[str, dict] = {}

    def put(name, value, line):
        if value is not None:
            values[name] = {"value": value, "line": line}

    if "wage_raw" in raw:
        txt, line = raw["wage_raw"]["text"], raw["wage_raw"]["line"]
        money = P.parse_money(txt)
        if money is not None:
            if any(k in txt for k in ("시급", "시간급", "시간당")):
                put("hourly_wage", money, line)
            elif "월" in txt:
                put("monthly_wage", money, line)
            else:
                # 단위가 불명확하면 금액 크기로 짐작한다 (10만원 넘으면 월급으로 봄)
                put("monthly_wage" if money > 100_000 else "hourly_wage", money, line)

    if "hours_raw" in raw:
        txt, line = raw["hours_raw"]["text"], raw["hours_raw"]["line"]
        rng = P.parse_time_range(txt)
        if rng:
            daily = max(rng[1] - rng[0], 0)
            put("daily_hours", round(daily, 2), line)
        minutes = P.parse_minutes(txt) if "휴게" in txt else None
        if minutes is not None:
            put("break_minutes", minutes, line)

    if "deposit_raw" in raw:
        txt, line = raw["deposit_raw"]["text"], raw["deposit_raw"]["line"]
        put("deposit", P.parse_money(txt), line)

    if "rent_raw" in raw:
        txt, line = raw["rent_raw"]["text"], raw["rent_raw"]["line"]
        put("monthly_rent", P.parse_money(txt), line)

    if "period_raw" in raw:
        txt, line = raw["period_raw"]["text"], raw["period_raw"]["line"]
        d = P.parse_date(txt)
        if d:
            put("contract_start", d, line)

    return values
