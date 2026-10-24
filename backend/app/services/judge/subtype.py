"""1단계: 문서의 세부 종류를 정한다. (근로계약/임대차/대부/소비자 등)

- contract: 핵심어(judge_subtypes.json)가 몇 번 나왔는지 세서 가장 많은 종류. 2번 미만이면 고르지 않는다.
- consent, notice: 읽기 단계의 문서 종류가 곧 세부 종류다(동의서 규칙, 가정통신문 규칙).
- 글자 비교는 공백을 지우고 한다. OCR 띄어쓰기는 믿기 어렵다.
"""

from __future__ import annotations

import re

from . import data as D


def _doc_type(doc) -> str:
    t = getattr(doc, "doc_type", "")
    return getattr(t, "value", t) or ""


def scores(doc) -> dict[str, int]:
    text = re.sub(r"\s+", "", doc.full_text or "")
    return {name: sum(text.count(re.sub(r"\s+", "", k)) for k in kws) for name, kws in D.subtypes().items()}


def determine_subtype(doc) -> str:
    dt = _doc_type(doc)
    if dt in ("consent", "notice"):
        return dt
    if dt != "contract":
        return ""
    s = scores(doc)
    if not s:
        return ""
    best = max(s, key=s.get)  # 동점이면 파일에서 앞선 종류
    return best if s[best] >= 2 else ""
