"""검사 규칙(check_rules), 수치 팩트(facts), 핵심 조문(laws.json) 생성 + 근거 조문 존재 검증."""
import json, sys, re
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

# ───────────── 수치 팩트 (OCR로 읽은 숫자와 바로 비교) ─────────────
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

# ───────────── 검사 규칙 (OCR 문장 ↔ 조문 대조) ─────────────
# check.type: required_items(필수 기재) / numeric_min / numeric_max / forbidden_clause(무효·위법 특약) / info(안내)
rules = [
    # 근로계약
    {"id": "LAB-001", "doc_types": ["labor_full_time", "labor_part_time"], "title": "필수 근로조건 기재 여부",
     "check": {"type": "required_items", "items": {"임금": ["임금", "시급", "월급", "급여"], "소정근로시간": ["근로시간", "소정근로", "출근", "퇴근"],
               "휴일": ["휴일", "주휴"], "연차유급휴가": ["연차", "유급휴가"], "근무장소": ["근무장소", "취업장소", "근무지"], "업무내용": ["업무", "직무"]}},
     "severity": "high", "tts": "계약서에 {missing}이 적혀 있지 않아요. 근로기준법상 꼭 써야 하는 항목이에요.",
     "refs": [R("labor_standards_act", "제17조"), R("labor_standards_decree", "제8조")]},
    {"id": "LAB-002", "doc_types": ["labor_part_time"], "title": "단시간·기간제 서면 명시(근로일·근로일별 시간)",
     "check": {"type": "required_items", "items": {"계약기간": ["계약기간", "근로계약기간"], "근로일": ["근로일", "요일"], "휴게": ["휴게"]}},
     "severity": "high", "tts": "아르바이트·기간제 계약서에는 {missing}을 반드시 적어야 해요.",
     "refs": [R("fixed_term_part_time_act", "제17조")]},
    {"id": "LAB-003", "doc_types": ["labor_full_time", "labor_part_time"], "title": "최저임금 미달",
     "check": {"type": "numeric_min", "field": "hourly_wage", "fact": "min_wage_{year}_hourly", "ocr_patterns": [r"시급\s*([\d,]+)\s*원", r"시간당\s*([\d,]+)\s*원"],
               "monthly_fact": "min_wage_{year}_monthly_209h"},
     "severity": "critical", "tts": "시급 {value}원은 {year}년 최저임금 {limit}원보다 적어요. 이 부분은 무효이고 최저임금만큼 받을 수 있어요.",
     "refs": [R("minimum_wage_act", "제6조", "①③")]},
    {"id": "LAB-004", "doc_types": ["labor_full_time", "labor_part_time"], "title": "위약금·손해배상 예정 특약",
     "check": {"type": "forbidden_clause", "keywords": ["위약금", "손해배상", "배상한다", "벌금", "중도 퇴사 시", "그만둘 경우", "교육비 반환"]},
     "severity": "critical", "tts": "그만두면 돈을 물어내라는 조항이 있어요. 근로기준법은 이런 약속을 금지하고 있어요.",
     "refs": [R("labor_standards_act", "제20조")]},
    {"id": "LAB-005", "doc_types": ["labor_full_time", "labor_part_time"], "title": "강제 저축·임금 공제",
     "check": {"type": "forbidden_clause", "keywords": ["적립", "강제 저축", "급여에서 공제", "임금에서 차감", "보증금", "유니폼 비용 공제"]},
     "severity": "high", "tts": "월급에서 돈을 미리 떼거나 저축하게 하는 조항이 있어요. 법으로 제한되는 내용이에요.",
     "refs": [R("labor_standards_act", "제21조"), R("labor_standards_act", "제22조"), R("labor_standards_act", "제43조", "①")]},
    {"id": "LAB-006", "doc_types": ["labor_full_time", "labor_part_time"], "title": "휴게시간 부족",
     "check": {"type": "numeric_min", "field": "break_minutes", "rule": "근로 4시간당 30분, 8시간당 60분", "facts": ["break_4h", "break_8h"]},
     "severity": "medium", "tts": "하루 {hours}시간 일하는데 휴게시간이 {value}분이에요. 법에서는 {limit}분 이상이에요.",
     "refs": [R("labor_standards_act", "제54조")]},
    {"id": "LAB-007", "doc_types": ["labor_full_time", "labor_part_time"], "title": "근로시간·연장근로 한도 초과",
     "check": {"type": "numeric_max", "fields": {"daily_hours": "daily_work_hours_max", "weekly_hours": "weekly_work_hours_max", "weekly_overtime": "weekly_overtime_max"}},
     "severity": "high", "tts": "일하는 시간이 법정 한도를 넘어요. 연장근로는 일주일에 12시간까지예요.",
     "refs": [R("labor_standards_act", "제50조"), R("labor_standards_act", "제53조")]},
    {"id": "LAB-008", "doc_types": ["labor_full_time", "labor_part_time"], "title": "연장·야간·휴일 가산수당 배제",
     "check": {"type": "forbidden_clause", "keywords": ["가산수당 없음", "추가수당 없", "연장수당 미지급", "포괄", "야간수당 없"]},
     "severity": "high", "tts": "추가로 일한 시간에 1.5배를 주지 않겠다는 내용이 보여요. 5인 이상 사업장이면 받을 권리가 있어요.",
     "refs": [R("labor_standards_act", "제56조")], "note": "상시 5명 미만 사업장은 제56조 적용 제외(근로기준법 제11조·시행령 별표1) — 앱에서 사업장 규모를 물어볼 것"},
    {"id": "LAB-009", "doc_types": ["labor_full_time", "labor_part_time"], "title": "주휴·연차 배제 특약",
     "check": {"type": "forbidden_clause", "keywords": ["주휴수당 없", "주휴수당 포함", "연차 없음", "연차 미부여"], "exception_fact": "weekly_holiday_threshold"},
     "severity": "high", "tts": "주 15시간 이상 일하면 주휴일과 연차를 받을 수 있어요. 이를 없애는 조항은 무효예요.",
     "refs": [R("labor_standards_act", "제55조"), R("labor_standards_act", "제60조"), R("labor_standards_act", "제18조", "③"), R("labor_standards_decree", "제30조")]},
    {"id": "LAB-010", "doc_types": ["labor_full_time", "labor_part_time"], "title": "즉시 해고·해고예고 배제 특약",
     "check": {"type": "forbidden_clause", "keywords": ["즉시 해고", "통보 없이", "언제든지 해고", "예고 없이"]},
     "severity": "high", "tts": "예고 없이 해고할 수 있다는 조항이 있어요. 3개월 이상 일하면 30일 전에 알려주거나 30일치 임금을 줘야 해요.",
     "refs": [R("labor_standards_act", "제23조"), R("labor_standards_act", "제26조"), R("labor_standards_act", "제27조")]},
    {"id": "LAB-011", "doc_types": ["labor_full_time", "labor_part_time"], "title": "퇴직금 포기·월급 포함 특약",
     "check": {"type": "forbidden_clause", "keywords": ["퇴직금 포함", "퇴직금 없음", "퇴직금 포기", "퇴직금을 청구하지"]},
     "severity": "high", "tts": "1년 이상, 주 15시간 이상 일하면 퇴직금을 받을 수 있어요. 미리 포기시키는 조항은 효력이 없어요.",
     "refs": [R("retirement_benefit_act", "제4조"), R("retirement_benefit_act", "제8조"), R("retirement_benefit_act", "제9조")]},
    {"id": "LAB-012", "doc_types": ["labor_full_time", "labor_part_time"], "title": "기간제 2년 초과 반복갱신",
     "check": {"type": "numeric_max", "field": "contract_total_years", "fact": "fixed_term_max_years"},
     "severity": "medium", "tts": "계약직으로 2년을 넘게 쓰면 정규직(기간 없는 계약)으로 보아요.",
     "refs": [R("fixed_term_part_time_act", "제4조")]},
    {"id": "LAB-013", "doc_types": ["labor_full_time", "labor_part_time"], "title": "임금 지급일·지급방법",
     "check": {"type": "required_items", "items": {"지급일": ["지급일", "매월", "급여일"], "지급방법": ["계좌", "통장", "현금", "지급방법"]}},
     "severity": "medium", "tts": "월급 받는 날짜나 방법이 적혀 있지 않아요. 임금은 매달 정해진 날 전액을 받아야 해요.",
     "refs": [R("labor_standards_act", "제43조"), R("labor_standards_act", "제17조", "②")]},
    {"id": "LAB-014", "doc_types": ["labor_full_time", "labor_part_time"], "title": "미성년자 근로계약",
     "check": {"type": "info", "trigger_keywords": ["친권자", "법정대리인", "보호자 동의"]},
     "severity": "info", "tts": "18세 미만이면 근로조건을 서면으로 받아야 하고, 부모님이 대신 계약할 수는 없어요.",
     "refs": [R("labor_standards_act", "제67조")]},
    {"id": "LAB-015", "doc_types": ["labor_full_time", "labor_part_time"], "title": "근로기준법 기준 미달 조항 일반",
     "check": {"type": "info"}, "severity": "info", "tts": "법 기준보다 나쁜 조건은 그 부분만 무효가 되고 법 기준이 적용돼요.",
     "refs": [R("labor_standards_act", "제15조")]},

    # 주택 임대차
    {"id": "HOU-001", "doc_types": ["lease_housing"], "title": "임대차 기간 2년 미만",
     "check": {"type": "numeric_min", "field": "lease_term_years", "fact": "housing_lease_min_term"},
     "severity": "info", "tts": "계약 기간이 2년보다 짧아도 세입자는 2년을 살 수 있어요.",
     "refs": [R("housing_lease_act", "제4조")]},
    {"id": "HOU-002", "doc_types": ["lease_housing"], "title": "차임·보증금 5% 초과 인상 특약",
     "check": {"type": "numeric_max", "field": "rent_increase_ratio", "fact": "housing_rent_increase_cap",
               "keywords": ["인상", "증액", "올린다", "매년"]},
     "severity": "critical", "tts": "월세나 보증금을 5%보다 많이 올릴 수 있다는 조항이 있어요. 법정 한도를 넘는 부분은 무효예요.",
     "refs": [R("housing_lease_act", "제7조"), R("housing_lease_decree", "제8조"), R("housing_lease_act", "제10조의2")]},
    {"id": "HOU-003", "doc_types": ["lease_housing"], "title": "계약갱신요구권 포기 특약",
     "check": {"type": "forbidden_clause", "keywords": ["갱신요구권", "갱신을 요구하지", "갱신 불가", "재계약 불가", "갱신 포기"]},
     "severity": "critical", "tts": "계약 연장을 요구하지 않겠다는 조항이 있어요. 세입자에게 불리해서 효력이 없어요.",
     "refs": [R("housing_lease_act", "제6조의3"), R("housing_lease_act", "제10조")]},
    {"id": "HOU-004", "doc_types": ["lease_housing"], "title": "전입신고·확정일자 금지 특약",
     "check": {"type": "forbidden_clause", "keywords": ["전입신고 불가", "전입하지", "주민등록 이전 금지", "확정일자 불가", "전입 금지"]},
     "severity": "critical", "tts": "전입신고를 하지 말라는 조항이 있어요. 전입신고를 해야 보증금을 지킬 수 있어요. 아주 위험한 신호예요.",
     "refs": [R("housing_lease_act", "제3조", "①"), R("housing_lease_act", "제3조의2", "②"), R("housing_lease_act", "제10조"), R("resident_registration_act", "제16조")]},
    {"id": "HOU-005", "doc_types": ["lease_housing"], "title": "월세 전환율 초과",
     "check": {"type": "numeric_max", "field": "conversion_rate", "fact": "housing_conversion_rate_cap", "needs_external": "한국은행 기준금리"},
     "severity": "high", "tts": "보증금을 월세로 바꾸는 비율이 법정 한도를 넘어요.",
     "refs": [R("housing_lease_act", "제7조의2"), R("housing_lease_decree", "제9조")]},
    {"id": "HOU-006", "doc_types": ["lease_housing"], "title": "보증금 반환 지연·조건부 반환",
     "check": {"type": "forbidden_clause", "keywords": ["새 임차인", "다음 세입자", "신규 임차인이 구해지면", "반환하지 아니"]},
     "severity": "high", "tts": "다음 세입자가 들어와야 보증금을 돌려준다는 조항이 있어요. 계약이 끝나도 보증금을 받을 때까지 계약은 유지돼요.",
     "refs": [R("housing_lease_act", "제4조", "②"), R("housing_lease_act", "제3조의3")]},
    {"id": "HOU-007", "doc_types": ["lease_housing"], "title": "수선의무 전가 특약",
     "check": {"type": "forbidden_clause", "keywords": ["모든 수리", "수선은 임차인", "보일러 수리비", "하자는 임차인"]},
     "severity": "medium", "tts": "집의 큰 고장까지 세입자가 고치라는 조항이 있어요. 집을 쓸 수 있게 유지하는 건 집주인 의무예요.",
     "refs": [R("civil_act", "제623조"), R("civil_act", "제626조")], "note": "소규모 수선은 특약으로 임차인 부담 가능(판례) — '대규모 수선'만 경고"},
    {"id": "HOU-008", "doc_types": ["lease_housing"], "title": "중도해지·묵시갱신 해지 제한",
     "check": {"type": "forbidden_clause", "keywords": ["해지할 수 없", "중도 해지 시 위약금", "묵시적 갱신 시에도"]},
     "severity": "medium", "tts": "자동으로 연장된 계약은 세입자가 언제든 해지를 알릴 수 있고, 3개월 뒤 끝나요.",
     "refs": [R("housing_lease_act", "제6조의2"), R("housing_lease_act", "제10조")]},
    {"id": "HOU-009", "doc_types": ["lease_housing"], "title": "소액임차인 최우선변제 안내",
     "check": {"type": "info", "field": "deposit", "fact": "housing_small_deposit_priority"},
     "severity": "info", "tts": "보증금이 {limit}원 이하라서, 집이 경매로 넘어가도 {priority}원까지는 먼저 돌려받을 수 있어요.",
     "refs": [R("housing_lease_act", "제8조"), R("housing_lease_decree", "제10조"), R("housing_lease_decree", "제11조")]},
    {"id": "HOU-010", "doc_types": ["lease_housing"], "title": "임대인 정보 확인(납세·선순위)",
     "check": {"type": "info", "trigger_keywords": ["국세", "체납", "선순위", "근저당"]},
     "severity": "info", "tts": "계약 전에 집주인의 세금 체납과 먼저 잡힌 담보를 확인할 수 있어요.",
     "refs": [R("housing_lease_act", "제3조의7"), R("housing_lease_act", "제3조의6")]},
    {"id": "HOU-011", "doc_types": ["lease_housing", "lease_commercial"], "title": "중개보수 상한",
     "check": {"type": "info", "keywords": ["중개보수", "중개수수료", "복비"]},
     "severity": "info", "tts": "중개수수료는 법에서 정한 요율 안에서만 받을 수 있어요.",
     "refs": [R("licensed_realtors_act", "제32조"), R("licensed_realtors_rule", "제20조")]},
    {"id": "HOU-012", "doc_types": ["lease_housing"], "title": "강행규정(불리한 특약 일괄 무효)",
     "check": {"type": "info"}, "severity": "info", "tts": "주택임대차보호법보다 세입자에게 불리한 특약은 효력이 없어요.",
     "refs": [R("housing_lease_act", "제10조")]},

    # 상가 임대차
    {"id": "COM-001", "doc_types": ["lease_commercial"], "title": "상가 차임 5% 초과 인상",
     "check": {"type": "numeric_max", "field": "rent_increase_ratio", "fact": "commercial_rent_increase_cap"},
     "severity": "critical", "tts": "상가 월세를 5%보다 많이 올릴 수 있다는 조항이 있어요.",
     "refs": [R("commercial_lease_act", "제11조"), R("commercial_lease_decree", "제4조")]},
    {"id": "COM-002", "doc_types": ["lease_commercial"], "title": "상가 갱신요구권(10년)·권리금 포기",
     "check": {"type": "forbidden_clause", "keywords": ["권리금 포기", "권리금을 청구하지", "갱신요구권 포기", "원상복구 시 권리금"]},
     "severity": "critical", "tts": "권리금이나 계약 연장 권리를 포기하라는 조항이 있어요. 상가 세입자에게 불리해서 무효예요.",
     "refs": [R("commercial_lease_act", "제10조"), R("commercial_lease_act", "제10조의4"), R("commercial_lease_act", "제15조")]},

    # 약관·소비자
    {"id": "TOS-001", "doc_types": ["*"], "title": "사업자 면책 조항",
     "check": {"type": "forbidden_clause", "keywords": ["책임지지 않", "책임을 지지 아니", "일체의 책임", "면책"]},
     "severity": "high", "tts": "회사가 고의나 큰 잘못에도 책임지지 않는다는 조항이 있어요. 약관법상 무효예요.",
     "refs": [R("standard_terms_act", "제7조")]},
    {"id": "TOS-002", "doc_types": ["*"], "title": "과중한 위약금·지연손해금",
     "check": {"type": "forbidden_clause", "keywords": ["위약금", "지연손해금", "배액", "전액 몰수", "환불 불가"]},
     "severity": "high", "tts": "지나치게 큰 위약금을 물리는 조항이 있어요. 부당하게 과중하면 무효이고, 법원이 줄일 수도 있어요.",
     "refs": [R("standard_terms_act", "제8조"), R("civil_act", "제398조")]},
    {"id": "TOS-003", "doc_types": ["*"], "title": "해지권 박탈·일방적 해지",
     "check": {"type": "forbidden_clause", "keywords": ["해지할 수 없", "해제할 수 없", "회사는 언제든지 해지"]},
     "severity": "high", "tts": "내가 계약을 끝낼 권리를 막거나, 회사만 마음대로 끝낼 수 있는 조항이 있어요.",
     "refs": [R("standard_terms_act", "제9조")]},
    {"id": "TOS-004", "doc_types": ["*"], "title": "일방적 내용 변경",
     "check": {"type": "forbidden_clause", "keywords": ["일방적으로 변경", "임의로 변경", "회사가 정하는 바에 따라"]},
     "severity": "medium", "tts": "회사가 마음대로 내용을 바꿀 수 있다는 조항이 있어요.",
     "refs": [R("standard_terms_act", "제10조")]},
    {"id": "TOS-005", "doc_types": ["*"], "title": "동의 간주 조항",
     "check": {"type": "forbidden_clause", "keywords": ["동의한 것으로 본다", "이의가 없으면", "승인한 것으로 간주"]},
     "severity": "medium", "tts": "아무 말 안 하면 동의한 것으로 보는 조항이 있어요.",
     "refs": [R("standard_terms_act", "제12조")]},
    {"id": "TOS-006", "doc_types": ["*"], "title": "부당한 재판관할·소송 금지",
     "check": {"type": "forbidden_clause", "keywords": ["관할 법원", "소송을 제기할 수 없", "민형사상 이의를 제기하지"]},
     "severity": "medium", "tts": "소송을 못 하게 하거나 먼 곳 법원으로 정한 조항이 있어요.",
     "refs": [R("standard_terms_act", "제14조")]},
    {"id": "TOS-007", "doc_types": ["*"], "title": "약관 설명의무",
     "check": {"type": "info"}, "severity": "info", "tts": "중요한 약관 내용은 사업자가 설명해야 하고, 설명하지 않은 조항은 계약 내용으로 주장할 수 없어요.",
     "refs": [R("standard_terms_act", "제3조"), R("standard_terms_act", "제5조"), R("standard_terms_act", "제6조")]},
    {"id": "CON-001", "doc_types": ["consumer_online"], "title": "온라인 구매 7일 청약철회 배제",
     "check": {"type": "forbidden_clause", "keywords": ["환불 불가", "교환 불가", "반품 불가", "단순 변심"], "fact": "ecommerce_withdrawal_days"},
     "severity": "high", "tts": "온라인으로 산 물건은 받은 날부터 7일 안에 청약을 철회할 수 있어요.",
     "refs": [R("ecommerce_act", "제17조"), R("ecommerce_act", "제35조")]},
    {"id": "CON-002", "doc_types": ["consumer_door_to_door", "consumer_membership"], "title": "방문·전화판매 14일 청약철회",
     "check": {"type": "forbidden_clause", "keywords": ["환불 불가", "철회 불가", "해지 불가"], "fact": "door_to_door_withdrawal_days"},
     "severity": "high", "tts": "방문판매나 전화권유로 산 계약은 계약서를 받은 날부터 14일 안에 철회할 수 있어요.",
     "refs": [R("door_to_door_sales_act", "제8조"), R("door_to_door_sales_act", "제31조"), R("door_to_door_sales_act", "제52조")]},
    {"id": "CON-003", "doc_types": ["consumer_installment", "consumer_funeral"], "title": "할부·선불식 할부 청약철회",
     "check": {"type": "forbidden_clause", "keywords": ["철회 불가", "해약 시 납입금 몰수"], "facts": ["installment_withdrawal_days", "prepaid_installment_withdrawal_days"]},
     "severity": "high", "tts": "할부계약은 7일, 상조처럼 미리 내는 할부는 14일 안에 철회할 수 있어요.",
     "refs": [R("installment_transactions_act", "제8조"), R("installment_transactions_act", "제24조"), R("installment_transactions_act", "제43조")]},

    # 금전
    {"id": "LOA-001", "doc_types": ["loan_private"], "title": "개인 간 차용 연 20% 초과 이자",
     "check": {"type": "numeric_max", "field": "annual_interest_rate", "fact": "private_loan_max_interest", "ocr_patterns": [r"연\s*([\d.]+)\s*%", r"월\s*([\d.]+)\s*%"]},
     "severity": "critical", "tts": "이자가 연 {value}%예요. 법정 최고이자 연 20%를 넘는 부분은 무효예요.",
     "refs": [R("interest_limitation_act", "제2조"), R("interest_limitation_max_rate_decree", "본문")]},
    {"id": "LOA-002", "doc_types": ["loan_lender"], "title": "대부업 연 20% 초과(수수료 포함)",
     "check": {"type": "numeric_max", "field": "annual_interest_rate", "fact": "lender_max_interest", "include": ["수수료", "사례금", "할인금", "공제금"]},
     "severity": "critical", "tts": "수수료까지 합친 이자가 연 20%를 넘어요. 넘는 부분 이자 약정은 무효예요.",
     "refs": [R("money_lending_act", "제8조"), R("money_lending_decree", "제5조"), R("money_lending_act", "제11조")]},

    # 교육
    {"id": "EDU-001", "doc_types": ["tuition"], "title": "등록금 반환 기준",
     "check": {"type": "info", "keywords": ["환불", "반환", "자퇴", "휴학"]},
     "severity": "info", "tts": "대학 등록금은 법에서 정한 기준에 따라 돌려받을 수 있어요.",
     "refs": [R("university_tuition_rule", "제6조")]},

    # 일반·공통
    {"id": "GEN-001", "doc_types": ["*"], "title": "반사회적·불공정 법률행위",
     "check": {"type": "info"}, "severity": "info", "tts": "사회질서에 어긋나거나 약점을 이용해 크게 불공정한 계약은 무효예요.",
     "refs": [R("civil_act", "제103조"), R("civil_act", "제104조")]},
    {"id": "GEN-002", "doc_types": ["*"], "title": "전자서명·패드 서명의 효력",
     "check": {"type": "info"}, "severity": "info", "tts": "화면에 한 전자서명도 종이 서명과 같은 효력을 가질 수 있어요.",
     "refs": [R("electronic_signature_act", "제3조")]},
    {"id": "GEN-003", "doc_types": ["*"], "title": "시각장애인 정보접근·정당한 편의제공",
     "check": {"type": "info"}, "severity": "info", "tts": "장애를 이유로 계약 정보를 제공하지 않는 것은 차별이에요. 읽어주기 같은 편의를 요구할 수 있어요.",
     "refs": [R("disability_discrimination_act", "제20조"), R("disability_discrimination_act", "제21조")]},
]

# ───────────── 근거 조문 검증 + 원문 첨부 ─────────────
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
for r in rules:
    r["refs"] = [resolve(x) for x in r["refs"]]

# 핵심 조문 묶음(laws.json): 규칙·팩트가 참조하는 조문 전문
core_keys = sorted({(x["law_id"], x["article_no"]) for r in rules for x in r["refs"]} |
                   {(x["law_id"], x["article_no"]) for f in facts for x in f.get("basis", [])})
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
    "generated_at": "2026-10-24T15:40:00+09:00",
    "source": "국가법령정보센터(law.go.kr) 원문을 그대로 미러링한 legalize-kr 저장소",
    "source_repo": "https://github.com/legalize-kr/legalize-kr",
    "source_commit": commit,
    "note": "조문 text는 원문 그대로입니다(요약·의역 없음). 일부 법령은 공포되었지만 시행일이 아직 오지 않은 최신본이므로 effective_date를 확인하세요. 최저임금 금액은 법령이 아니라 고용노동부 고시라서 facts.json에 보도 출처와 함께 따로 넣었습니다.",
    "verified_against_law_go_kr": "미러 경유(직접 접속 불가)",
}
(OUT / "laws.json").write_text(json.dumps({"meta": meta, "laws": list(by_law.values())}, ensure_ascii=False, indent=2), encoding="utf-8")
(OUT / "check_rules.json").write_text(json.dumps({"meta": meta | {"rule_count": len(rules)}, "rules": rules}, ensure_ascii=False, indent=2), encoding="utf-8")
(OUT / "facts.json").write_text(json.dumps({"meta": meta | {"fact_count": len(facts)}, "facts": facts}, ensure_ascii=False, indent=2), encoding="utf-8")
print("rules", len(rules), "facts", len(facts), "core laws", len(by_law), "core articles", len(core_keys))
