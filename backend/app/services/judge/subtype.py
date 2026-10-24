"""1단계: contract 문서의 세부 종류를 정한다. (근로계약/임대차/대부/소비자 등)

읽기 단계의 문서 종류 구분과 같은 방식: 핵심어 개수를 세고, 2번 미만이면 고르지 않는다.
"""

from __future__ import annotations

from . import data as D


def determine_subtype(doc) -> str:
    """doc_type이 contract일 때만 세부 종류를 고른다. 아니면 빈 문자열."""
    if getattr(doc, "doc_type", None) != "contract":
        return ""

    text = doc.full_text or ""
    scores: dict[str, int] = {}
    for name, keywords in D.subtypes().items():
        scores[name] = sum(text.count(k) for k in keywords)

    if not scores:
        return ""
    best = max(scores, key=scores.get)
    if scores[best] < 2:
        return ""
    return best
