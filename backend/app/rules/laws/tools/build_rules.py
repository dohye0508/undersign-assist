"""검사 규칙(check_rules), 수치 팩트(facts), 핵심 조문(laws.json) 생성 + 근거 조문 존재 검증.

사용법: python3 tools/build_rules.py <laws 폴더>   (full/ 이 먼저 있어야 한다)

안내 문장(tts) 원칙 (CLAUDE.md 판단의 원칙)
- 단정하지 않는다: "무효예요" 대신 "~로 보여요, 확인이 필요해요".
- 문서 원문과 비교 기준은 Finding의 evidence/reason/basis에 따로 담기므로, 문장은 짧게 한 가지만 말한다.
- 빈칸: {missing} {value} {limit} {year} {hours} {priority} 는 코드가 채운다.
"""
import json, sys
from pathlib import Path

OUT = Path(sys.argv[1])
FULL = OUT / "full"
laws = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in FULL.glob("*.json")}
art = {(k, a["article_no"]): a for k, v in laws.items() for a in v["articles"]}


def R(law_id, no, para=None):
    return {"law_id": law_id, "article_no": no, **({"paragraph": para} if para else {})}


MW_SRC = [
    {"title": "고용노동부, 2027년도 적용 최저임금 시간급 10,700원 (뉴스서울)", "url": "https://newsseoul.co.kr/news/view/1065579017067312"},
    {"title": "2027년 최저임금 시간급 10,700원, 월 환산액 223만 6,300원 (택스넷)", "url": "https://www.taxnet.co.kr/contents/taxnetpost/post-detail?id=4905"},
]
MW26_SRC = [
    {"title": "고용노동부, 2026년 적용 최저임금안 시간급 10,320원 (뉴스서울)", "url": "https://newsseoul.co.kr/news/view/1065568218616323"},
]

CONSUMER = ["consumer_online", "consumer_door_to_door", "consumer_membership", "consumer_installment", "consumer_funeral"]
LABOR = ["labor_full_time", "labor_part_time"]

# ───────────── 수치 팩트 ─────────────
facts = [
    {"id": "min_wage_2026_hourly", "value": 10320, "unit": "원/시간", "valid_from": "2026-01-01", "valid_to": "2026-12-31",
     "basis": R("minimum_wage_act", "제10조"), "source_kind": "고용노동부 고시(언론 보도로 확인)", "sources": MW26_SRC},
    {"id": "min_wage_2026_monthly_209h", "value": 2156880, "unit": "원/월", "valid_from": "2026-01-01", "valid_to": "2026-12-31",
     "derived": "10,320원 × 209시간(주 40시간 + 주휴 8시간 기준 월 환산)", "sources": MW26_SRC},
    {"id": "min_wage_2027_hourly", "value": 10700, "unit": "원/시간", "valid_from": "2027-01-01", "valid_to": "2027-12-31",
     "announced": "2026-08-05", "basis": R("minimum_wage_act", "제10조"), "source_kind": "고용노동부 고시(언론 보도로 확인)", "sources": MW_SRC},
    {"id": "min_wage_2027_monthly_209h", "value": 2236300, "unit": "원/월", "valid_from": "2027-01-01", "valid_to": "2027-12-31", "sources": MW_SRC},
    {"id": "probation_min_wage_ratio", "value": 0.9, "unit": "비율", "note": "1년 이상 계약 + 수습 3개월 이내만, 단순노무직 제외",
     "basis": [R("minimum_wage_act", "제5조", "②"), R("minimum_wage_decree", "제3조")]},
    {"id": "small_workplace_threshold", "value": 5, "unit": "명(상시 근로자)", "note": "5명 미만 사업장은 근로시간 한도·가산수당·연차 등 일부 조항이 적용되지 않음",
     "basis": [R("labor_standards_act", "제11조"), R("labor_standards_decree", "제7조")]},
    {"id": "weekly_work_hours_max", "value": 40, "unit": "시간/주", "basis": R("labor_standards_act", "제50조", "①")},
    {"id": "daily_work_hours_max", "value": 8, "unit": "시간/일", "basis": R("labor_standards_act", "제50조", "②")},
    {"id": "weekly_overtime_max", "value": 12, "unit": "시간/주", "basis": R("labor_standards_act", "제53조", "①")},
    {"id": "overtime_premium", "value": 0.5, "unit": "통상임금 대비 가산율", "basis": R("labor_standards_act", "제56조")},
    {"id": "night_work_window", "value": "22:00-06:00", "basis": R("labor_standards_act", "제56조", "③")},
    {"id": "break_4h", "value": 30, "unit": "분", "basis": R("labor_standards_act", "제54조", "①")},
    {"id": "break_8h", "value": 60, "unit": "분", "basis": R("labor_standards_act", "제54조", "①")},
    {"id": "weekly_holiday_threshold", "value": 15, "unit": "시간/주(이상이면 주휴·연차 적용)", "basis": R("labor_standards_act", "제18조", "③")},
    {"id": "annual_leave_base", "value": 15, "unit": "일", "basis": R("labor_standards_act", "제60조", "①")},
    {"id": "annual_leave_max", "value": 25, "unit": "일", "basis": R("labor_standards_act", "제60조", "④")},
    {"id": "dismissal_notice_days", "value": 30, "unit": "일", "basis": R("labor_standards_act", "제26조")},
    {"id": "final_pay_deadline_days", "value": 14, "unit": "일", "basis": [R("labor_standards_act", "제36조"), R("retirement_benefit_act", "제9조")]},
    {"id": "severance_min_service", "value": 1, "unit": "년", "basis": R("retirement_benefit_act", "제4조")},
    {"id": "fixed_term_max_years", "value": 2, "unit": "년", "basis": R("fixed_term_part_time_act", "제4조")},
    {"id": "part_time_overtime_max", "value": 12, "unit": "시간/주", "basis": R("fixed_term_part_time_act", "제6조")},
    {"id": "housing_lease_min_term", "value": 2, "unit": "년", "basis": R("housing_lease_act", "제4조", "①")},
    {"id": "housing_rent_increase_cap", "value": 0.05, "unit": "비율(20분의 1)", "basis": [R("housing_lease_act", "제7조", "②"), R("housing_lease_decree", "제8조")]},
    {"id": "housing_rent_increase_interval", "value": 1, "unit": "년", "basis": R("housing_lease_act", "제7조", "①")},
    {"id": "housing_conversion_rate_cap", "value": "min(연 10%, 한국은행 기준금리 + 연 2%p)", "basis": [R("housing_lease_act", "제7조의2"), R("housing_lease_decree", "제9조")]},
    {"id": "housing_renewal_notice_window", "value": "만료 6개월 전 ~ 2개월 전", "basis": [R("housing_lease_act", "제6조"), R("housing_lease_act", "제6조의3")]},
    {"id": "housing_small_deposit_priority", "unit": "원",
     "note": "근저당 등 선순위 담보가 설정된 날의 기준이 적용되므로, 오래된 담보가 있으면 금액이 더 낮을 수 있음",
     "value": {"서울특별시": {"보증금_상한": 165000000, "최우선변제액": 55000000},
               "과밀억제권역·세종·용인·화성·김포": {"보증금_상한": 145000000, "최우선변제액": 48000000},
               "광역시·안산·광주·파주·이천·평택": {"보증금_상한": 85000000, "최우선변제액": 28000000},
               "그 밖의 지역": {"보증금_상한": 75000000, "최우선변제액": 25000000}},
     "basis": [R("housing_lease_decree", "제10조"), R("housing_lease_decree", "제11조")]},
    {"id": "commercial_rent_increase_cap", "value": 0.05, "unit": "비율", "basis": R("commercial_lease_decree", "제4조")},
    {"id": "commercial_renewal_notice_window", "value": "만료 6개월 전 ~ 1개월 전", "basis": R("commercial_lease_act", "제10조", "①")},
    {"id": "commercial_conversion_rate_cap", "value": "min(연 12%, 한국은행 기준금리 × 4.5)", "basis": R("commercial_lease_decree", "제5조")},
    {"id": "private_loan_max_interest", "value": 0.20, "unit": "연 이자율", "basis": [R("interest_limitation_act", "제2조"), R("interest_limitation_max_rate_decree", "본문")]},
    {"id": "lender_max_interest", "value": 0.20, "unit": "연 이자율", "basis": [R("money_lending_act", "제8조"), R("money_lending_decree", "제5조", "②")]},
    {"id": "ecommerce_withdrawal_days", "value": 7, "unit": "일", "basis": R("ecommerce_act", "제17조")},
    {"id": "door_to_door_withdrawal_days", "value": 14, "unit": "일", "basis": R("door_to_door_sales_act", "제8조")},
    {"id": "installment_withdrawal_days", "value": 7, "unit": "일", "basis": R("installment_transactions_act", "제8조")},
    {"id": "prepaid_installment_withdrawal_days", "value": 14, "unit": "일", "basis": R("installment_transactions_act", "제24조")},
]

# ───────────── 사용자에게 물어볼 질문 (문서만으로 알 수 없는 조건) ─────────────
questions = [
    {"id": "workplace_size", "text": "일하는 곳의 직원이 5명 이상인가요? 이에 따라 적용되는 법이 달라져요.",
     "options": {"yes": "5명 이상", "no": "5명 미만", "unknown": "모름"},
     "basis": [R("labor_standards_act", "제11조"), R("labor_standards_decree", "제7조")]},
]

# ───────────── 검사 규칙 ─────────────
# check.type
#   required_items      : 항목별 동의어 중 하나라도 문서에 있어야 함 (없으면 missing)
#   conditional_required: check.when 핵심어가 문서에 있을 때만 required_items처럼 검사. 항목 값은 동의어 목록 또는 {"regex": ...}
#   numeric_min / numeric_max : 뽑은 값(field)과 기준값(fact, 연도 템플릿 가능) 비교
#   forbidden_clause    : 키워드가 있는 줄. context_any가 있으면 그중 하나도 같은 줄에 있어야 함. skip_negation=true면 부정문 검사 안 함
#   info                : trigger_keywords가 문서에 있을 때만 안내
#   custom              : evaluators.py의 같은 이름 함수가 처리
# applies_if: {"workplace_size": "yes"} → 답이 "no"면 건너뛰고, 모르면 질문을 함께 돌려준다
rules = [
    # ── 근로계약 ──
    {"id": "LAB-001", "doc_types": LABOR, "title": "필수 근로조건 기재",
     "check": {"type": "required_items", "items": {"임금": ["임금", "시급", "시간급", "월급", "급여"], "근로시간": ["근로시간", "소정근로", "출근", "퇴근", "근무시간"],
               "휴일": ["휴일", "주휴"], "연차유급휴가": ["연차", "유급휴가"], "근무장소": ["근무장소", "취업장소", "근무지"], "업무내용": ["업무", "직무"]}},
     "severity": "high", "tts": "계약서에서 {missing} 항목을 찾지 못했어요. 근로계약서에 꼭 적어야 하는 내용이라 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제17조"), R("labor_standards_decree", "제8조")]},
    {"id": "LAB-002", "doc_types": ["labor_part_time"], "title": "단시간 근로 서면 명시",
     "check": {"type": "required_items", "items": {"계약기간": ["계약기간", "근로계약기간"], "근로일": ["근로일", "요일", "근무일"], "휴게": ["휴게"]}},
     "severity": "high", "tts": "아르바이트 계약서에서 {missing} 항목을 찾지 못했어요. 서면으로 적어야 하는 내용이라 확인이 필요해요.",
     "refs": [R("fixed_term_part_time_act", "제17조")]},
    {"id": "LAB-003", "doc_types": LABOR, "title": "최저임금 미달",
     "check": {"type": "numeric_min", "field": "hourly_wage", "fact": "min_wage_{year}_hourly"},
     "severity": "critical", "tts": "시급 {value}원은 {year}년 최저임금 {limit}원보다 낮아 보여요. 최저임금보다 적게 정한 부분은 법에서 인정되지 않을 수 있어 확인이 필요해요.",
     "refs": [R("minimum_wage_act", "제6조", "①③"), R("minimum_wage_act", "제5조", "②")],
     "note": "수습 3개월 이내(1년 이상 계약)는 90%까지 가능 — 문서에 수습이 있으면 reason에 함께 적는다"},
    {"id": "LAB-004", "doc_types": LABOR, "title": "위약금·손해배상 예정",
     "check": {"type": "forbidden_clause", "keywords": ["위약금", "벌금", "중도퇴사", "그만둘경우", "교육비", "손해배상액", "배상금"],
               "context_any": ["원", "배상", "반환", "물어", "공제", "위약금", "벌금"]},
     "severity": "critical", "tts": "그만두면 돈을 물어내라는 내용으로 보이는 문장이 있어요. 근로계약에서 위약금을 미리 정하는 것은 금지되어 있어 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제20조")]},
    {"id": "LAB-005", "doc_types": LABOR, "title": "강제 저축·임금 공제",
     "check": {"type": "forbidden_clause", "keywords": ["적립", "강제저축", "공제", "차감"], "context_any": ["임금", "급여", "월급", "시급"]},
     "severity": "high", "tts": "월급에서 돈을 떼거나 모아 두게 하는 문장이 있어요. 법으로 제한되는 경우가 있어 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제21조"), R("labor_standards_act", "제22조"), R("labor_standards_act", "제43조", "①")],
     "note": "4대보험·세금 공제는 법령에 근거가 있어 정상 — 문구에 보험·세금이 함께 있으면 제외"},
    {"id": "LAB-006", "doc_types": LABOR, "title": "휴게시간 부족",
     "check": {"type": "custom", "fn": "break_time", "facts": ["break_4h", "break_8h"]},
     "severity": "medium", "tts": "하루 {hours}시간 일하는데 휴게시간이 {value}분으로 보여요. 법에서는 {limit}분 이상이라 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제54조")]},
    {"id": "LAB-007", "doc_types": LABOR, "title": "근로시간 한도 초과",
     "check": {"type": "numeric_max", "fields": {"daily_hours": "daily_work_hours_max", "weekly_hours": "weekly_work_hours_max"}},
     "applies_if": {"workplace_size": "yes"},
     "severity": "high", "tts": "정해진 근로시간이 {value}시간으로 법정 기준 {limit}시간보다 길어 보여요. 초과분이 연장근로로 처리되는지 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제50조"), R("labor_standards_act", "제53조")]},
    {"id": "LAB-008", "doc_types": LABOR, "title": "연장·야간·휴일 가산수당 배제",
     "check": {"type": "forbidden_clause", "keywords": ["가산수당없", "추가수당없", "연장수당미지급", "야간수당없", "포괄임금"]},
     "applies_if": {"workplace_size": "yes"},
     "severity": "high", "tts": "더 일한 시간에 추가 수당을 주지 않는다는 내용으로 보여요. 직원 5명 이상인 곳이면 1.5배를 받을 수 있어 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제56조")]},
    {"id": "LAB-009", "doc_types": LABOR, "title": "주휴·연차 배제",
     "check": {"type": "forbidden_clause", "keywords": ["주휴수당없", "주휴수당포함", "연차없", "연차미부여", "연차는없"]},
     "severity": "high", "tts": "주휴수당이나 연차를 없애는 내용으로 보여요. 일주일에 15시간 이상 일하면 받을 수 있어 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제55조"), R("labor_standards_act", "제60조"), R("labor_standards_act", "제18조", "③"), R("labor_standards_decree", "제30조")]},
    {"id": "LAB-010", "doc_types": LABOR, "title": "예고 없는 해고",
     "check": {"type": "forbidden_clause", "keywords": ["즉시해고", "통보없이", "언제든지해고", "예고없이"]},
     "severity": "high", "tts": "예고 없이 해고할 수 있다는 문장이 있어요. 3개월 이상 일했다면 30일 전에 알리거나 30일 치 임금을 줘야 해서 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제26조"), R("labor_standards_act", "제27조"), R("labor_standards_act", "제23조")]},
    {"id": "LAB-011", "doc_types": LABOR, "title": "퇴직금 포기·포함",
     "check": {"type": "forbidden_clause", "keywords": ["퇴직금포함", "퇴직금없", "퇴직금포기", "퇴직금을청구하지"]},
     "severity": "high", "tts": "퇴직금을 미리 포기하거나 월급에 넣는다는 문장이 있어요. 1년 이상 일하면 따로 받을 수 있어 확인이 필요해요.",
     "refs": [R("retirement_benefit_act", "제4조"), R("retirement_benefit_act", "제8조"), R("retirement_benefit_act", "제9조")]},
    {"id": "LAB-012", "doc_types": LABOR, "title": "기간제 2년 초과",
     "check": {"type": "numeric_max", "field": "contract_total_years", "fact": "fixed_term_max_years"},
     "severity": "info", "tts": "계약 기간이 2년을 넘어요. 기간제로 2년을 넘게 일하면 기간이 없는 계약으로 볼 수 있어요.",
     "refs": [R("fixed_term_part_time_act", "제4조")]},
    {"id": "LAB-013", "doc_types": LABOR, "title": "임금 지급일·지급방법",
     "check": {"type": "required_items", "items": {"지급일": ["지급일", "급여일", "매월", "매달"], "지급방법": ["계좌", "통장", "현금", "지급방법", "이체"]}},
     "severity": "medium", "tts": "임금 {missing} 항목을 찾지 못했어요. 임금은 매달 정해진 날에 받아야 해서 확인이 필요해요.",
     "refs": [R("labor_standards_act", "제43조"), R("labor_standards_act", "제17조", "②")]},
    {"id": "LAB-014", "doc_types": LABOR, "title": "미성년자 근로계약",
     "check": {"type": "info", "trigger_keywords": ["친권자", "법정대리인", "보호자동의", "연소근로자"]},
     "severity": "info", "tts": "18세 미만이 쓰는 계약서로 보여요. 근로조건을 서면으로 받아야 하고, 부모님이 대신 계약할 수는 없어요.",
     "refs": [R("labor_standards_act", "제67조")]},
    {"id": "LAB-015", "doc_types": LABOR, "title": "법 기준 미달 조건",
     "check": {"type": "info"}, "severity": "info", "tts": "법 기준보다 나쁜 조건은 그 부분만 인정되지 않고 법 기준이 대신 적용돼요.",
     "refs": [R("labor_standards_act", "제15조")]},

    # ── 주택 임대차 ──
    {"id": "HOU-001", "doc_types": ["lease_housing"], "title": "임대차 기간 2년 미만",
     "check": {"type": "numeric_min", "field": "lease_term_years", "fact": "housing_lease_min_term"},
     "severity": "info", "tts": "계약 기간이 2년보다 짧게 적혀 있어요. 세입자는 원하면 2년까지 살 수 있어요.",
     "refs": [R("housing_lease_act", "제4조")]},
    {"id": "HOU-002", "doc_types": ["lease_housing"], "title": "차임·보증금 5% 초과 인상",
     "check": {"type": "numeric_max", "field": "rent_increase_ratio", "fact": "housing_rent_increase_cap"},
     "severity": "critical", "tts": "월세나 보증금을 {value}% 올릴 수 있다는 문장이 있어요. 법정 한도 5%보다 높아 보여 확인이 필요해요.",
     "refs": [R("housing_lease_act", "제7조"), R("housing_lease_decree", "제8조"), R("housing_lease_act", "제10조의2")]},
    {"id": "HOU-003", "doc_types": ["lease_housing"], "title": "계약갱신요구권 포기",
     "check": {"type": "forbidden_clause", "keywords": ["갱신요구권", "갱신을요구하지", "갱신불가", "재계약불가", "갱신포기"]},
     "severity": "critical", "tts": "계약 연장을 요구하지 않겠다는 내용으로 보이는 문장이 있어요. 세입자에게 불리한 약속은 인정되지 않을 수 있어 확인이 필요해요.",
     "refs": [R("housing_lease_act", "제6조의3"), R("housing_lease_act", "제10조")]},
    {"id": "HOU-004", "doc_types": ["lease_housing"], "title": "전입신고·확정일자 금지",
     "check": {"type": "forbidden_clause", "keywords": ["전입신고불가", "전입신고를하지", "전입하지", "주민등록이전금지", "확정일자불가", "전입금지"]},
     "severity": "critical", "tts": "전입신고를 하지 말라는 내용으로 보이는 문장이 있어요. 전입신고를 해야 보증금을 지킬 수 있어서 꼭 확인이 필요해요.",
     "refs": [R("housing_lease_act", "제3조", "①"), R("housing_lease_act", "제3조의2", "②"), R("housing_lease_act", "제10조"), R("resident_registration_act", "제16조")]},
    {"id": "HOU-005", "doc_types": ["lease_housing"], "title": "월세 전환율 초과",
     "check": {"type": "numeric_max", "field": "conversion_rate", "fact": "housing_conversion_rate_cap", "needs_external": "한국은행 기준금리"},
     "severity": "high", "tts": "보증금을 월세로 바꾸는 비율이 법정 한도보다 높아 보여요.",
     "refs": [R("housing_lease_act", "제7조의2"), R("housing_lease_decree", "제9조")],
     "note": "기준금리가 데이터에 없어 지금은 실행하지 않음"},
    {"id": "HOU-006", "doc_types": ["lease_housing"], "title": "보증금 조건부 반환",
     "check": {"type": "forbidden_clause", "keywords": ["새임차인", "다음세입자", "신규임차인이", "새세입자"], "context_any": ["보증금", "반환", "돌려"]},
     "severity": "high", "tts": "다음 세입자가 들어와야 보증금을 돌려준다는 내용으로 보여요. 계약이 끝나면 보증금을 받을 때까지 계약이 이어지는 것으로 봐서 확인이 필요해요.",
     "refs": [R("housing_lease_act", "제4조", "②"), R("housing_lease_act", "제3조의3")]},
    {"id": "HOU-007", "doc_types": ["lease_housing"], "title": "수선의무 전가",
     "check": {"type": "forbidden_clause", "keywords": ["모든수리", "수선은임차인", "보일러수리비", "하자는임차인", "수리비는임차인"]},
     "severity": "medium", "tts": "집 수리를 모두 세입자가 한다는 문장이 있어요. 큰 고장을 고칠 책임은 보통 집주인에게 있어 확인이 필요해요.",
     "refs": [R("civil_act", "제623조"), R("civil_act", "제626조")], "note": "소규모 수선은 특약으로 임차인 부담 가능(판례)"},
    {"id": "HOU-008", "doc_types": ["lease_housing"], "title": "중도해지 제한",
     "check": {"type": "forbidden_clause", "keywords": ["해지할수없", "중도해지시위약금", "묵시적갱신시에도"]},
     "severity": "medium", "tts": "계약을 중간에 끝낼 수 없다는 문장이 있어요. 자동으로 연장된 계약은 세입자가 언제든 알리고 3개월 뒤 끝낼 수 있어요.",
     "refs": [R("housing_lease_act", "제6조의2"), R("housing_lease_act", "제10조")]},
    {"id": "HOU-009", "doc_types": ["lease_housing"], "title": "소액임차인 최우선변제",
     "check": {"type": "custom", "fn": "small_deposit", "fact": "housing_small_deposit_priority"},
     "severity": "info", "tts": "보증금이 {limit}원 이하라서, 집이 경매로 넘어가도 {priority}원까지는 먼저 돌려받을 수 있는 경우예요.",
     "refs": [R("housing_lease_act", "제8조"), R("housing_lease_decree", "제10조"), R("housing_lease_decree", "제11조")]},
    {"id": "HOU-010", "doc_types": ["lease_housing"], "title": "집주인 정보 확인",
     "check": {"type": "info", "trigger_keywords": ["국세", "체납", "선순위", "근저당", "담보"]},
     "severity": "info", "tts": "계약 전에 집주인의 세금 체납과 먼저 잡힌 담보를 확인해 달라고 할 수 있어요.",
     "refs": [R("housing_lease_act", "제3조의7"), R("housing_lease_act", "제3조의6")]},
    {"id": "HOU-011", "doc_types": ["lease_housing", "lease_commercial"], "title": "중개보수",
     "check": {"type": "info", "trigger_keywords": ["중개보수", "중개수수료", "복비"]},
     "severity": "info", "tts": "중개수수료는 지역 조례로 정한 요율 안에서만 받을 수 있어요.",
     "refs": [R("licensed_realtors_act", "제32조"), R("licensed_realtors_rule", "제20조")]},
    {"id": "HOU-012", "doc_types": ["lease_housing"], "title": "세입자에게 불리한 특약",
     "check": {"type": "info"}, "severity": "info", "tts": "주택임대차보호법보다 세입자에게 불리한 특약은 인정되지 않아요.",
     "refs": [R("housing_lease_act", "제10조")]},
    {"id": "HOU-013", "doc_types": ["lease_housing"], "title": "임대차 계약 필수 항목",
     "check": {"type": "required_items", "items": {"보증금": ["보증금"], "임대차기간": ["임대차기간", "계약기간", "기간"], "주택 주소": ["소재지", "주소", "목적물"]}},
     "severity": "medium", "tts": "계약서에서 {missing} 항목을 찾지 못했어요. 보증금을 지키려면 꼭 적혀 있어야 해서 확인이 필요해요.",
     "refs": [R("housing_lease_act", "제3조의2", "②"), R("housing_lease_act", "제4조")]},

    # ── 상가 임대차 ──
    {"id": "COM-001", "doc_types": ["lease_commercial"], "title": "상가 차임 5% 초과 인상",
     "check": {"type": "numeric_max", "field": "rent_increase_ratio", "fact": "commercial_rent_increase_cap"},
     "severity": "critical", "tts": "상가 월세를 {value}% 올릴 수 있다는 문장이 있어요. 법정 한도 5%보다 높아 보여 확인이 필요해요.",
     "refs": [R("commercial_lease_act", "제11조"), R("commercial_lease_decree", "제4조")]},
    {"id": "COM-002", "doc_types": ["lease_commercial"], "title": "권리금·갱신요구권 포기",
     "check": {"type": "forbidden_clause", "keywords": ["권리금포기", "권리금을청구하지", "갱신요구권포기", "권리금을인정하지"]},
     "severity": "critical", "tts": "권리금이나 계약 연장 권리를 포기하라는 내용으로 보여요. 상가 세입자에게 불리한 약속은 인정되지 않을 수 있어 확인이 필요해요.",
     "refs": [R("commercial_lease_act", "제10조"), R("commercial_lease_act", "제10조의4"), R("commercial_lease_act", "제15조")]},

    # ── 약관·소비자 (사업자가 만든 약관에만 해당) ──
    {"id": "TOS-001", "doc_types": CONSUMER, "title": "사업자 면책",
     "check": {"type": "forbidden_clause", "keywords": ["책임지지않", "책임을지지아니", "일체의책임", "면책된다"]},
     "severity": "high", "tts": "회사가 책임지지 않는다는 문장이 있어요. 회사의 고의나 큰 잘못까지 빼는 약관은 인정되지 않아 확인이 필요해요.",
     "refs": [R("standard_terms_act", "제7조")]},
    {"id": "TOS-002", "doc_types": CONSUMER, "title": "과중한 위약금",
     "check": {"type": "forbidden_clause", "keywords": ["위약금", "지연손해금", "전액몰수", "납입금몰수"]},
     "severity": "medium", "tts": "위약금을 정한 문장이 있어요. 지나치게 크면 인정되지 않거나 줄어들 수 있어 금액을 확인해 보세요.",
     "refs": [R("standard_terms_act", "제8조"), R("civil_act", "제398조")]},
    {"id": "TOS-003", "doc_types": CONSUMER, "title": "해지권 제한·일방 해지",
     "check": {"type": "forbidden_clause", "keywords": ["해지할수없", "해제할수없", "회사는언제든지해지"]},
     "severity": "high", "tts": "내가 계약을 끝낼 권리를 막거나 회사만 마음대로 끝낼 수 있는 문장으로 보여요. 확인이 필요해요.",
     "refs": [R("standard_terms_act", "제9조")]},
    {"id": "TOS-004", "doc_types": CONSUMER, "title": "일방적 내용 변경",
     "check": {"type": "forbidden_clause", "keywords": ["일방적으로변경", "임의로변경", "회사가정하는바에따라"]},
     "severity": "medium", "tts": "회사가 마음대로 내용을 바꿀 수 있다는 문장이 있어요. 확인이 필요해요.",
     "refs": [R("standard_terms_act", "제10조")]},
    {"id": "TOS-005", "doc_types": CONSUMER, "title": "동의 간주",
     "check": {"type": "forbidden_clause", "keywords": ["동의한것으로본다", "이의가없으면", "승인한것으로간주"], "skip_negation": True},
     "severity": "medium", "tts": "아무 말을 하지 않으면 동의한 것으로 본다는 문장이 있어요. 확인이 필요해요.",
     "refs": [R("standard_terms_act", "제12조")]},
    {"id": "TOS-006", "doc_types": CONSUMER, "title": "재판관할·소송 제한",
     "check": {"type": "forbidden_clause", "keywords": ["소송을제기할수없", "민형사상이의를제기하지", "관할법원"]},
     "severity": "info", "tts": "분쟁이 생기면 어느 법원에서 다툴지 정한 문장이 있어요. 소송 자체를 막거나 먼 곳으로 정했다면 인정되지 않을 수 있어요.",
     "refs": [R("standard_terms_act", "제14조")]},
    {"id": "TOS-007", "doc_types": CONSUMER, "title": "약관 설명의무",
     "check": {"type": "info", "trigger_keywords": ["약관"]},
     "severity": "info", "tts": "중요한 약관은 회사가 설명해야 하고, 설명하지 않은 내용은 계약 내용이라고 주장할 수 없어요.",
     "refs": [R("standard_terms_act", "제3조"), R("standard_terms_act", "제6조")]},
    {"id": "CON-001", "doc_types": ["consumer_online"], "title": "온라인 구매 7일 청약철회",
     "check": {"type": "forbidden_clause", "keywords": ["환불불가", "교환불가", "반품불가", "단순변심"], "skip_negation": True},
     "severity": "high", "tts": "환불이나 반품이 안 된다는 문장이 있어요. 온라인으로 산 물건은 받은 날부터 7일 안에 철회할 수 있는 경우가 많아 확인이 필요해요.",
     "refs": [R("ecommerce_act", "제17조"), R("ecommerce_act", "제35조")]},
    {"id": "CON-002", "doc_types": ["consumer_door_to_door", "consumer_membership"], "title": "방문·전화판매 14일 청약철회",
     "check": {"type": "forbidden_clause", "keywords": ["환불불가", "철회불가", "해지불가", "중도해지불가"], "skip_negation": True},
     "severity": "high", "tts": "철회나 해지가 안 된다는 문장이 있어요. 방문판매나 전화권유로 맺은 계약은 계약서를 받은 날부터 14일 안에 철회할 수 있어 확인이 필요해요.",
     "refs": [R("door_to_door_sales_act", "제8조"), R("door_to_door_sales_act", "제31조"), R("door_to_door_sales_act", "제52조")]},
    {"id": "CON-003", "doc_types": ["consumer_installment", "consumer_funeral"], "title": "할부·선불식 할부 청약철회",
     "check": {"type": "forbidden_clause", "keywords": ["철회불가", "해약시납입금몰수", "환불불가"], "skip_negation": True},
     "severity": "high", "tts": "철회가 안 된다는 문장이 있어요. 할부는 7일, 상조처럼 미리 내는 할부는 14일 안에 철회할 수 있어 확인이 필요해요.",
     "refs": [R("installment_transactions_act", "제8조"), R("installment_transactions_act", "제24조"), R("installment_transactions_act", "제43조")]},

    # ── 금전 ──
    {"id": "LOA-001", "doc_types": ["loan_private"], "title": "연 20% 초과 이자",
     "check": {"type": "numeric_max", "field": "annual_interest_rate", "fact": "private_loan_max_interest"},
     "severity": "critical", "tts": "이자가 연 {value}%로 보여요. 법정 최고이자 연 {limit}%보다 높아 넘는 부분은 인정되지 않을 수 있어요.",
     "refs": [R("interest_limitation_act", "제2조"), R("interest_limitation_max_rate_decree", "본문")]},
    {"id": "LOA-002", "doc_types": ["loan_lender"], "title": "대부업 연 20% 초과",
     "check": {"type": "numeric_max", "field": "annual_interest_rate", "fact": "lender_max_interest"},
     "severity": "critical", "tts": "이자가 연 {value}%로 보여요. 수수료까지 합쳐 연 {limit}%를 넘는 부분은 인정되지 않을 수 있어요.",
     "refs": [R("money_lending_act", "제8조"), R("money_lending_decree", "제5조"), R("money_lending_act", "제11조")]},

    # ── 개인정보 동의서 ──
    {"id": "CNS-001", "doc_types": ["consent"], "title": "동의 받을 때 알려야 할 4가지",
     "check": {"type": "required_items", "items": {"수집 목적": ["목적"], "수집 항목": ["항목"], "보유 기간": ["보유", "이용기간", "보존기간", "파기"],
               "동의를 거부할 권리": ["거부할권리", "거부할수", "동의를거부", "거부하실", "거부권"]}},
     "severity": "high", "tts": "동의서에서 {missing} 항목을 찾지 못했어요. 개인정보 동의를 받을 때 꼭 알려야 하는 내용이라 확인이 필요해요.",
     "refs": [R("personal_info_act", "제15조", "②")]},
    {"id": "CNS-002", "doc_types": ["consent"], "title": "제3자 제공 고지",
     "check": {"type": "conditional_required", "when": ["제3자", "제공받는자", "제공받는기관"],
               "items": {"제공받는 곳": ["제공받는자", "제공받는기관", "제공처"], "제공 목적": ["목적"], "제공 항목": ["항목"],
                         "제공받는 곳의 보유 기간": ["보유", "이용기간"], "동의를 거부할 권리": ["거부"]}},
     "severity": "high", "tts": "다른 곳에 개인정보를 준다는 동의서인데 {missing} 항목을 찾지 못했어요. 확인이 필요해요.",
     "refs": [R("personal_info_act", "제17조", "②")]},
    {"id": "CNS-003", "doc_types": ["consent"], "title": "선택 동의 거부 시 불이익",
     "check": {"type": "forbidden_clause", "keywords": ["동의하지않으시면", "동의하지않을경우", "동의를거부하시면", "동의를거부할경우", "거부하실경우"],
               "context_any": ["이용할수없", "제공할수없", "참여할수없", "불가", "제한"], "skip_negation": True},
     "severity": "medium", "level": "info",
     "tts": "동의하지 않으면 이용할 수 없다는 문장이 있어요. 꼭 필요한 항목이 아니라 선택 항목이라면, 거부해도 서비스를 받을 수 있어요.",
     "refs": [R("personal_info_act", "제22조", "⑤")]},
    {"id": "CNS-004", "doc_types": ["consent", "notice"], "title": "주민등록번호 수집",
     "check": {"type": "info", "trigger_keywords": ["주민등록번호", "주민번호"]},
     "severity": "info", "tts": "주민등록번호를 적는 칸이 있어요. 주민등록번호는 법령에 근거가 있을 때만 받을 수 있어서, 왜 필요한지 물어볼 수 있어요.",
     "refs": [R("personal_info_act", "제24조의2")]},
    {"id": "CNS-005", "doc_types": ["consent"], "title": "민감정보 별도 동의",
     "check": {"type": "info", "trigger_keywords": ["민감정보", "건강정보", "병력", "장애정도", "진료기록"]},
     "severity": "info", "tts": "건강 같은 민감한 정보를 받는 동의서로 보여요. 이런 정보는 다른 정보와 따로 동의를 받아야 해요.",
     "refs": [R("personal_info_act", "제23조")]},
    {"id": "CNS-006", "doc_types": ["consent"], "title": "홍보·마케팅 동의",
     "check": {"type": "info", "trigger_keywords": ["마케팅", "광고", "홍보", "이벤트안내"]},
     "severity": "info", "tts": "홍보나 광고에 쓰는 동의가 들어 있어요. 이 동의는 따로 받아야 하고, 거부해도 서비스를 받을 수 있어요.",
     "refs": [R("personal_info_act", "제22조", "①⑤")]},

    # ── 가정통신문 (법 판단 없이 빠짐 확인만) ──
    {"id": "NTC-001", "doc_types": ["notice"], "title": "회신 기한",
     "check": {"type": "conditional_required", "when": ["회신", "제출", "신청서", "참가신청"],
               "items": {"회신 기한": {"regex": r"(까지|마감|기한|\d{1,2}\s*[월./]\s*\d{1,2}\s*일?\s*\(?[월화수목금토일]?)"}}},
     "severity": "medium", "tts": "회신해야 하는 가정통신문인데 {missing} 항목을 찾지 못했어요. 언제까지 내야 하는지 학교에 확인해 보세요.",
     "refs": []},
    {"id": "NTC-002", "doc_types": ["notice"], "title": "비용 금액",
     "check": {"type": "conditional_required", "when": ["참가비", "비용", "납부", "수익자부담", "회비"],
               "items": {"금액": {"regex": r"(\d[\d,]*\s*원|\d+\s*만\s*원|무료)"}}},
     "severity": "medium", "tts": "돈을 내야 하는 내용이 있는데 {missing} 항목을 찾지 못했어요. 얼마인지 학교에 확인해 보세요.",
     "refs": []},
    {"id": "NTC-003", "doc_types": ["notice"], "title": "행사 날짜·장소",
     "check": {"type": "conditional_required", "when": ["체험학습", "현장학습", "행사", "방문", "견학", "수련"],
               "items": {"날짜": {"regex": r"(\d{1,2}\s*월\s*\d{1,2}\s*일|\d{4}\s*[.\-]\s*\d{1,2}\s*[.\-]\s*\d{1,2}|\d{1,2}\s*[./]\s*\d{1,2}\s*\()"},
                         "장소": ["장소", "목적지", "집결"]}},
     "severity": "medium", "tts": "행사 안내인데 {missing} 항목을 찾지 못했어요. 학교에 확인해 보세요.",
     "refs": []},
    {"id": "NTC-004", "doc_types": ["notice"], "title": "개인정보 동의 포함",
     "check": {"type": "info", "trigger_keywords": ["개인정보", "수집", "동의합니다", "동의함"]},
     "severity": "info", "tts": "가정통신문 안에 개인정보 동의가 들어 있어요. 목적과 보유 기간, 거부할 권리가 적혀 있는지 함께 확인해 보세요.",
     "refs": [R("personal_info_act", "제15조", "②")]},

    # ── 공통 ──
    {"id": "GEN-001", "doc_types": ["*"], "title": "반사회적·불공정 계약",
     "check": {"type": "info"}, "severity": "info", "tts": "사회질서에 어긋나거나 약점을 이용해 크게 불공정한 계약은 인정되지 않아요.",
     "refs": [R("civil_act", "제103조"), R("civil_act", "제104조")]},
    {"id": "GEN-002", "doc_types": ["*"], "title": "전자서명 효력",
     "check": {"type": "info"}, "severity": "info", "tts": "화면에 한 전자서명도 종이 서명과 같은 효력을 가질 수 있어요.",
     "refs": [R("electronic_signature_act", "제3조")]},
    {"id": "GEN-003", "doc_types": ["*"], "title": "정보접근 편의 요구",
     "check": {"type": "info"}, "severity": "info", "tts": "장애를 이유로 계약 정보를 주지 않는 것은 차별이에요. 읽어주기 같은 편의를 요구할 수 있어요.",
     "refs": [R("disability_discrimination_act", "제20조"), R("disability_discrimination_act", "제21조")]},
]

# 단정 표현 검사: 안내 문장에 이런 말이 남아 있으면 만들기를 멈춘다
BANNED = ["무효예요", "무효이고", "무효입니다", "효력이 없어요", "효력이 없습니다", "불법이에요", "위법이에요"]
for r in rules:
    for b in BANNED:
        if b in r["tts"]:
            raise SystemExit(f"{r['id']} 안내 문장에 단정 표현: {b}")


def resolve(ref):
    a = art.get((ref["law_id"], ref["article_no"]))
    if not a:
        raise SystemExit(f"근거 조문 없음: {ref}")
    L = laws[ref["law_id"]]
    return {**ref, "law_name": L["law_name"], "title": a["title"], "effective_date": L["effective_date"],
            "official_url": a["source_url"], "mirror_url": L["mirror_source"]["file_url"]}


for f in facts:
    if "basis" in f:
        b = f["basis"] if isinstance(f["basis"], list) else [f["basis"]]
        f["basis"] = [resolve(x) for x in b]
for q in questions:
    q["basis"] = [resolve(x) for x in q["basis"]]
for r in rules:
    r["refs"] = [resolve(x) for x in r["refs"]]
    for qid, _ in (r.get("applies_if") or {}).items():
        q = next(q for q in questions if q["id"] == qid)
        q.setdefault("affects", []).append(r["id"])

core_keys = sorted({(x["law_id"], x["article_no"]) for r in rules for x in r["refs"]} |
                   {(x["law_id"], x["article_no"]) for f in facts for x in f.get("basis", [])} |
                   {(x["law_id"], x["article_no"]) for q in questions for x in q["basis"]})
by_law = {}
for lid, no in core_keys:
    L = laws[lid]
    e = by_law.setdefault(lid, {"law_id": lid, "law_name": L["law_name"], "law_kind": L["law_kind"], "doc_types": L["doc_types"],
                                "promulgation_date": L["promulgation_date"], "effective_date": L["effective_date"],
                                "official_url": L["official_url"], "mirror_url": L["mirror_source"]["file_url"], "articles": []})
    a = art[(lid, no)]
    e["articles"].append({k: a[k] for k in ("article_no", "title", "text", "source_url")} |
                         {"used_by_rules": [r["id"] for r in rules if any(x["law_id"] == lid and x["article_no"] == no for x in r["refs"])]})

commit = next(iter(laws.values()))["mirror_source"]["commit"]
meta = {
    "project": "undersign-contract",
    "generated_at": "2026-10-24T17:00:00+09:00",
    "source": "국가법령정보센터(law.go.kr) 원문을 그대로 미러링한 legalize-kr 저장소",
    "source_repo": "https://github.com/legalize-kr/legalize-kr",
    "source_commit": commit,
    "note": "조문 text는 원문 그대로입니다(요약·의역 없음). 일부 법령은 공포되었지만 시행일이 아직 오지 않은 최신본이므로 effective_date를 확인하세요. 최저임금 금액은 법령이 아니라 고용노동부 고시라서 facts.json에 보도 출처와 함께 따로 넣었습니다.",
    "verified_against_law_go_kr": "미러 경유(직접 접속 불가)",
}
(OUT / "laws.json").write_text(json.dumps({"meta": meta, "laws": list(by_law.values())}, ensure_ascii=False, indent=2), encoding="utf-8")
(OUT / "check_rules.json").write_text(json.dumps({"meta": meta | {"rule_count": len(rules)}, "questions": questions, "rules": rules}, ensure_ascii=False, indent=2), encoding="utf-8")
(OUT / "facts.json").write_text(json.dumps({"meta": meta | {"fact_count": len(facts)}, "facts": facts}, ensure_ascii=False, indent=2), encoding="utf-8")
print("rules", len(rules), "facts", len(facts), "questions", len(questions), "core laws", len(by_law), "core articles", len(core_keys))
