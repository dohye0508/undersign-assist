"""4단계: check.type마다 함수 하나. 규칙 + 뽑은 값을 받아 Finding 하나(또는 None)를 돌려준다.

값이 없어 비교를 못 하면 결과를 만들지 않는다(추측하지 않는다).
확신이 낮은 경우(부정문, 법 조문 인용)는 caution이 아니라 info로 낮춘다.
"""

from __future__ import annotations

import re

from . import data as D
from . import facts as F

_NEGATIONS = ("아니", "않", "없", "금지", "불가", "정하지")
_ARTICLE_RE = re.compile(r"제\s*\d+\s*조")


def _resolve_refs(rule: dict) -> list[dict]:
    idx = D.laws_index()
    out = []
    for ref in rule.get("refs", []):
        art = idx.get((ref.get("law_id", ""), ref.get("article_no", "")))
        if art:
            out.append({
                "law_name": art["law_name"],
                "article_no": art["article_no"],
                "title": art["title"],
                "excerpt": (art["text"] or "")[:300],
                "url": art["url"],
            })
        else:
            out.append({
                "law_name": ref.get("law_name", ""),
                "article_no": ref.get("article_no", ""),
                "title": ref.get("title", ""),
                "excerpt": "",
                "url": ref.get("official_url", ""),
            })
    return out


def _base(rule: dict, level: str) -> dict:
    return {
        "level": level,
        "item": rule["title"],
        "reason": "",
        "evidence": "",
        "rule_id": rule["id"],
        "severity": rule.get("severity", "info"),
        "line": -1,
        "speech": "",
        "basis": _resolve_refs(rule),
    }


def eval_required_items(rule: dict, doc, values: dict) -> dict | None:
    text = (doc.full_text or "").replace(" ", "").replace("\n", "")
    missing = []
    for item, synonyms in rule["check"]["items"].items():
        if not any(s.replace(" ", "") in text for s in synonyms):
            missing.append(item)
    if not missing:
        return None
    r = _base(rule, "missing")
    r["reason"] = f"{', '.join(missing)} 항목이 문서에서 보이지 않음"
    r["speech"] = rule["tts"].replace("{missing}", ", ".join(missing))
    return r


def eval_numeric_min(rule: dict, doc, values: dict) -> dict | None:
    field = rule["check"]["field"]
    v = values.get(field)
    if not v or v.get("value") is None:
        return None
    start = values.get("contract_start", {}).get("value")
    year = F.pick_year(start)
    fact = F.fact_value(rule["check"]["fact"], year)
    if not fact:
        return None
    if v["value"] >= fact["value"]:
        return None
    r = _base(rule, "caution")
    note = " (월급을 시급으로 환산함)" if v.get("derived") else ""
    r["reason"] = f"문서 값 {v['value']:,} / {year}년 기준 {fact['value']:,}{note}"
    r["line"] = v.get("line", -1)
    r["speech"] = rule["tts"].format(value=f"{v['value']:,}", year=year, limit=f"{fact['value']:,}")
    return r


def eval_numeric_max(rule: dict, doc, values: dict) -> dict | None:
    hit = None
    for field, fact_key in rule["check"].get("fields", {}).items():
        v = values.get(field)
        fact = D.facts().get(fact_key)
        if not v or not fact or v.get("value") is None:
            continue
        if v["value"] > fact["value"]:
            hit = (field, v, fact)
            break
    if not hit:
        return None
    field, v, fact = hit
    r = _base(rule, "caution")
    r["reason"] = f"{field} {v['value']} / 기준 {fact['value']}"
    r["line"] = v.get("line", -1)
    r["speech"] = rule["tts"].format(value=v["value"], limit=fact["value"], year="")
    return r


def eval_forbidden_clause(rule: dict, doc, values: dict) -> dict | None:
    keywords = rule["check"]["keywords"]
    for block in getattr(doc, "blocks", []) or []:
        line_text = block.text
        if not any(k in line_text for k in keywords):
            continue
        if any(n in line_text for n in _NEGATIONS):
            continue  # 부정문: "위약금을 정하지 아니한다" 같은 문장은 경고하지 않음
        if "법" in line_text and _ARTICLE_RE.search(line_text):
            r = _base(rule, "info")
            r["reason"] = "법 조문을 인용한 문장으로 보임, 확인 필요"
            r["evidence"] = line_text
            r["speech"] = f"{rule['title']}과 관련된 문구가 있지만 법 조문을 인용하고 있어요. 확인해보세요."
            return r
        r = _base(rule, "caution")
        r["reason"] = "금지된 표현으로 보이는 문장 발견"
        r["evidence"] = line_text
        r["speech"] = rule["tts"]
        return r
    return None


def eval_info(rule: dict, doc, values: dict) -> dict | None:
    text = doc.full_text or ""
    keywords = rule["check"].get("trigger_keywords", [])
    if not any(k in text for k in keywords):
        return None
    r = _base(rule, "info")
    r["reason"] = "참고 안내"
    r["speech"] = rule["tts"]
    return r


EVALUATORS = {
    "required_items": eval_required_items,
    "numeric_min": eval_numeric_min,
    "numeric_max": eval_numeric_max,
    "forbidden_clause": eval_forbidden_clause,
    "info": eval_info,
}


def run_rule(rule: dict, doc, values: dict) -> dict | None:
    fn = EVALUATORS.get(rule["check"]["type"])
    if not fn:
        return None
    return fn(rule, doc, values)
