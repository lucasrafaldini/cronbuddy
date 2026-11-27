import datetime
import pytest

from cronbuddy_linux.schedule import Schedule, ScheduleError, TimeOfDay


def _t(h: int, m: int = 0) -> TimeOfDay:
    return TimeOfDay(h, m)


def test_cron_expressions():
    assert Schedule.interval(15).cron_expressions() == ["*/15 * * * *"]
    assert Schedule.interval(120).cron_expressions() == ["0 */2 * * *"]
    assert Schedule.interval(7).cron_expressions() is None
    assert Schedule.daily([_t(18), _t(9)]).cron_expressions() == ["0 9,18 * * *"]
    assert Schedule.daily([_t(9), _t(9, 30)]).cron_expressions() == ["0 9 * * *", "30 9 * * *"]
    assert Schedule.weekly([5, 1, 3], [_t(7, 45)]).cron_expressions() == ["45 7 * * 1,3,5"]
    assert Schedule.monthly([15, 1], _t(0)).cron_expressions() == ["0 0 1,15 * *"]
    assert Schedule.at_login().cron_expressions() == ["@reboot"]


def test_systemd_triggers():
    assert Schedule.interval(7).systemd_trigger() == ("interval", 420)
    assert Schedule.at_login().systemd_trigger() == ("at_login", None)
    assert Schedule.cron("* * * * *").systemd_trigger() == ("interval", 60)
    assert Schedule.daily([_t(9, 30)]).systemd_trigger() == ("calendar", ["*-*-* 09:30:00"])
    with pytest.raises(ScheduleError):
        Schedule.cron("nope").systemd_trigger()


def test_summaries():
    assert Schedule.interval(1).summary == "Every minute"
    assert Schedule.interval(90).summary == "Every 90 minutes"
    assert Schedule.interval(180).summary == "Every 3 hours"
    assert Schedule.hourly(5).summary == "Every hour at :05"
    assert Schedule.daily([_t(18), _t(9)]).summary == "Every day at 09:00 and 18:00"
    assert Schedule.weekly([1, 2, 3, 4, 5], [_t(9)]).summary == "Weekdays at 09:00"
    assert Schedule.monthly([1, 2, 3, 11, 22], _t(8)).summary == "Monthly on the 1st, 2nd, 3rd, 11th and 22nd at 08:00"
    assert Schedule.cron("0 9,18 * * 1-5").summary == "Weekdays at 09:00 and 18:00"
    assert Schedule.cron("0 0 1 1 *").summary == "Cron · 0 0 1 1 *"


def test_structuring_cron():
    assert Schedule.structured_from_cron("*/10 * * * *") == Schedule.interval(10)
    assert Schedule.structured_from_cron("0 */6 * * *") == Schedule.interval(360)
    assert Schedule.structured_from_cron("20 * * * *") == Schedule.hourly(20)
    assert Schedule.structured_from_cron("0 10,14,17 * * 1-5") == Schedule.weekly(
        [1, 2, 3, 4, 5], [_t(10), _t(14), _t(17)]
    )
    assert Schedule.structured_from_cron("30 6 1 * *") == Schedule.monthly([1], _t(6, 30))
    assert Schedule.structured_from_cron("@reboot") == Schedule.at_login()
    assert Schedule.structured_from_cron("garbage") is None


def test_interval_next_dates_follow_last_run():
    now = datetime.datetime(2026, 1, 1, 2, 46, 40, tzinfo=datetime.timezone.utc)
    last = now - datetime.timedelta(seconds=1000)
    nxt = Schedule.interval(10).next_dates(now, 2, last_run=last)
    assert nxt == [last + datetime.timedelta(minutes=20), last + datetime.timedelta(minutes=30)]


def test_round_trip_dict():
    for s in [
        Schedule.interval(15),
        Schedule.hourly(30),
        Schedule.daily([_t(8), _t(20, 15)]),
        Schedule.weekly([1, 5], [_t(9)]),
        Schedule.monthly([1, 15], _t(12)),
        Schedule.at_login(),
        Schedule.cron("0 0 1 1 *"),
    ]:
        assert Schedule.from_dict(s.to_dict()) == s
