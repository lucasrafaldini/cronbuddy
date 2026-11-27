import datetime
import shutil
import subprocess

import pytest

from cronbuddy_linux.cron_expr import CronExpression, CronParseError


def _utc(y: int, mo: int, d: int, h: int = 0, mi: int = 0) -> datetime.datetime:
    return datetime.datetime(y, mo, d, h, mi, tzinfo=datetime.timezone.utc)


def test_parses_lists_ranges_and_steps():
    e = CronExpression.parse("*/15 9-17 * * 1-5")
    assert e.minutes == frozenset({0, 15, 30, 45})
    assert e.hours == frozenset(range(9, 18))
    assert e.days_of_week == frozenset({1, 2, 3, 4, 5})
    assert not e.dom_restricted
    assert e.dow_restricted


def test_parses_names_macros_and_sunday_seven():
    assert CronExpression.parse("0 0 * jan,dec sun").months == frozenset({1, 12})
    assert CronExpression.parse("0 0 * * 7").days_of_week == frozenset({0})
    assert CronExpression.parse("@daily").minutes == frozenset({0})
    assert CronExpression.parse("5/20 * * * *").minutes == frozenset({5, 25, 45})


@pytest.mark.parametrize(
    "expr",
    ["", "* * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "*/0 * * * *", "a b c d e", "5-1 * * * *"],
)
def test_rejects_invalid(expr: str):
    assert not CronExpression.is_valid(expr)
    with pytest.raises(CronParseError):
        CronExpression.parse(expr)


def test_next_date_rolls_over_days_and_months():
    e = CronExpression.parse("30 8 * * *")
    assert e.next_date(_utc(2026, 1, 31, 9)) == _utc(2026, 2, 1, 8, 30)
    assert e.next_date(_utc(2026, 1, 31, 8, 29)) == _utc(2026, 1, 31, 8, 30)
    assert e.next_date(_utc(2026, 1, 31, 8, 30)) == _utc(2026, 2, 1, 8, 30)


def test_day_of_month_and_weekday_are_ored():
    e = CronExpression.parse("0 12 13 * 5")
    nxt = e.next_dates(_utc(2026, 3, 1), 3)
    assert nxt == [_utc(2026, 3, 6, 12), _utc(2026, 3, 13, 12), _utc(2026, 3, 20, 12)]


def test_finds_leap_day():
    e = CronExpression.parse("0 0 29 2 *")
    assert e.next_date(_utc(2026, 3, 1)) == _utc(2028, 2, 29)


def test_systemd_calendars_expansion():
    weekdays = CronExpression.parse("0 9,18 * * 1-5").systemd_calendars()
    assert weekdays == ["Mon,Tue,Wed,Thu,Fri *-*-* 09,18:00:00"]

    hourly = CronExpression.parse("15 * * * *").systemd_calendars()
    assert hourly == ["*-*-* *:15:00"]

    ored = CronExpression.parse("0 12 13 * 5").systemd_calendars()
    assert ored == ["*-*-13 12:00:00", "Fri *-*-* 12:00:00"]

    if shutil.which("systemd-analyze"):
        for cal in (weekdays or []) + (hourly or []) + (ored or []):
            proc = subprocess.run(["systemd-analyze", "calendar", cal], capture_output=True, text=True)
            assert proc.returncode == 0, f"systemd-analyze rejected {cal}: {proc.stderr}"
