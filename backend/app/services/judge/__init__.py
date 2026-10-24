"""판단 파이프라인: 세부 종류 정하기 -> 값 뽑기 -> 규칙 고르기 -> 규칙 실행 -> 근거 붙이기 -> 안내 문장.

AI는 쓰지 않는다. 전부 규칙과 수식이다. (undersign-assist 판단 단계 논리 구조 설계 문서 기준)
"""

from __future__ import annotations

from . import data as D
from . import evaluators as Ev
from . import extract as E
from . import facts as F
from . import speech as Sp
from . import subtype as S


def run(document, answers: dict[str, str] | None = None) -> dict:
    answers = answers or {}

    doc_subtype = S.determine_subtype(document)
    values = E.extract(document)

    # 근로계약서는 주 근로시간을 계산해 15시간 미만이면 단시간으로 재분류한다.
    if doc_subtype == "labor_full_time" and "daily_hours" in values:
        weekly = values.get("weekly_hours", {}).get("value") or values["daily_hours"]["value"] * values.get("days_per_week", {}).get("value", 5)
        if weekly < 15:
            doc_subtype = "labor_part_time"

    # 월급만 있고 시급이 없으면 환산해서 hourly_wage를 만든다 (근거에 환산 사실을 남김).
    if "hourly_wage" not in values and "monthly_wage" in values:
        weekly_hours = values.get("daily_hours", {}).get("value", 8) * 5
        monthly = values["monthly_wage"]["value"]
        values["hourly_wage"] = {
            "value": round(F.hourly_from_monthly(monthly, weekly_hours)),
            "line": values["monthly_wage"]["line"],
            "derived": True,
        }

    rules = D.rules_for(doc_subtype)
    questions = D.questions_for(rules)
    findings: list[dict] = []
    for rule in rules:
        cond = rule.get("applies_if")
        if cond and any(answers.get(q) != want for q, want in cond.items()):
            continue  # 모름이거나 답이 없으면 이 규칙은 돌리지 않고 질문으로 묻는다
        result = Ev.run_rule(rule, document, values)
        if result:
            findings.append(result)

    counts: dict[str, int] = {}
    for f in findings:
        counts[f["level"]] = counts.get(f["level"], 0) + 1

    pending = [q for q in questions if answers.get(q["id"]) not in ("yes", "no")]
    return {
        "findings": findings,
        "speech": Sp.build_summary(findings),
        "subtype": doc_subtype,
        "counts": counts,
        "questions": pending,
        "disclaimer": Sp.DISCLAIMER,
    }
