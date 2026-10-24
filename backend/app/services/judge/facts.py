"""3단계: 날짜(계약 시작일)에 맞는 법정 기준값을 고르고, 월급을 시급으로 환산한다."""

from __future__ import annotations

import datetime

from . import data as D


def pick_year(contract_start: datetime.date | None) -> int:
    if contract_start:
        return contract_start.year
    return datetime.date.today().year


def fact_value(fact_id_template: str, year: int) -> dict | None:
    """'min_wage_{year}_hourly' 같은 템플릿에 연도를 채워 facts.json에서 찾는다."""
    fid = fact_id_template.format(year=year)
    return D.facts().get(fid)


def hourly_from_monthly(monthly: float, weekly_hours: float = 40.0) -> float:
    """월급을 시급으로 환산한다.

    주 40시간 기준이면 209시간(주휴 포함 월 환산 시간)으로 나눈다.
    주 근로시간이 다르면, 그 시간 대비 주휴시간을 비례로 더해 4.345주를 곱한 값으로 나눈다.
    (설계서의 근사식. 정확한 주휴수당 계산은 추후 보정)
    """
    if weekly_hours >= 40:
        return monthly / 209
    weekly_with_holiday = weekly_hours + (weekly_hours / 40) * 8
    monthly_hours = weekly_with_holiday * 4.345
    if monthly_hours <= 0:
        return monthly
    return monthly / monthly_hours
