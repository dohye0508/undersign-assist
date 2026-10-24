"""legalize-kr 마크다운 → 조문 단위 JSON 변환기."""
import json, re, sys, subprocess, yaml, os
from pathlib import Path

ROOT = Path(sys.argv[1])  # lk 저장소 경로
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)

COMMIT = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()

# (파일 경로, law_id, 분류, doc_types)
TARGETS = [
    ("kr/근로기준법/법률(법률).md", "labor_standards_act", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/근로기준법/시행령.md", "labor_standards_decree", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/근로기준법/시행규칙.md", "labor_standards_rule", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/최저임금법/법률.md", "minimum_wage_act", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/최저임금법/시행령.md", "minimum_wage_decree", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/근로자퇴직급여보장법/법률.md", "retirement_benefit_act", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/기간제및단시간근로자보호등에관한법률/법률.md", "fixed_term_part_time_act", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/남녀고용평등과일ㆍ가정양립지원에관한법률/법률.md", "equal_employment_act", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/파견근로자보호등에관한법률/법률.md", "dispatched_workers_act", "근로", ["labor_dispatch"]),
    ("kr/근로자퇴직급여보장법/시행령.md", "retirement_benefit_decree", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/기간제및단시간근로자보호등에관한법률/시행령.md", "fixed_term_part_time_decree", "근로", ["labor_full_time", "labor_part_time"]),
    ("kr/민간임대주택에관한특별법/시행령.md", "private_rental_housing_decree", "주거임대차", ["lease_housing"]),
    ("kr/공인중개사법/시행령.md", "licensed_realtors_decree", "주거임대차", ["lease_housing", "lease_commercial"]),
    ("kr/공인중개사법/시행규칙.md", "licensed_realtors_rule", "주거임대차", ["lease_housing", "lease_commercial"]),
    ("kr/대부업등의등록및금융이용자보호에관한법률/시행령.md", "money_lending_decree", "금전", ["loan_lender"]),
    ("kr/주택임대차보호법/법률.md", "housing_lease_act", "주거임대차", ["lease_housing"]),
    ("kr/주택임대차보호법/시행령.md", "housing_lease_decree", "주거임대차", ["lease_housing"]),
    ("kr/주택임대차계약증서상의확정일자부여및임대차정보제공에관한규칙/법무부령.md", "housing_lease_fixed_date_rule", "주거임대차", ["lease_housing"]),
    ("kr/민간임대주택에관한특별법/법률.md", "private_rental_housing_act", "주거임대차", ["lease_housing"]),
    ("kr/전세사기피해자지원및주거안정에관한특별법/법률.md", "jeonse_fraud_victim_act", "주거임대차", ["lease_housing"]),
    ("kr/공인중개사법/법률.md", "licensed_realtors_act", "주거임대차", ["lease_housing", "lease_commercial"]),
    ("kr/상가건물임대차보호법/법률.md", "commercial_lease_act", "상가임대차", ["lease_commercial"]),
    ("kr/상가건물임대차보호법/시행령.md", "commercial_lease_decree", "상가임대차", ["lease_commercial"]),
    ("kr/민법/법률.md", "civil_act", "일반", ["*"]),
    ("kr/약관의규제에관한법률/법률.md", "standard_terms_act", "소비자", ["*"]),
    ("kr/약관의규제에관한법률/시행령.md", "standard_terms_decree", "소비자", ["*"]),
    ("kr/전자상거래등에서의소비자보호에관한법률/법률.md", "ecommerce_act", "소비자", ["consumer_online"]),
    ("kr/전자상거래등에서의소비자보호에관한법률/시행령.md", "ecommerce_decree", "소비자", ["consumer_online"]),
    ("kr/방문판매등에관한법률/법률.md", "door_to_door_sales_act", "소비자", ["consumer_door_to_door", "consumer_membership"]),
    ("kr/방문판매등에관한법률/시행령.md", "door_to_door_sales_decree", "소비자", ["consumer_door_to_door", "consumer_membership"]),
    ("kr/할부거래에관한법률/법률.md", "installment_transactions_act", "소비자", ["consumer_installment", "consumer_funeral"]),
    ("kr/할부거래에관한법률/시행령.md", "installment_transactions_decree", "소비자", ["consumer_installment", "consumer_funeral"]),
    ("kr/소비자기본법/법률.md", "framework_consumer_act", "소비자", ["*"]),
    ("kr/이자제한법/법률(법률).md", "interest_limitation_act", "금전", ["loan_private"]),
    ("kr/이자제한법제2조제1항의최고이자율에관한규정/대통령령.md", "interest_limitation_max_rate_decree", "금전", ["loan_private"]),
    ("kr/대부업등의등록및금융이용자보호에관한법률/법률.md", "money_lending_act", "금전", ["loan_lender"]),
    ("kr/대학등록금에관한규칙/교육부령.md", "university_tuition_rule", "교육", ["tuition"]),
    ("kr/주민등록법/법률.md", "resident_registration_act", "행정", ["lease_housing", "admin"]),
    ("kr/주민등록법/시행령.md", "resident_registration_decree", "행정", ["lease_housing", "admin"]),
    ("kr/전자서명법/법률.md", "electronic_signature_act", "서명", ["*"]),
    ("kr/장애인차별금지및권리구제등에관한법률/법률.md", "disability_discrimination_act", "접근성", ["*"]),
]

ART_RE = re.compile(r"^#{5}\s+(제\d+조(?:의\d+)?)\s*(?:\((.*)\))?\s*(.*)$")
HDR_RE = re.compile(r"^(#{1,4})\s+(.*)$")


def clean(line: str) -> str:
    line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)
    line = line.replace("\\.", ".")
    return line.rstrip()


def parse(path: Path):
    raw = path.read_text(encoding="utf-8")
    _, fm, body = raw.split("---\n", 2)
    meta = yaml.safe_load(fm)
    lines = body.split("\n")
    articles, preamble = [], []
    cur = None
    heading = {}
    in_addenda = False
    for ln in lines:
        m = ART_RE.match(ln)
        h = HDR_RE.match(ln)
        if m and not in_addenda:
            if cur:
                articles.append(cur)
            no, title, rest = m.group(1), (m.group(2) or "").strip(), m.group(3).strip()
            path_str = " > ".join(heading[k] for k in sorted(heading) if heading[k] != meta.get("제목"))
            cur = {"article_no": no, "title": title, "chapter": path_str, "text_lines": []}
            if rest:
                cur["text_lines"].append(rest)
            continue
        if h and not ln.startswith("#####"):
            level, txt = len(h.group(1)), h.group(2).strip()
            if txt.startswith("부칙"):
                in_addenda = True
                if cur:
                    articles.append(cur)
                    cur = None
                continue
            heading = {k: v for k, v in heading.items() if k < level}
            heading[level] = txt
            continue
        if in_addenda:
            continue
        if cur is not None:
            cur["text_lines"].append(clean(ln))
        elif ln.strip() and not ln.startswith("#"):
            preamble.append(clean(ln))
    if cur:
        articles.append(cur)

    out_articles = []
    base = meta.get("출처", "")
    for a in articles:
        text = "\n".join(l for l in a.pop("text_lines")).strip()
        text = re.sub(r"\n{2,}", "\n", text)
        if a["article_no"] == "제0조" and not text:
            continue
        a["text"] = text
        a["deleted"] = bool(re.fullmatch(r"(삭제\s*)?(<.*>)?\s*", text)) or a["title"].startswith("삭제") or text.startswith("삭제 <")
        a["source_url"] = f"{base}/{a['article_no']}" if base else None
        out_articles.append(a)
    # 조문 없이 본문만 있는 규정(예: 최고이자율 규정)
    if not out_articles and preamble:
        out_articles.append({"article_no": "본문", "title": meta.get("제목"), "chapter": "",
                             "text": "\n".join(preamble).strip(), "deleted": False, "source_url": base})
    attachments = [
        {"no": f"{x.get('별표번호','')}-{x.get('별표가지번호','')}", "kind": x.get("별표구분"),
         "title": x.get("제목"), "url": x.get("파일링크")}
        for x in (meta.get("첨부파일") or [])
    ]
    return meta, out_articles, attachments


index = []
for rel, law_id, cat, doc_types in TARGETS:
    p = ROOT / rel
    meta, arts, atts = parse(p)
    rec = {
        "law_id": law_id,
        "law_name": meta.get("제목"),
        "law_kind": meta.get("법령구분"),
        "category": cat,
        "doc_types": doc_types,
        "ministry": meta.get("소관부처"),
        "promulgation_date": str(meta.get("공포일자")),
        "promulgation_no": str(meta.get("공포번호")),
        "effective_date": str(meta.get("시행일자")),
        "status": meta.get("상태"),
        "law_mst": str(meta.get("법령MST")),
        "official_url": meta.get("출처"),
        "mirror_source": {
            "repo": "https://github.com/legalize-kr/legalize-kr",
            "path": rel,
            "commit": COMMIT,
            "file_url": f"https://github.com/legalize-kr/legalize-kr/blob/{COMMIT}/{rel}",
        },
        "attachments": atts,
        "article_count": len([a for a in arts if not a["deleted"]]),
        "articles": arts,
    }
    (OUT / f"{law_id}.json").write_text(json.dumps(rec, ensure_ascii=False, indent=1), encoding="utf-8")
    index.append({k: rec[k] for k in rec if k not in ("articles", "attachments")} | {"file": f"full/{law_id}.json"})
    print(f"{law_id:40s} {rec['law_name'][:30]:30s} arts={rec['article_count']:4d} eff={rec['effective_date']}")

(OUT.parent / "index.json").write_text(json.dumps({"source_commit": COMMIT, "laws": index}, ensure_ascii=False, indent=1), encoding="utf-8")
