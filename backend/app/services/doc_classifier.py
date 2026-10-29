"""OCR text classification using titles and independent evidence, without an API call.

Repeated words, overlapping synonyms and duplicated pages count only once per
evidence group. A title is stronger than incidental mentions in the body. The
first page decides the main form; a privacy appendix does not replace it.
Scores are diagnostic evidence weights, not probabilities.
"""

import re
import unicodedata
from dataclasses import dataclass

from app.models import DocType, TextBlock

TITLE_WEIGHT = 10
GROUP_WEIGHT = 2
MIN_MARGIN = 2
HEADER_LINES = 8

# These describe documents rather than being a document to complete/sign.
_REFERENCE_HEADINGS = (
    "제출서류목록", "구비서류목록", "개인정보처리방침", "개인정보보호교육자료",
    "계약서작성방법안내", "계약서작성안내", "계약서작성요령", "계약서작성가이드",
)
_FIELD_PREFIXES = ("제출서류", "구비서류", "준비물", "교육내용", "작품명", "작품요약", "예시문서")


def _unicode_text(text: str) -> str:
    # Remove zero-width characters BEFORE composing Hangul syllables.
    text = "".join(c for c in text if unicodedata.category(c) != "Cf")
    return unicodedata.normalize("NFKC", text).casefold()


def normalize(text: str) -> str:
    """Compose Hangul, fold full-width text, ignore OCR spacing and separators."""
    text = _unicode_text(text)
    return "".join(c for c in text if c.isalnum() and c != "ᆞ")


@dataclass(frozen=True)
class Classification:
    doc_type: DocType
    scores: dict[str, int]
    reason: str


class DocumentClassifier:
    def __init__(self, rules: dict):
        self.rules = {kind: rule["classification"] for kind, rule in rules.items()}
        self.groups = {
            kind: {name: tuple(normalize(term) for term in terms) for name, terms in rule["groups"].items()}
            for kind, rule in self.rules.items()
        }
        self.titles = {kind: tuple(normalize(t) for t in rule["titles"]) for kind, rule in self.rules.items()}

    def _evidence(self, lines: list[TextBlock]) -> dict[str, set[str]]:
        text = normalize("\n".join(b.text for b in lines))
        return {kind: {name for name, terms in groups.items() if any(t in text for t in terms)}
                for kind, groups in self.groups.items()}

    def _titles(self, first_page: list[TextBlock]) -> set[str]:
        found = set()
        for block in first_page[:HEADER_LINES]:
            # Parenthetical form labels such as '(예시)' are not part of a title.
            text = _unicode_text(block.text)
            text = re.sub(r"\([^()]*\)\s*$", "", text)
            heading = normalize(text)
            if len(heading) > 65 or any(mark in text for mark in (":", "：")):
                continue
            if any(heading.startswith(p) and heading != p + "서" for p in _FIELD_PREFIXES):
                continue
            for kind, titles in self.titles.items():
                if any(heading.endswith(title) for title in titles):
                    found.add(kind)
        return found

    def _eligible(self, kind: str, groups: set[str]) -> bool:
        rule = self.rules[kind]
        return (
            len(groups) >= rule["min_groups"]
            and set(rule.get("required_all", ())) <= groups
            and (not rule.get("required_any") or bool(groups.intersection(rule["required_any"])))
        )

    @staticmethod
    def _substantive(kind: str, groups: set[str]) -> bool:
        """Does the main page contain the fields of this form, beyond its title?"""
        if kind == "contract":
            return len(groups - {"agreement", "term"}) >= 2
        if kind == "notice":
            return len(groups & {"schedule", "place", "supplies", "cost", "reply"}) >= 2
        if kind == "application":
            return bool(groups & {"applicant", "category"}) and len(groups & {"applicant", "category", "identity", "affiliation", "contact"}) >= 3
        if kind == "summary":
            return len(groups & {"work_name", "team", "description", "intent", "technology", "environment"}) >= 3
        return False

    def classify(self, lines: list[TextBlock]) -> Classification:
        lines = [b for b in lines if normalize(b.text)]
        page = min((b.page for b in lines), default=0)
        first_page = [b for b in lines if b.page == page]
        titles = self._titles(first_page)
        evidence = self._evidence(lines)
        primary = self._evidence(first_page)
        scores = {kind: GROUP_WEIGHT * len(groups) + (TITLE_WEIGHT if kind in titles else 0)
                  for kind, groups in evidence.items()}

        def result(kind: str, reason: str) -> Classification:
            return Classification(DocType(kind), scores, reason)

        # Check only the opening, so a list/reference inside a real form is harmless.
        for block in first_page[:3]:
            heading = normalize(block.text)
            if any(heading.endswith(marker) for marker in _REFERENCE_HEADINGS):
                return result("unknown", "reference_material")

        # Application/notice/summary headings sometimes sit on a privacy-only page.
        privacy = primary["consent"]
        privacy_form = (
            self._eligible("consent", privacy)
            and len(privacy & {"purpose", "items", "retention", "third_party", "refusal"}) >= 2
        )
        supported_titles = {kind for kind in titles if self._substantive(kind, primary[kind])}
        if privacy_form and titles and titles <= {"application", "summary", "notice", "consent"} and not supported_titles:
            return result("consent", "privacy_form_under_generic_heading")

        if len(titles) == 1:
            return result(next(iter(titles)), "first_page_title")
        if len(titles) > 1:
            if len(supported_titles) == 1:
                return result(next(iter(supported_titles)), "main_form_fields")
            return result("unknown", "conflicting_titles")

        candidates = [kind for kind, groups in evidence.items() if self._eligible(kind, groups)]
        candidates.sort(key=lambda kind: scores[kind], reverse=True)
        if not candidates:
            return result("unknown", "insufficient_evidence")
        if len(candidates) > 1 and scores[candidates[0]] - scores[candidates[1]] < MIN_MARGIN:
            return result("unknown", "ambiguous_evidence")
        return result(candidates[0], "body_evidence")
