"""2단계: 읽기 결과를 규칙이 비교할 수 있는 숫자(ContractValues)로 바꾼다.

값마다 {"value": ..., "line": 몇 번째 줄에서 찾았는지} 모양으로 둔다. 줄 번호가 있어야 사진 위에 상자를 그리고
원문을 읽어줄 수 있다. 못 뽑으면 그 키를 아예 넣지 않는다(추측해서 채우지 않는다).

찾는 순서: 읽기 단계의 항목(fields) → 없으면 문서의 줄(blocks)에서 항목 이름으로 직접 찾기.
임대차·차용증 문서는 읽기 단계 항목이 근로계약서 기준이라, 대부분 줄에서 직접 찾는다.
"""

from __future__ import annotations

import re

from . import parse as P

# 읽기 단계 field.label -> 여기서 쓰는 원시 키
_FIELD_ALIASES = {
    "임금": "wage", "시간급": "wage", "시급": "wage", "월급": "wage", "급여": "wage",
    "근로 시간": "hours", "소정근로시간": "hours", "근로시간": "hours",
    "계약 기간": "period", "계약기간": "period",
    "보증금": "deposit", "차임": "rent",
}

# 줄에서 직접 찾을 때 쓰는 항목 이름 (공백 없이 비교)
_LINE_KEYS = {
    "wage": ["시간급", "시급", "월급", "임금", "급여"],
    "hours": ["소정근로시간", "근로시간", "근무시간"],
    "break": ["휴게시간", "휴게"],
    "workdays": ["근무일", "근로일", "근무요일"],
    "period": ["근로계약기간", "임대차기간", "계약기간", "존속기간"],
    "deposit": ["보증금"],
    "rent": ["월차임", "차임", "월세"],
    "address": ["소재지", "주소", "목적물"],
}
_INCREASE_WORDS = ["인상", "증액", "올린", "올릴", "올리기"]
_INTEREST_WORDS = ["이자", "이율"]


def compact(text: str) -> str:
    return re.sub(r"\s+", "", text or "")


def _blocks(doc) -> list[str]:
    return [b.text for b in (getattr(doc, "blocks", None) or [])]


def _after_key(line: str, key: str) -> str | None:
    """줄에 key(띄어쓰기 무시)가 있으면 그 뒤의 글자. 없으면 None."""
    pattern = r"\s*".join(map(re.escape, key))
    m = re.search(pattern, line)
    return line[m.end():] if m else None


def _segment(line: str, key: str, stops: list[str]) -> str | None:
    """key 뒤에서 다음 항목 이름(stops) 전까지만. '보증금 5천만원 월세 50만원' → '5천만원 '"""
    rest = _after_key(line, key)
    if rest is None:
        return None
    cut = len(rest)
    for s in stops:
        m = re.search(r"\s*".join(map(re.escape, s)), rest)
        if m and m.start() > 0:
            cut = min(cut, m.start())
    return rest[:cut]


def find_line(lines: list[str], keys: list[str], need=None, stops: list[str] = ()) -> tuple[str, int] | None:
    """keys 중 하나가 있는 첫 줄. need(text→값)가 값을 못 만들면 다음 줄을 이어서 본다."""
    for i, line in enumerate(lines):
        for key in keys:
            seg = _segment(line, key, list(stops)) if stops else _after_key(line, key)
            if seg is None:
                continue
            if need is None or need(seg) is not None:
                return seg, i
            if i + 1 < len(lines) and need(lines[i + 1]) is not None:
                return lines[i + 1], i + 1
    return None


def extract(doc) -> dict[str, dict]:
    lines = _blocks(doc)
    full = getattr(doc, "full_text", "") or "\n".join(lines)

    raw: dict[str, tuple[str, int]] = {}
    for f in getattr(doc, "fields", None) or []:
        key = _FIELD_ALIASES.get((f.label or "").strip())
        if key and key not in raw and f.value:
            raw[key] = (f.value, f.line)

    values: dict[str, dict] = {}

    def put(name, value, line, **extra):
        if value is not None:
            values[name] = {"value": value, "line": line, **extra}

    def source(key, need=None, stops=()):
        if key in raw and (need is None or need(raw[key][0]) is not None):
            return raw[key]
        return find_line(lines, _LINE_KEYS[key], need, stops)

    # ── 임금 ──
    found = source("wage", P.parse_money)
    if found:
        txt, line = found
        money = P.parse_money(txt)
        unit_text = compact(txt + (lines[line] if 0 <= line < len(lines) else ""))
        if any(k in unit_text for k in ("시급", "시간급", "시간당")):
            put("hourly_wage", money, line)
        elif "월" in unit_text:
            put("monthly_wage", money, line)
        elif money is not None:
            # 단위가 적혀 있지 않으면 금액 크기로 나눈다 (10만원 넘으면 월급으로 봄)
            put("monthly_wage" if money > 100_000 else "hourly_wage", money, line, unit_guessed=True)

    # ── 근로시간·휴게·근무일 ──
    found = source("hours")
    if found:
        txt, line = found
        whole = lines[line] if 0 <= line < len(lines) else txt
        daily = P.parse_hours_per(whole, "day")
        weekly = P.parse_hours_per(whole, "week")
        span = P.parse_time_range(txt)
        if daily is not None:
            put("daily_hours", daily, line, stated=True)
        if weekly is not None:
            put("weekly_hours", weekly, line, stated=True)
        if span:
            put("work_span_hours", round(max(span[1] - span[0], 0), 2), line)
        if "휴게" in whole:
            put("break_minutes", P.parse_minutes(whole[whole.index("휴게"):]), line)

    if "break_minutes" not in values:
        found = find_line(lines, _LINE_KEYS["break"], P.parse_minutes)
        if found:
            put("break_minutes", P.parse_minutes(found[0]), found[1])

    days = None
    for key in ("workdays", "hours"):
        found = source(key, P.parse_days_per_week) if key == "workdays" else None
        if found:
            days = P.parse_days_per_week(found[0])
            put("days_per_week", days, found[1])
            break
    if days is None:
        d = P.parse_days_per_week(full)
        if d:
            put("days_per_week", d, -1)

    # 하루 근로시간 = 출퇴근 사이 시간 - 휴게. 휴게를 모르면 하루 근로시간을 정하지 않는다.
    if "daily_hours" not in values and "work_span_hours" in values and "break_minutes" in values:
        span_v = values["work_span_hours"]
        put("daily_hours", round(span_v["value"] - values["break_minutes"]["value"] / 60, 2), span_v["line"])
    if "weekly_hours" not in values and "daily_hours" in values and "days_per_week" in values:
        put("weekly_hours", round(values["daily_hours"]["value"] * values["days_per_week"]["value"], 2), values["daily_hours"]["line"])

    if "수습" in full:
        put("probation", True, -1)

    # ── 계약 기간 ──
    found = source("period", P.parse_duration_years)
    if found:
        txt, line = found
        dates = P.parse_dates(txt)
        if dates:
            put("contract_start", dates[0], line)
        years = P.parse_duration_years(txt)
        put("contract_total_years", years, line)
        put("lease_term_years", years, line)
    elif "period" in raw:
        d = P.parse_date(raw["period"][0])
        put("contract_start", d, raw["period"][1])

    # ── 보증금·월세 ──
    found = source("deposit", P.parse_money, stops=_LINE_KEYS["rent"])
    if found:
        put("deposit", P.parse_money(found[0]), found[1])
    found = source("rent", P.parse_money, stops=_LINE_KEYS["deposit"])
    if found:
        put("monthly_rent", P.parse_money(found[0]), found[1])

    # ── 인상률 (가장 높은 것) ──
    best = None
    for i, line in enumerate(lines):
        c = compact(line)
        if any(w in c for w in _INCREASE_WORDS):
            p = P.parse_percent(line)
            if p is not None and (best is None or p > best[0]):
                best = (p, i)
    if best:
        put("rent_increase_ratio", best[0], best[1])

    # ── 이자율 (연으로 바꾼 값 중 가장 높은 것) ──
    best = None
    for i, line in enumerate(lines):
        c = compact(line)
        if any(w in c for w in _INTEREST_WORDS):
            r = P.parse_annual_rate(line)
            if r is not None and (best is None or r > best[0]):
                best = (r, i)
    if best:
        put("annual_interest_rate", best[0], best[1])

    # ── 주소 (소액임차인 지역 구분용) ──
    found = find_line(lines, _LINE_KEYS["address"])
    if found:
        put("address", (lines[found[1]] or "").strip(), found[1])

    return values
