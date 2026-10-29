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
    "서류목록", "처리방침", "교육자료", "교육안내", "작성방법", "작성방법안내",
    "작성안내", "작성요령", "작성가이드",
)
_FIELD_PREFIXES = ("제출서류", "구비서류", "준비물", "교육내용", "작품명", "작품요약", "예시문서")
_APPENDICES = {"contract": {"consent"}, "notice": {"consent", "application"},
               "application": {"consent", "summary"}, "summary": {"consent"}, "consent": set()}


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

    def _title_kinds(self, text: str) -> set[str]:
        text = _unicode_text(text)
        # Form labels, page counts and school correspondence numbers are metadata.
        text = re.sub(r"(?:\([^()]*\)|\[[^\[\]]*\])\s*$", "", text)
        heading = normalize(text)
        heading = re.sub(r"(?:제?\d{4}\d{1,4}호|제\d+호)$", "", heading)
        if len(heading) > 65 or ":" in text:
            return set()
        if any(heading.startswith(p) and heading != p + "서" for p in _FIELD_PREFIXES):
            return set()
        found = {kind for kind, titles in self.titles.items() if any(heading.endswith(t) for t in titles)}
        if re.search(r"(?:개인정보|민감정보|고유식별정보)(?:수집|이용|활용|제공|처리|제3자|및|에대한)*동의서$", heading):
            found.add("consent")
        return found

    def _titles(self, page: list[TextBlock]) -> set[str]:
        found = set()
        header = page[:HEADER_LINES]
        for index, block in enumerate(header):
            found.update(self._title_kinds(block.text))
            if index and not self._title_kinds(header[index - 1].text):
                # A photographed heading may be emitted as two OCR lines.
                found.update(self._title_kinds(header[index - 1].text + block.text))
        return found

    def _reference_page(self, page: list[TextBlock]) -> bool:
        for block in page[:3]:
            if self._title_kinds(block.text):
                return False
            if any(normalize(block.text).endswith(marker) for marker in _REFERENCE_HEADINGS):
                return True
        return False

    def _form_evidence(self, page: list[TextBlock]) -> dict[str, set[str]]:
        # '수집 목적: 신청자 확인' and '수집 항목: 성명, 소속, 연락처'
        # describe personal data, not application fields to complete.
        privacy_keys = tuple(t for name, terms in self.groups["consent"].items()
                             if name not in {"privacy", "agreement"} for t in terms)
        return self._evidence([b for b in page if not any(t in normalize(b.text) for t in privacy_keys)])

    @staticmethod
    def _contract_families(groups: set[str]) -> set[str]:
        return {prefix for prefix in ("labor_", "lease_", "loan_", "trade_")
                if sum(g.startswith(prefix) for g in groups) >= 2}

    def _conflicting_pages(self, kind: str, pages: list[list[TextBlock]]) -> bool:
        main_families = self._contract_families(self._evidence(pages[0])["contract"])
        for page in pages[1:]:
            if self._reference_page(page):
                continue
            evidence = self._form_evidence(page)
            for other in self._titles(page):
                if other != kind and other not in _APPENDICES[kind] and self._substantive(other, evidence[other]):
                    return True
                if kind == other == "contract":
                    families = self._contract_families(evidence["contract"])
                    if families and main_families and not families.intersection(main_families):
                        return True
                    main_families.update(families)
        return False

    def _eligible(self, kind: str, groups: set[str]) -> bool:
        rule = self.rules[kind]
        return (
            len(groups) >= rule["min_groups"]
            and set(rule.get("required_all", ())) <= groups
            and (not rule.get("required_sets") or any(set(required) <= groups for required in rule["required_sets"]))
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
        by_page: dict[int, list[TextBlock]] = {}
        for block in lines:
            by_page.setdefault(block.page, []).append(block)
        pages = [by_page[p] for p in sorted(by_page)] or [[]]
        first_page = pages[0]
        titles = self._titles(first_page)
        evidence = self._evidence(lines)
        primary = self._evidence(first_page)
        scores = {kind: GROUP_WEIGHT * len(groups) + (TITLE_WEIGHT if kind in titles else 0)
                  for kind, groups in evidence.items()}

        def result(kind: str, reason: str) -> Classification:
            if kind != "unknown" and self._conflicting_pages(kind, pages):
                return Classification(DocType.UNKNOWN, scores, "conflicting_documents")
            return Classification(DocType(kind), scores, reason)

        # Check only the opening, so a list/reference inside a real form is harmless.
        if self._reference_page(first_page):
            return result("unknown", "reference_material")

        # Application/notice/summary headings sometimes sit on a privacy-only page.
        privacy = primary["consent"]
        privacy_form = (
            self._eligible("consent", privacy)
            and len(privacy & {"purpose", "items", "retention", "third_party", "refusal"}) >= 2
        )
        form_evidence = self._form_evidence(first_page)
        supported_titles = {kind for kind in titles if self._substantive(kind, form_evidence[kind])}
        if privacy_form and titles and titles <= {"application", "summary", "notice", "consent"} and not supported_titles:
            return result("consent", "privacy_form_under_generic_heading")

        if len(titles) == 1:
            kind = next(iter(titles))
            return result(kind, "first_page_title")
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
