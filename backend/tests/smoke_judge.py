"""fastapi 없이 judge 엔진만 시험한다: python tests/smoke_judge.py"""
import sys, types, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
# app/services/judge/__init__ 은 fastapi를 쓰지 않는다. app 패키지 import만 피한다.
import importlib.util
pkg = types.ModuleType("app"); pkg.__path__ = [str(pathlib.Path(__file__).resolve().parents[1] / "app")]
sys.modules["app"] = pkg
from app.services import judge as J  # noqa

class B:  # TextBlock 흉내
    def __init__(s, t): s.text = t
class F:
    def __init__(s, l, v, line): s.label, s.value, s.line = l, v, line
class Doc:
    def __init__(s, doc_type, lines, fields=()):
        s.doc_type = doc_type; s.blocks = [B(l) for l in lines]; s.fields = list(fields)
        s.full_text = "\n".join(lines)

def show(name, doc, answers=None):
    r = J.run(doc, answers)
    print(f"== {name}: subtype={r['subtype']} counts={r['counts']} q={[q['id'] for q in r['questions']]}")
    for f in r["findings"]:
        print(f"  [{f['level']}/{f['severity']}] {f['rule_id']} {f['item']} | {f['reason']} | line={f['line']}\n      {f['speech']}")
    return r

labor = Doc("contract", [
    "표준 근로계약서", "사용자 홍길동과 근로자 김철수는 다음과 같이 근로계약을 체결한다.",
    "근로계약기간: 2026년 11월 1일부터 2027년 10월 31일까지",
    "소정근로시간: 09시 00분부터 18시 00분까지 (휴게시간 20분)",
    "근무일: 매주 5일", "임금: 시간급 9,500원",
    "위약금을 정하지 아니한다.", "퇴사 시 위약금 100만원을 배상한다.",
])
show("근로(최저임금 미달·휴게 부족·위약금)", labor)

housing = Doc("contract", [
    "주택 임대차 계약서", "소재지: 경기도 안산시 단원구 1번지",
    "보증금 5천만원 월세 50만원", "임대차기간: 2026년 12월 1일부터 2028년 11월 30일까지",
    "임대료는 매년 10% 인상한다.",
])
show("주택임대차", housing)

consent = Doc("consent", ["개인정보 수집 이용 동의서", "수집 항목: 이름, 전화번호", "개인정보를 제3자에게 제공한다."])
show("동의서", consent)
notice = Doc("notice", ["가정통신문", "현장체험학습 안내", "일시: 11월 3일"])
show("가정통신문", notice)

# ── 단언 ──
def ids(r): return {f["rule_id"] for f in r["findings"]}
r = J.run(labor)
assert "LAB-003" in ids(r) and "LAB-006" in ids(r), "최저임금·휴게 경고가 나와야 함"
assert sum(f["rule_id"] == "LAB-004" for f in r["findings"]) == 1
clean = Doc("contract", ["근로계약서", "근로자 사용자 임금", "시간급 11,000원", "위약금을 정하지 아니한다.", "손해배상액을 예정하지 아니한다."])
assert "LAB-004" not in ids(J.run(clean)), "부정문은 경고하지 않아야 함"
r = J.run(Doc("contract", ["근로계약서 근로자 사용자", "월급 3,000,000원", "일 4시간 주 5일"]), {"workplace_size": "yes"})
assert r["subtype"] in ("labor_full_time", "labor_part_time") and not r["questions"]
# 월급 → 시급 환산은 근거에 남는다
assert any("환산" in f["reason"] for f in J.run(Doc("contract", ["근로계약서 근로자 사용자", "월급 1,500,000원", "일 8시간 주 5일"]))["findings"] if f["rule_id"] == "LAB-003")
# 금지 문구 점검: 모든 말하기 문장에 단정 표현이 없어야 함
BANNED = ["무효예요", "효력이 없어요", "불법이에요", "위법이에요"]
for rule in __import__("app.services.judge.data", fromlist=["x"]).rules():
    assert not any(b in rule["tts"] for b in BANNED), rule["id"]
print("OK")
