"""인식한 글자 → 문서 종류, 핵심 항목, 읽어줄 요약.

종류는 제목·본문 근거·혼합 서식 규칙으로 먼저 정한다. 근거가 부족하면 unknown으로 남긴다.
항목은 AI(Groq)로 옮겨 적되, 키가 없거나 실패하면 규칙으로 추출한다.

어느 쪽이든 AI는 **문서에 적힌 것을 옮겨 적기만** 한다. 읽어줄 문장은 코드가 항목으로 만든다.
시험해 보니 AI에게 요약 문장을 맡기면 문서에 없는 내용(예: "매일 근무")을 지어냈다.
"""

import json
import re
import unicodedata
from pathlib import Path

from app.models import DocType, Field, TextBlock
from app.services import llm
from app.services.doc_classifier import DocumentClassifier

RULES = json.loads((Path(__file__).resolve().parents[1] / "rules" / "doc_types.json").read_text("utf-8"))
CLASSIFIER = DocumentClassifier(RULES)

MAX_VALUE_LENGTH = 80


def review_speech(pages: list[int]) -> str:
    numbers = ", ".join(str(page + 1) for page in pages)
    return (f"{numbers}페이지의 글자를 충분히 읽지 못했어요. "
            "문서 전체가 보이도록 가까이에서 흔들리지 않게 다시 찍어 주세요. "
            "화면 사진이라면 원본 이미지나 스크린샷을 사용해 주세요.")


def read(lines: list[TextBlock]) -> tuple[DocType, dict[str, int], list[Field], str]:
    """문서 종류, 종류별 근거 점수, 항목, 읽은 방식("ai" 또는 "rules")."""
    full_text = "\n".join(line.text for line in lines)
    classification = CLASSIFIER.classify(lines)
    doc_type, scores = classification.doc_type, classification.scores
    if doc_type == DocType.UNKNOWN:
        return doc_type, scores, [], "rules"
    by_rules = _extract_by_rules(lines, doc_type)
    if llm.available():
        try:
            fields = _read_with_ai(full_text, lines, doc_type)
            # 빈 서식은 규칙이 더 많은 항목을 찾기도 한다.
            if len(fields) >= len(by_rules):
                return doc_type, scores, fields, "ai"
        except llm.LlmError:
            pass
    return doc_type, scores, by_rules, "rules"


def compact(text: str) -> str:
    """OCR 띄어쓰기는 믿기 어려워서 비교할 때는 공백을 지운다."""
    return re.sub(r"\s+", "", text)


def label_of(doc_type: DocType) -> str:
    return RULES.get(doc_type.value, {}).get("label", "알 수 없는 문서")


# --- AI ---------------------------------------------------------------------


def _read_with_ai(full_text: str, lines: list[TextBlock], doc_type: DocType) -> list[Field]:
    labels = json.dumps([f["label"] for f in RULES[doc_type.value]["fields"]], ensure_ascii=False)
    prompt = f"""다음은 종이 문서 사진을 OCR로 읽은 글자다. 여러 페이지를 이어 붙인 **한 문서**이니 페이지마다 따로 나누지 말고 하나로 정리한다. 글자 일부가 깨지거나 띄어쓰기가 틀렸을 수 있다.

1. 문서 종류는 "{doc_type.value}" ({label_of(doc_type)})로 정해져 있다. 종류를 바꾸지 않는다.
2. 다음 항목마다 문서에 적힌 값을 옮겨 적는다: {labels}
   - 문서에 실제로 적힌 내용만 쓴다. 적혀 있지 않으면 null.
   - 숫자, 날짜, 금액은 문서에 적힌 그대로 쓴다. 계산하거나 추측하지 않는다.
   - 띄어쓰기와 명백한 OCR 오타만 바로잡는다.
   - 값은 짧은 구절로 쓴다. 설명이나 의견을 덧붙이지 않는다.

JSON만 출력한다: {{"doc_type": "...", "fields": {{"항목 이름": "값 또는 null"}}}}

OCR 글자:
{full_text}"""
    answer = llm.ask_json(prompt)

    if not isinstance(answer, dict) or answer.get("doc_type") != doc_type.value:
        raise llm.LlmError("AI가 지정된 문서 종류와 다른 응답을 반환했어요")

    values = answer.get("fields") or {}
    if not isinstance(values, dict):
        raise llm.LlmError("AI 항목 응답이 객체가 아니에요")
    fields = []
    for spec in RULES[doc_type.value]["fields"]:
        value = values.get(spec["label"])
        if isinstance(value, str) and value.strip():
            value = value.strip()[:MAX_VALUE_LENGTH]
            line = _line_of(value, lines)
            if line < 0:
                raise llm.LlmError("AI 항목값을 OCR 원문에서 확인하지 못했어요")
            # Matching a number elsewhere (e.g. 식비 instead of 시급) is not
            # evidence for this field. A preceding empty label may own the value.
            labelled = any(value_after(lines[line].text, key) is not None for key in spec["keys"])
            if not labelled and line > 0 and lines[line - 1].page == lines[line].page:
                labelled = any(value_after(lines[line - 1].text, key) == "" for key in spec["keys"])
            if not labelled:
                raise llm.LlmError("AI 항목과 OCR 원문의 항목 이름이 맞지 않아요")
            raw = _find_value(lines, spec["keys"], [compact(k) for f in RULES[doc_type.value]["fields"] for k in f["keys"]])
            if raw and not _evidence_text(raw[0]).startswith(_evidence_text(value)):
                # Also protect rows with several amounts: 시급 5000원 식비 15000원.
                raise llm.LlmError("AI 값이 해당 항목의 원문 값과 달라요")
            fields.append(Field(label=spec["label"], value=value, line=line))
    return fields


def _evidence_text(text: str) -> str:
    text = compact(unicodedata.normalize("NFKC", text)).casefold()
    return re.sub(r"(?<=\d),(?=\d)", "", text)


def _line_of(value: str, lines: list[TextBlock]) -> int:
    """Require copied source evidence, not fuzzy similarity (especially money)."""
    target = _evidence_text(value)
    if not target:
        return -1
    for index, line in enumerate(lines):
        text = _evidence_text(line.text)
        for match in re.finditer(re.escape(target), text):
            # 5,000 must not be accepted from 15,000; keep decimal points/signs.
            if target[0].isdigit() and match.start() and text[match.start()-1] in "0123456789.-":
                continue
            if target[-1].isdigit() and match.end() < len(text) and text[match.end()] in "0123456789.":
                continue
            return index
    return -1


# --- 규칙 -------------------------------------------------------------------


def _extract_by_rules(lines: list[TextBlock], doc_type: DocType) -> list[Field]:
    if doc_type == DocType.UNKNOWN:
        return []
    specs = RULES[doc_type.value]["fields"]
    all_keys = [compact(key) for spec in specs for key in spec["keys"]]
    fields = []
    for spec in specs:
        found = _find_value(lines, spec["keys"], all_keys)
        if found:
            value, index = found
            fields.append(Field(label=spec["label"], value=value, line=index))
    return fields


def _find_value(lines: list[TextBlock], keys: list[str], all_keys: list[str] = ()) -> tuple[str, int] | None:
    # 거래일시 must be tried before 거래일, 보호자성명 before 보호자.
    keys = sorted(keys, key=lambda key: len(compact(key)), reverse=True)
    for key in keys:
        for index, line in enumerate(lines):
            # "위임 업무 재직증명서" is a field, while "조사 결과 보고서"
            # is a heading. A specific leading label can disambiguate a title suffix.
            leading_label = any(
                len(compact(key)) >= 3 and re.match(
                    r"^\s*" + r"\s*".join(map(re.escape, compact(key))) + r"(?=\s|[:：])", line.text
                ) and compact(value_after(line.text, key) or "") not in {
                    "보고서", "요약서", "확인서", "증명서", "서약서", "신청서",
                    "동의서", "위임장", "영수증", "설문지", "청구서", "고지서",
                } for key in keys
            )
            if CLASSIFIER._title_kinds(line.text) and not leading_label:
                continue
            value = value_after(line.text, key)
            if value is None:
                continue
            if key == "금액":
                prefix = re.split(r"금\s*액", line.text, maxsplit=1)[0]
                if re.search(r"[가-힣A-Za-z]", prefix):
                    continue  # 환불 금액/할인 금액 is not an unspecified payment amount.
            # 항목 이름만 있고 값이 다음 줄에 있는 서식이 많다.
            # 단, 다음 줄이 다른 항목 이름이면(표 머리글이 줄마다 따로 읽힌 경우: "수집 목적" 다음 줄 "보유 기간") 값이 아니다
            if not value and index + 1 < len(lines) and lines[index + 1].page == line.page:
                next_text = lines[index + 1].text
                if not CLASSIFIER._title_kinds(next_text) and not re.search(r"[:：]", next_text) and not any(k in compact(next_text) for k in all_keys):
                    value = next_text
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
    # 여러 장은 한 문서의 여러 페이지다. "사진 N장"이라고 하면 문서 N개처럼 들려서 "N페이지짜리 문서"로 말한다
    doc = f"{page_count}페이지짜리 {label}" if page_count > 1 else label
    parts = [f"{doc}{_euro(doc)} 보여요."]
    if fields:
        parts.append(f"중요한 항목 {len(fields)}개를 찾았어요.")
        parts += [f"{f.label}, {f.value}." for f in fields]
    else:
        parts.append("중요한 항목은 찾지 못했어요. 문서가 화면에 다 들어오게 다시 찍어 보세요.")
    return " ".join(parts)
