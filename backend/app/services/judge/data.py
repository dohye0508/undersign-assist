"""rules/laws/ 안의 JSON을 한 번만 읽어서 메모리에 둔다. (설계서 파일 구조 절)"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

_APP_DIR = Path(__file__).resolve().parents[2]  # backend/app
_LAWS_DIR = _APP_DIR / "rules" / "laws"
_SUBTYPES_PATH = _APP_DIR / "rules" / "judge_subtypes.json"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def _check_rules_raw() -> dict:
    return _read_json(_LAWS_DIR / "check_rules.json")


@lru_cache(maxsize=1)
def _facts_raw() -> dict:
    return _read_json(_LAWS_DIR / "facts.json")


@lru_cache(maxsize=1)
def _laws_raw() -> dict:
    return _read_json(_LAWS_DIR / "laws.json")


@lru_cache(maxsize=1)
def subtypes() -> dict[str, list[str]]:
    return _read_json(_SUBTYPES_PATH)


def rules() -> list[dict]:
    return _check_rules_raw()["rules"]


@lru_cache(maxsize=1)
def facts() -> dict[str, dict]:
    return {f["id"]: f for f in _facts_raw()["facts"]}


@lru_cache(maxsize=1)
def laws_index() -> dict[tuple[str, str], dict]:
    """(law_id, article_no) -> 조문 원문 한 건"""
    idx: dict[tuple[str, str], dict] = {}
    for law in _laws_raw()["laws"]:
        for art in law.get("articles", []):
            idx[(law["law_id"], art["article_no"])] = {
                "law_name": law["law_name"],
                "article_no": art["article_no"],
                "title": art.get("title", ""),
                "text": art.get("text", ""),
                "url": art.get("source_url") or law.get("official_url", ""),
            }
    return idx


def rules_for(subtype: str) -> list[dict]:
    """세부 종류(subtype)에 맞는 규칙 + 공통 규칙("*")을 함께 돌려준다."""
    out = []
    for r in rules():
        doc_types = r.get("doc_types", [])
        if "*" in doc_types or (subtype and subtype in doc_types):
            out.append(r)
    return out
