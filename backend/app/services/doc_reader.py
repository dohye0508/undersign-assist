"""인식한 글자 → 문서 종류, 핵심 항목, 읽어줄 요약.

두 가지 방식이 있다.
- AI(Groq): 글자를 주고 문서 종류와 항목 값을 JSON으로 받는다. 깨진 글자나 문장 중간에 걸친 값도 자연스럽게 정리한다.
- 규칙: `rules/doc_types.json`의 핵심어 수로 종류를 고르고, 항목 이름 뒤의 글자를 잘라 값으로 쓴다.
AI를 쓸 수 없으면(키 없음, 실패) 규칙으로 돌아간다.

어느 쪽이든 AI는 **문서에 적힌 것을 옮겨 적기만** 한다. 읽어줄 문장은 코드가 항목으로 만든다.
시험해 보니 AI에게 요약 문장을 맡기면 문서에 없는 내용(예: "매일 근무")을 지어냈다.
"""

import json
import re
from difflib import SequenceMatcher
from pathlib import Path

from app.models import DocType, Field, TextBlock
from app.services import llm

RULES = json.loads((Path(__file__).resolve().parents[1] / "rules" / "doc_types.json").read_text("utf-8"))

# 이 개수보다 적게 나오면 종류를 단정하지 않는다
MIN_KEYWORD_HITS = 2
MAX_VALUE_LENGTH = 80


def read(lines: list[TextBlock]) -> tuple[DocType, dict[str, int], list[Field], str]:
    """문서 종류, 종류별 핵심어 수, 항목, 읽은 방식("ai" 또는 "rules")."""
    full_text = "\n".join(line.text for line in lines)
    scores = keyword_scores(full_text)
    if lines and llm.available():
        try:
            doc_type, fields = _read_with_ai(full_text, lines)
            return doc_type, scores, fields, "ai"
        except llm.LlmError:
            pass
    doc_type = _classify_by_keywords(scores)
    return doc_type, scores, _extract_by_rules(lines, doc_type), "rules"


def compact(text: str) -> str:
    """OCR 띄어쓰기는 믿기 어려워서 비교할 때는 공백을 지운다."""
    return re.sub(r"\s+", "", text)


def keyword_scores(full_text: str) -> dict[str, int]:
    text = compact(full_text)
    return {kind: sum(text.count(k) for k in rule["keywords"]) for kind, rule in RULES.items()}


def label_of(doc_type: DocType) -> str:
    return RULES.get(doc_type.value, {}).get("label", "알 수 없는 문서")


# --- AI ---------------------------------------------------------------------


def _read_with_ai(full_text: str, lines: list[TextBlock]) -> tuple[DocType, list[Field]]:
    kinds = "\n".join(
        f'- "{kind}" ({rule["label"]}): 항목 {json.dumps([f["label"] for f in rule["fields"]], ensure_ascii=False)}'
        for kind, rule in RULES.items()
    )
    prompt = f"""다음은 종이 문서 사진을 OCR로 읽은 글자다. 글자 일부가 깨지거나 띄어쓰기가 틀렸을 수 있다.

1. 문서 종류를 아래에서 하나 고른다. 어느 것도 아니면 "unknown".
{kinds}
2. 고른 종류의 항목마다 문서에 적힌 값을 옮겨 적는다.
   - 문서에 실제로 적힌 내용만 쓴다. 적혀 있지 않으면 null.
   - 숫자, 날짜, 금액은 문서에 적힌 그대로 쓴다. 계산하거나 추측하지 않는다.
   - 띄어쓰기와 명백한 OCR 오타만 바로잡는다.
   - 값은 짧은 구절로 쓴다. 설명이나 의견을 덧붙이지 않는다.

JSON만 출력한다: {{"doc_type": "...", "fields": {{"항목 이름": "값 또는 null"}}}}

OCR 글자:
{full_text}"""
    answer = llm.ask_json(prompt)

    try:
        doc_type = DocType(answer.get("doc_type", "unknown"))
    except ValueError:
        doc_type = DocType.UNKNOWN
    if doc_type == DocType.UNKNOWN:
        return doc_type, []

    values = answer.get("fields") or {}
    fields = []
    for spec in RULES[doc_type.value]["fields"]:
        value = values.get(spec["label"])
        if isinstance(value, str) and value.strip():
            value = value.strip()[:MAX_VALUE_LENGTH]
            fields.append(Field(label=spec["label"], value=value, line=_line_of(value, lines)))
    return doc_type, fields


def _line_of(value: str, lines: list[TextBlock]) -> int:
    """AI가 정리한 값이 사진의 어느 줄에서 왔는지 찾는다 (사진 위 표시용). 못 찾으면 -1."""
    target = compact(value)
    best, best_index = 0.0, -1
    for index, line in enumerate(lines):
        text = compact(line.text)
        match = SequenceMatcher(None, target, text).find_longest_match(0, len(target), 0, len(text))
        score = match.size / max(len(target), 1)
        if score > best:
            best, best_index = score, index
    return best_index if best >= 0.4 else -1


# --- 규칙 -------------------------------------------------------------------


def _classify_by_keywords(scores: dict[str, int]) -> DocType:
    best = max(scores, key=scores.get)
    if scores[best] < MIN_KEYWORD_HITS:
        return DocType.UNKNOWN
    return DocType(best)


def _extract_by_rules(lines: list[TextBlock], doc_type: DocType) -> list[Field]:
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


# --- 읽어줄 문장 -------------------------------------------------------------


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
    # 페이지 수는 줄의 page 번호(0부터)로 센다. 사진 한 장이면 1
    page_count = max(line.page for line in lines) + 1
    # 화면의 쉬운 설명 문장과 같은 투로 시작한다: 무엇으로 보이고, 몇 장을 읽어 몇 개를 찾았는지
    parts = [f"{label}{_euro(label)} 보여요."]
    if fields:
        parts.append(f"사진 {page_count}장, 중요한 항목 {len(fields)}개를 찾았어요.")
        parts += [f"{f.label}, {f.value}." for f in fields]
    else:
        parts.append(f"사진 {page_count}장을 읽었지만 중요한 항목은 찾지 못했어요. 문서가 화면에 다 들어오게 다시 찍어 보세요.")
    return " ".join(parts)
