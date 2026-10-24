"""4단계: check.type마다 함수 하나. 규칙 + 뽑은 값을 받아 Finding 하나(또는 None)를 돌려준다.

- 값이 없어 비교를 못 하면 결과를 만들지 않는다(추측하지 않는다). 기준값이 데이터에 없을 때만 info로 알린다.
- 확신이 낮은 경우(부정문, 법 조문 인용)는 caution이 아니라 info로 낮춘다. 틀린 경고가 놓친 경고보다 해롭다.
- 글자 비교는 모두 공백을 지우고 한다. OCR 띄어쓰기는 믿기 어렵다.
"""

from __future__ import annotations

import re

from . import data as D
from . import facts as F
from .extract import compact

_NEGATIONS = ("아니", "않", "없", "금지", "정하지", "못한다")
_ARTICLE_RE = re.compile(r"제\d+조")


# ── 공통 ──────────────────────────────────────────────────────────────────


def _excerpt(text: str, paragraph: str | None) -> str:
    """조문에서 해당 항(①②…) 한 문단만. 항이 없으면 앞부분."""
    text = text or ""
    if paragraph:
        marks = "①②③④⑤⑥⑦⑧⑨⑩"
        parts = re.split(f"(?=[{marks}])", text)
        picked = [p.strip() for p in parts if p and p[0] in paragraph]
        if picked:
            return "\n".join(picked)[:500]
    return text[:300]


def resolve_refs(refs: list[dict]) -> list[dict]:
    idx = D.laws_index()
    out = []
    for ref in refs:
        art = idx.get((ref.get("law_id", ""), ref.get("article_no", "")))
        out.append({
            "law_name": (art or ref).get("law_name", ""),
            "article_no": ref.get("article_no", ""),
            "title": (art or ref).get("title", ""),
            "excerpt": _excerpt(art["text"], ref.get("paragraph")) if art else "",
            "url": (art["url"] if art else ref.get("official_url", "")),
        })
    return out


def _base(rule: dict, level: str) -> dict:
    # 심각도가 info인 규칙은 경고가 아니라 안내로 내보낸다. 규칙에 level이 정해져 있으면 그걸 쓴다.
    if level == "caution" and (rule.get("severity") == "info" or rule.get("level") == "info"):
        level = "info"
    return {
        "level": level,
        "item": rule["title"],
        "reason": "",
        "evidence": "",
        "rule_id": rule["id"],
        "severity": rule.get("severity", "info"),
        "line": -1,
        "speech": "",
        "basis": resolve_refs(rule.get("refs", [])),
    }


def _fill(template: str, **kw) -> str:
    out = template
    for k, v in kw.items():
        out = out.replace("{" + k + "}", str(v))
    return out


def _fmt(v, fact: dict) -> str:
    """비율은 %, 금액은 쉼표."""
    unit = fact.get("unit", "")
    if isinstance(v, float) and ("비율" in unit or "이자율" in unit):
        pct = v * 100
        return f"{pct:.0f}" if abs(pct - round(pct)) < 0.05 else f"{pct:.1f}"
    if isinstance(v, (int, float)):
        return f"{v:,.0f}" if float(v).is_integer() else f"{v:,.2f}".rstrip("0").rstrip(".")
    return str(v)


def _evidence(doc, line: int) -> str:
    blocks = getattr(doc, "blocks", None) or []
    return blocks[line].text if 0 <= line < len(blocks) else ""


def _item_present(text: str, spec) -> bool:
    if isinstance(spec, dict) and "regex" in spec:
        return re.search(spec["regex"], text) is not None
    return any(compact(s) in text for s in spec)


# ── check.type별 ──────────────────────────────────────────────────────────


def eval_required_items(rule: dict, doc, values: dict) -> dict | None:
    flat = compact(doc.full_text)
    missing = [item for item, spec in rule["check"]["items"].items() if not _item_present(flat, spec)]
    if not missing:
        return None
    r = _base(rule, "missing")
    r["reason"] = f"{', '.join(missing)} 항목을 문서에서 찾지 못함"
    r["speech"] = _fill(rule["tts"], missing=", ".join(missing))
    return r


def eval_conditional_required(rule: dict, doc, values: dict) -> dict | None:
    flat = compact(doc.full_text)
    if not any(compact(w) in flat for w in rule["check"]["when"]):
        return None
    # 정규식은 띄어쓰기를 살린 원문에서, 동의어는 공백을 지운 글자에서 찾는다
    raw = doc.full_text or ""
    missing = [item for item, spec in rule["check"]["items"].items()
               if not _item_present(raw if isinstance(spec, dict) else flat, spec)]
    if not missing:
        return None
    r = _base(rule, "missing")
    r["reason"] = f"{', '.join(missing)} 항목을 문서에서 찾지 못함"
    r["speech"] = _fill(rule["tts"], missing=", ".join(missing))
    return r


def eval_numeric_min(rule: dict, doc, values: dict) -> dict | None:
    check = rule["check"]
    v = values.get(check["field"])
    if not v or v.get("value") is None:
        return None
    year = F.pick_year(values.get("contract_start", {}).get("value"))
    fact = F.fact_value(check["fact"], year)
    if not fact:
        if "{year}" in check["fact"]:
            r = _base(rule, "info")
            r["reason"] = f"{year}년 기준값이 데이터에 없어 비교하지 못함"
            r["line"] = v.get("line", -1)
            r["evidence"] = _evidence(doc, r["line"])
            r["speech"] = f"{year}년 기준이 아직 데이터에 없어서 {rule['title']} 여부를 비교하지 못했어요."
            return r
        return None
    if v["value"] >= fact["value"]:
        return None
    r = _base(rule, "caution")
    notes = []
    if v.get("derived"):
        notes.append("월급을 시급으로 환산함")
    if not values.get("contract_start"):
        notes.append("계약 시작일을 찾지 못해 올해 기준으로 비교함")
    if rule["id"] == "LAB-003" and values.get("probation"):
        notes.append("수습 기간이면 3개월까지 90%가 기준일 수 있음")
    r["reason"] = f"문서 {_fmt(v['value'], fact)} / 기준 {_fmt(fact['value'], fact)}" + (f" ({', '.join(notes)})" if notes else "")
    r["line"] = v.get("line", -1)
    r["evidence"] = _evidence(doc, r["line"])
    r["speech"] = _fill(rule["tts"], value=_fmt(v["value"], fact), year=year, limit=_fmt(fact["value"], fact))
    return r


def eval_numeric_max(rule: dict, doc, values: dict) -> dict | None:
    check = rule["check"]
    pairs = list(check.get("fields", {}).items())
    if "field" in check:
        pairs.append((check["field"], check["fact"]))
    year = F.pick_year(values.get("contract_start", {}).get("value"))
    for field, fact_key in pairs:
        v = values.get(field)
        fact = F.fact_value(fact_key, year)
        if not v or v.get("value") is None or not fact or not isinstance(fact.get("value"), (int, float)):
            continue  # 기준이 수식(전환율 등)이면 지금은 비교하지 않는다
        if v["value"] <= fact["value"]:
            continue
        r = _base(rule, "caution")
        r["reason"] = f"문서 {_fmt(v['value'], fact)} / 기준 {_fmt(fact['value'], fact)} {fact.get('unit', '')}".strip()
        r["line"] = v.get("line", -1)
        r["evidence"] = _evidence(doc, r["line"])
        r["speech"] = _fill(rule["tts"], value=_fmt(v["value"], fact), limit=_fmt(fact["value"], fact), year=year)
        return r
    return None


def eval_forbidden_clause(rule: dict, doc, values: dict) -> dict | None:
    check = rule["check"]
    keywords = [compact(k) for k in check["keywords"]]
    context = [compact(k) for k in check.get("context_any", [])]
    lines = [b.text for b in (getattr(doc, "blocks", None) or [])]

    # 한 줄씩, 그리고 OCR이 문장을 두 줄로 쪼갠 경우를 위해 이웃한 두 줄을 이어서도 본다
    candidates = [(i, i, lines[i]) for i in range(len(lines))]
    candidates += [(i, i + 1, lines[i] + " " + lines[i + 1]) for i in range(len(lines) - 1)]

    for first, last, text in candidates:
        flat = compact(text)
        hit = next((k for k in keywords if k in flat), None)
        if not hit:
            continue
        if last > first and (hit in compact(lines[first]) or hit in compact(lines[last])):
            continue  # 한 줄에서 이미 본 경우
        rest = flat.replace(hit, "")
        if context and not any(c in flat for c in context):
            continue
        if not check.get("skip_negation") and any(n in rest for n in _NEGATIONS):
            continue  # "위약금을 정하지 아니한다" 같은 문장은 경고하지 않음
        evidence = text.strip()
        if "법" in flat and _ARTICLE_RE.search(flat):
            r = _base(rule, "info")
            r["reason"] = "법 조문을 인용한 문장으로 보임"
            r["evidence"] = evidence
            r["line"] = first
            r["speech"] = f"{rule['title']}과 관련된 문장이 있지만 법 조문을 인용하고 있어요. 내용을 한번 들어 보세요."
            return r
        r = _base(rule, "caution")
        r["reason"] = "확인이 필요한 표현이 들어 있는 문장"
        r["evidence"] = evidence
        r["line"] = first
        r["speech"] = rule["tts"]
        return r
    return None


def eval_info(rule: dict, doc, values: dict) -> dict | None:
    triggers = rule["check"].get("trigger_keywords", [])
    if not triggers:
        return None  # 조건 없는 안내는 근거 듣기용으로만 둔다
    flat = compact(doc.full_text)
    hit = next((t for t in triggers if compact(t) in flat), None)
    if not hit:
        return None
    r = _base(rule, "info")
    r["reason"] = f"문서에 '{hit}'이(가) 있어 안내"
    for i, b in enumerate(getattr(doc, "blocks", None) or []):
        if compact(hit) in compact(b.text):
            r["line"], r["evidence"] = i, b.text
            break
    r["speech"] = rule["tts"]
    return r


# ── custom ────────────────────────────────────────────────────────────────


def custom_break_time(rule: dict, doc, values: dict) -> dict | None:
    """근로시간 4시간이면 30분, 8시간이면 1시간 이상 (근로기준법 제54조)."""
    hours = values.get("daily_hours", {}).get("value")
    brk = values.get("break_minutes")
    if hours is None or not brk:
        return None
    facts = D.facts()
    need = facts["break_8h"]["value"] if hours >= 8 else facts["break_4h"]["value"] if hours >= 4 else 0
    if brk["value"] >= need:
        return None
    r = _base(rule, "caution")
    r["reason"] = f"하루 {hours:g}시간 근로, 휴게 {brk['value']}분 / 기준 {need}분 이상"
    r["line"] = brk.get("line", -1)
    r["evidence"] = _evidence(doc, r["line"])
    r["speech"] = _fill(rule["tts"], hours=f"{hours:g}", value=brk["value"], limit=need)
    return r


# 소액임차인 지역 구분 (주택임대차보호법 시행령 제10조·제11조). 경계가 걸치는 곳(인천, 남양주, 시흥 등)은 정하지 않는다.
_REGIONS = [
    ("서울특별시", ["서울"]),
    ("과밀억제권역·세종·용인·화성·김포", ["세종", "용인", "화성", "김포", "수원", "성남", "안양", "부천", "광명", "과천", "의왕", "군포", "의정부", "구리", "하남", "고양"]),
    ("광역시·안산·광주·파주·이천·평택", ["부산", "대구", "광주광역시", "대전", "울산", "안산", "파주", "이천", "평택", "경기도광주", "경기광주"]),
]
_AMBIGUOUS = ["인천", "남양주", "시흥"]
_PROVINCES = ["경기", "강원", "충청", "충북", "충남", "전라", "전북", "전남", "경상", "경북", "경남", "제주"]


def region_of(address: str) -> str | None:
    a = compact(address)
    if any(x in a for x in _AMBIGUOUS):
        return None
    for name, keys in _REGIONS:
        if any(k in a for k in keys):
            return name
    if "광주" in a:
        return None  # 광주광역시와 경기 광주시를 구분할 수 없음
    if any(p in a for p in _PROVINCES):
        return "그 밖의 지역"
    return None


def custom_small_deposit(rule: dict, doc, values: dict) -> dict | None:
    deposit = values.get("deposit")
    if not deposit:
        return None
    table = D.facts()[rule["check"]["fact"]]["value"]
    region = region_of(values.get("address", {}).get("value", "") or "")
    r = _base(rule, "info")
    r["line"] = deposit.get("line", -1)
    r["evidence"] = _evidence(doc, r["line"])
    note = D.facts()[rule["check"]["fact"]].get("note", "")
    if region:
        row = table[region]
        if deposit["value"] > row["보증금_상한"]:
            return None
        r["reason"] = f"{region} 기준 보증금 {row['보증금_상한']:,}원 이하 → 최우선변제 {row['최우선변제액']:,}원까지. {note}"
        r["speech"] = _fill(rule["tts"], limit=f"{row['보증금_상한']:,}", priority=f"{row['최우선변제액']:,}")
        return r
    lowest = min(v["보증금_상한"] for v in table.values())
    if deposit["value"] > max(v["보증금_상한"] for v in table.values()):
        return None
    r["reason"] = f"주소로 지역을 정하지 못함. 지역별 보증금 상한 {lowest:,}원~{table['서울특별시']['보증금_상한']:,}원. {note}"
    r["speech"] = "보증금 금액에 따라 집이 경매로 넘어가도 일부를 먼저 돌려받을 수 있는 경우가 있어요. 지역마다 기준이 달라서 확인이 필요해요."
    return r


CUSTOM = {"break_time": custom_break_time, "small_deposit": custom_small_deposit}


def eval_custom(rule: dict, doc, values: dict) -> dict | None:
    fn = CUSTOM.get(rule["check"].get("fn", ""))
    return fn(rule, doc, values) if fn else None


EVALUATORS = {
    "required_items": eval_required_items,
    "conditional_required": eval_conditional_required,
    "numeric_min": eval_numeric_min,
    "numeric_max": eval_numeric_max,
    "forbidden_clause": eval_forbidden_clause,
    "info": eval_info,
    "custom": eval_custom,
}


def run_rule(rule: dict, doc, values: dict) -> dict | None:
    fn = EVALUATORS.get(rule["check"]["type"])
    if not fn:
        return None
    return fn(rule, doc, values)
