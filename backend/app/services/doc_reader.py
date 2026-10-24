"""인식한 글자 → 문서 종류, 핵심 항목, 읽어줄 요약.

AI가 아니라 규칙으로 판단한다: 문서 종류는 `rules/doc_types.json`의 핵심어가 몇 개 나왔는지로,
항목은 항목 이름(예: 시급)이 있는 줄에서 그 뒤의 값을 가져온다. 규칙 파일만 고치면 문서 종류를 늘릴 수 있다.
"""

import json
import re
from pathlib import Path

from app.models import DocType, Field, TextBlock

RULES = json.loads((Path(__file__).resolve().parents[1] / "rules" / "doc_types.json").read_text("utf-8"))

# 이 개수보다 적게 나오면 종류를 단정하지 않는다
MIN_KEYWORD_HITS = 2
MAX_VALUE_LENGTH = 60


def compact(text: str) -> str:
    """OCR 띄어쓰기는 믿기 어려워서 비교할 때는 공백을 지운다."""
    return re.sub(r"\s+", "", text)


def classify(full_text: str) -> tuple[DocType, dict[str, int]]:
    text = compact(full_text)
    scores = {kind: sum(text.count(k) for k in rule["keywords"]) for kind, rule in RULES.items()}
    best = max(scores, key=scores.get)
    if scores[best] < MIN_KEYWORD_HITS:
        return DocType.UNKNOWN, scores
    return DocType(best), scores


def label_of(doc_type: DocType) -> str:
    return RULES.get(doc_type.value, {}).get("label", "알 수 없는 문서")


def extract_fields(lines: list[TextBlock], doc_type: DocType) -> list[Field]:
    if doc_type == DocType.UNKNOWN:
        return []
    fields = []
    for spec in RULES[doc_type.value]["fields"]:
        found = _find_value(lines, spec["keys"])
        if found:
            value, index = found
            fields.append(Field(label=spec["label"], value=value, line=index))
    return fields


def _find_value(lines: list[TextBlock], keys: list[str]) -> tuple[str, int] | None:
    for index, line in enumerate(lines):
        for key in keys:
            value = value_after(line.text, key)
            if value is None:
                continue
            # 항목 이름만 있고 값이 다음 줄에 있는 서식이 많다
            if not value and index + 1 < len(lines):
                value = lines[index + 1].text
            if value:
                return value[:MAX_VALUE_LENGTH], index
    return None


def value_after(text: str, key: str) -> str | None:
    """줄에 key가 있으면 그 뒤의 글자를 돌려준다(띄어쓰기 무시). 없으면 None."""
    pattern = r"\s*".join(map(re.escape, key))
    match = re.search(pattern, text)
    if not match:
        return None
    return text[match.end():].strip(" :：.)]-|\t")


def _euro(word: str) -> str:
    """받침에 따라 '로'/'으로'를 고른다 (ㄹ 받침은 '로')."""
    code = ord(word[-1]) - 0xAC00
    if not 0 <= code <= 11171:
        return "로"
    final = code % 28
    return "로" if final in (0, 8) else "으로"


def build_speech(doc_type: DocType, fields: list[Field], lines: list[TextBlock]) -> str:
    if not lines:
        return "글자를 찾지 못했어요. 문서가 화면에 다 들어오게 다시 찍어 주세요."
    if doc_type == DocType.UNKNOWN:
        opening = " ".join(line.text for line in lines[:3])
        return f"어떤 문서인지 알아내지 못했어요. 처음 부분을 읽어드릴게요. {opening}"

    label = label_of(doc_type)
    parts = [f"{label}{_euro(label)} 보여요."]
    if fields:
        parts += [f"{f.label}, {f.value}." for f in fields]
    else:
        parts.append("중요한 항목은 찾지 못했어요. 전체 듣기로 내용을 들어 보세요.")
    return " ".join(parts)
