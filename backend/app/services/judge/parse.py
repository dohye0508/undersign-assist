"""금액·시간·날짜·비율 숫자 읽기. 모두 순수 함수이며, 글자를 못 읽으면 None을 돌려준다.

설계서(판단 단계 논리 구조 설계) 2단계에서 쓴다.
"""

from __future__ import annotations

import re
import datetime

_HANGUL_DIGITS = {
    "영": 0, "일": 1, "이": 2, "삼": 3, "사": 4,
    "오": 5, "육": 6, "륙": 6, "칠": 7, "팔": 8, "구": 9,
}
_HANGUL_SMALL_UNITS = {"십": 10, "백": 100, "천": 1000}
_HANGUL_BIG_UNITS = {"만": 10_000, "억": 100_000_000, "조": 1_000_000_000_000}


def _fix_ocr_digits(s: str) -> str:
    """흔한 OCR 오타를 숫자로 고친다 (O→0, l/I→1, B→8 등 자릿수 안에서만)."""
    return (
        s.replace("O", "0").replace("o", "0")
        .replace("l", "1").replace("I", "1")
    )


def _hangul_number_to_int(s: str) -> int | None:
    """'오천만' '이백오십만' 같은 한글 숫자를 정수로. 모르는 글자가 섞이면 None."""
    if not s:
        return None
    total = 0
    section = 0
    num = 0
    for ch in s:
        if ch in _HANGUL_DIGITS:
            num = _HANGUL_DIGITS[ch]
        elif ch in _HANGUL_SMALL_UNITS:
            section += (num or 1) * _HANGUL_SMALL_UNITS[ch]
            num = 0
        elif ch in _HANGUL_BIG_UNITS:
            section += num
            total += (section or 1) * _HANGUL_BIG_UNITS[ch]
            section = 0
            num = 0
        else:
            return None
    total += section + num
    return total if total > 0 else None


def parse_money(text: str) -> int | None:
    """'시급 10,000원' '금 오천만원정' '5천만원' 등에서 금액(원)을 뽑는다."""
    if not text:
        return None
    t = _fix_ocr_digits(text)

    m = re.search(r"([\d,]+)\s*억\s*([\d,]+)?\s*만?\s*원", t)
    if m:
        eok = int(m.group(1).replace(",", "") or 0)
        man = int((m.group(2) or "0").replace(",", "") or 0)
        return eok * 100_000_000 + man * 10_000

    m = re.search(r"([\d,]+)\s*만\s*원", t)
    if m:
        return int(m.group(1).replace(",", "")) * 10_000

    m = re.search(r"([\d][\d,]*)\s*원", t)
    if m:
        v = m.group(1).replace(",", "")
        if v.isdigit():
            return int(v)

    m = re.search(r"(?:금\s*)?([일이삼사오육륙칠팔구십백천만억]+)\s*원", t)
    if m:
        return _hangul_number_to_int(m.group(1))

    return None


def parse_percent(text: str) -> float | None:
    """'연 24%' '매년 10% 인상' → 0.24 / 0.10"""
    if not text:
        return None
    t = _fix_ocr_digits(text)
    m = re.search(r"([\d]+(?:\.\d+)?)\s*%", t)
    if m:
        return float(m.group(1)) / 100
    return None


def parse_time_range(text: str) -> tuple[float, float] | None:
    """'09:00~18:00' 같은 문장에서 (시작시, 끝시)를 시 단위 소수로."""
    if not text:
        return None
    t = _fix_ocr_digits(text)
    m = re.search(
        r"(\d{1,2})\s*[:시]\s*(\d{0,2})?\s*(?:분)?\s*[~\-–—]|부터",
        t,
    )
    m = re.search(
        r"(\d{1,2})\s*[:시]\s*(\d{0,2})?\s*(?:분)?\s*(?:[~\-–—]|부터)\s*"
        r"(\d{1,2})\s*[:시]\s*(\d{0,2})?",
        t,
    )
    if not m:
        return None
    h1, m1, h2, m2 = m.groups()
    start = int(h1) + (int(m1) / 60 if m1 else 0)
    end = int(h2) + (int(m2) / 60 if m2 else 0)
    return (start, end)


def parse_minutes(text: str) -> int | None:
    """'휴게 1시간' '12:00~13:00' 같은 문장에서 분(min)을 뽑는다."""
    if not text:
        return None
    rng = parse_time_range(text)
    if rng:
        return max(int(round((rng[1] - rng[0]) * 60)), 0)
    t = _fix_ocr_digits(text)
    h = re.search(r"(\d+)\s*시간", t)
    mi = re.search(r"(\d+)\s*분", t)
    hours = int(h.group(1)) if h else 0
    minutes = int(mi.group(1)) if mi else 0
    if h or mi:
        return hours * 60 + minutes
    return None


def parse_date(text: str) -> datetime.date | None:
    """'2026. 3. 1.' '2026년 3월 1일' → date"""
    if not text:
        return None
    t = _fix_ocr_digits(text)
    m = re.search(r"(\d{4})\s*[.\-년]\s*(\d{1,2})\s*[.\-월]\s*(\d{1,2})", t)
    if not m:
        return None
    y, mo, d = (int(x) for x in m.groups())
    try:
        return datetime.date(y, mo, d)
    except ValueError:
        return None


def parse_dates(text: str) -> list[datetime.date]:
    """문장 안의 날짜를 모두 (순서대로). '2026.3.1 ~ 2028.2.28' → 두 개."""
    if not text:
        return []
    t = _fix_ocr_digits(text)
    out = []
    for m in re.finditer(r"(\d{4})\s*[.\-년/]\s*(\d{1,2})\s*[.\-월/]\s*(\d{1,2})", t):
        y, mo, d = (int(x) for x in m.groups())
        try:
            out.append(datetime.date(y, mo, d))
        except ValueError:
            continue
    return out


def parse_duration_years(text: str) -> float | None:
    """'2년' '24개월' '1년 6개월' → 년(소수). 날짜가 두 개 있으면 그 차이."""
    if not text:
        return None
    dates = parse_dates(text)
    if len(dates) >= 2 and dates[1] > dates[0]:
        # 끝나는 날을 하루 포함해서 센다 (2026.3.1~2028.2.28 = 2년)
        return round(((dates[1] - dates[0]).days + 1) / 365.25, 2)
    t = _fix_ocr_digits(text)
    y = re.search(r"(\d+)\s*년(?!\s*\d)", t)
    mo = re.search(r"(\d+)\s*개월", t)
    if y or mo:
        return round((int(y.group(1)) if y else 0) + (int(mo.group(1)) / 12 if mo else 0), 2)
    return None


def parse_hours_per(text: str, unit: str) -> float | None:
    """'1일 8시간' '하루 6시간' (unit='day') / '주 40시간' '1주 15시간' (unit='week')"""
    if not text:
        return None
    t = _fix_ocr_digits(text)
    prefix = r"(?:1\s*일|하루|일일|매일)" if unit == "day" else r"(?:1\s*주|주|매주|일주일)"
    m = re.search(prefix + r"\s*(?:소정)?\s*(?:근로|근무)?\s*(?:시간)?\s*[:은는]?\s*(\d+(?:\.\d+)?)\s*시간", t)
    return float(m.group(1)) if m else None


def parse_days_per_week(text: str) -> int | None:
    """'주 5일' '월~금' '매주 화,목' → 일 수"""
    if not text:
        return None
    t = _fix_ocr_digits(text)
    m = re.search(r"주\s*(\d)\s*일", t)
    if m:
        return int(m.group(1))
    days = "월화수목금토일"
    m = re.search(r"([월화수목금토일])\s*(?:요일)?\s*[~\-–부터]\s*([월화수목금토일])\s*요?일?", t)
    if m:
        a, b = days.index(m.group(1)), days.index(m.group(2))
        if b >= a:
            return b - a + 1
    m = re.search(r"(?:매주|주)\s*((?:[월화수목금토일]\s*(?:요일)?\s*[,ㆍ·、 ]\s*)+[월화수목금토일])", t)
    if m:
        listed = set(re.findall(r"[월화수목금토일]", m.group(1)))
        if len(listed) >= 2:
            return len(listed)
    return None


def parse_annual_rate(text: str) -> float | None:
    """'연 24%' → 0.24, '월 2%' → 0.24 (월 이자는 12를 곱해 연으로)."""
    if not text:
        return None
    t = _fix_ocr_digits(text)
    m = re.search(r"(연|년|월)\s*(?:이자|이율)?\s*[:은는]?\s*(\d+(?:\.\d+)?)\s*%", t)
    if m:
        rate = float(m.group(2)) / 100
        return round(rate * 12, 4) if m.group(1) == "월" else rate
    p = parse_percent(t)
    return p
