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


def _findings(rules: list[dict], document, values: dict, answers: dict[str, str]) -> list[dict]:
    """규칙을 돌린다. applies_if가 있는 규칙은 답이 조건과 같을 때만 돌린다(모름·무응답이면 건너뜀)."""
    out: list[dict] = []
    for rule in rules:
        cond = rule.get("applies_if")
        if cond and any(answers.get(q) != want for q, want in cond.items()):
            continue
        result = Ev.run_rule(rule, document, values)
        if result:
            out.append(result)
    return out


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

    # 답이 결과를 바꾸지 못하는 질문은 묻지 않는다.
    # 아직 답이 없는 질문마다, 그 질문에 걸린 규칙들을 yes/no 양쪽으로 돌려 보고 결과가 같으면
    # 질문을 뺀다. (예: 근로계약서에 근로시간 초과·수당 배제 내용이 없으면 "5명 이상?"은 묻지 않는다)
    effective = dict(answers)
    for q in questions:
        qid = q["id"]
        if effective.get(qid) in ("yes", "no"):
            continue
        depends = [r for r in rules if qid in (r.get("applies_if") or {})]
        outcomes = []
        for option in ("yes", "no"):
            trial = dict(effective)
            trial[qid] = option
            # 같은 규칙에 걸린 다른 미답 질문은 "규칙이 돌아가는 쪽"으로 가정한다.
            # 그래야 "이 질문의 답이 결과를 바꿀 수 있는가"만 따로 볼 수 있다.
            for r in depends:
                for other, want in (r.get("applies_if") or {}).items():
                    if other != qid and trial.get(other) not in ("yes", "no"):
                        trial[other] = want
            outcomes.append(_findings(depends, document, values, trial))
        if outcomes[0] == outcomes[1]:
            # 어느 답이든 결과가 같으므로 아무 쪽을 써도 된다. 규칙의 applies_if가 바라는 쪽("규칙을 돌리는 쪽")을
            # 고른다. 답이 없으면 규칙을 건너뛰는 아래 _findings 로직은 그대로 두고, 답이 "정해진 것"으로만 다룬다.
            effective[qid] = next(
                (r["applies_if"][qid] for r in depends if r.get("applies_if", {}).get(qid) in ("yes", "no")),
                "yes",
            )

    findings = _findings(rules, document, values, effective)

    counts: dict[str, int] = {}
    for f in findings:
        counts[f["level"]] = counts.get(f["level"], 0) + 1

    pending = [q for q in questions if effective.get(q["id"]) not in ("yes", "no")]
    return {
        "findings": findings,
        "speech": Sp.build_summary(findings),
        "subtype": doc_subtype,
        "counts": counts,
        "questions": pending,
        "disclaimer": Sp.DISCLAIMER,
    }
