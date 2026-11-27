"""Human-friendly schedule model convertible to cron and systemd timers."""

from __future__ import annotations

import datetime
from dataclasses import dataclass
from typing import Any

from .cron_expr import CronExpression, CronParseError

SHORT_WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]


class ScheduleError(ValueError):
    """Raised when a schedule cannot be lowered to a backend trigger."""


@dataclass(frozen=True, order=True)
class TimeOfDay:
    hour: int
    minute: int

    @property
    def formatted(self) -> str:
        return f"{self.hour:02d}:{self.minute:02d}"

    def to_dict(self) -> dict[str, int]:
        return {"hour": self.hour, "minute": self.minute}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TimeOfDay":
        return cls(hour=int(data["hour"]), minute=int(data["minute"]))


def _join_list(items: list[str]) -> str:
    if not items:
        return ""
    if len(items) == 1:
        return items[0]
    return ", ".join(items[:-1]) + " and " + items[-1]


def _ordinal(n: int) -> str:
    if 11 <= (n % 100) <= 13:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def _describe_weekdays(weekdays: tuple[int, ...] | list[int]) -> str:
    s = set(weekdays)
    if len(s) == 7:
        return "Every day"
    if s == {1, 2, 3, 4, 5}:
        return "Weekdays"
    if s == {0, 6}:
        return "Weekends"
    ordered = sorted(s, key=lambda d: (d + 6) % 7)
    return ", ".join(SHORT_WEEKDAYS[d] for d in ordered)


def _grouped_times(times: tuple[TimeOfDay, ...]) -> list[tuple[int, str]]:
    by_minute: dict[int, set[int]] = {}
    for t in times:
        by_minute.setdefault(t.minute, set()).add(t.hour)
    return [
        (minute, ",".join(str(h) for h in sorted(by_minute[minute])))
        for minute in sorted(by_minute)
    ]


@dataclass(frozen=True)
class Schedule:
    kind: str  # interval | hourly | daily | weekly | monthly | atLogin | cron
    minutes: int | None = None
    minute: int | None = None
    times: tuple[TimeOfDay, ...] = ()
    weekdays: tuple[int, ...] = ()
    days: tuple[int, ...] = ()
    time: TimeOfDay | None = None
    expression: str | None = None

    @classmethod
    def interval(cls, minutes: int) -> "Schedule":
        return cls(kind="interval", minutes=minutes)

    @classmethod
    def hourly(cls, minute: int) -> "Schedule":
        return cls(kind="hourly", minute=minute)

    @classmethod
    def daily(cls, times: list[TimeOfDay]) -> "Schedule":
        return cls(kind="daily", times=tuple(times))

    @classmethod
    def weekly(cls, weekdays: list[int], times: list[TimeOfDay]) -> "Schedule":
        return cls(kind="weekly", weekdays=tuple(weekdays), times=tuple(times))

    @classmethod
    def monthly(cls, days: list[int], time: TimeOfDay) -> "Schedule":
        return cls(kind="monthly", days=tuple(days), time=time)

    @classmethod
    def at_login(cls) -> "Schedule":
        return cls(kind="atLogin")

    @classmethod
    def cron(cls, expression: str) -> "Schedule":
        return cls(kind="cron", expression=expression)

    def cron_expressions(self) -> list[str] | None:
        if self.kind == "interval":
            n = self.minutes or 0
            if n == 1:
                return ["* * * * *"]
            if 0 < n < 60 and 60 % n == 0:
                return [f"*/{n} * * * *"]
            if n >= 60 and n % 60 == 0:
                h = n // 60
                if h == 1:
                    return ["0 * * * *"]
                if h == 24:
                    return ["0 0 * * *"]
                if 24 % h == 0:
                    return [f"0 */{h} * * *"]
            return None
        if self.kind == "hourly":
            return [f"{self.minute or 0} * * * *"]
        if self.kind == "daily":
            if not self.times:
                return None
            return [f"{m} {hrs} * * *" for m, hrs in _grouped_times(self.times)]
        if self.kind == "weekly":
            if not self.weekdays or not self.times:
                return None
            wd_set = sorted(set(self.weekdays))
            dow = "*" if len(wd_set) == 7 else ",".join(str(d) for d in wd_set)
            return [f"{m} {hrs} * * {dow}" for m, hrs in _grouped_times(self.times)]
        if self.kind == "monthly":
            if not self.days or self.time is None:
                return None
            day_str = ",".join(str(d) for d in sorted(set(self.days)))
            return [f"{self.time.minute} {self.time.hour} {day_str} * *"]
        if self.kind == "atLogin":
            return ["@reboot"]
        if self.kind == "cron":
            return [(self.expression or "").strip()]
        return None

    def _parsed_expressions(self) -> list[CronExpression] | None:
        exprs = self.cron_expressions()
        if exprs is None:
            return None
        parsed: list[CronExpression] = []
        for expr in exprs:
            try:
                parsed.append(CronExpression.parse(expr))
            except CronParseError:
                return None
        return parsed

    def systemd_trigger(self) -> tuple[str, Any]:
        """Return ('interval', seconds) | ('calendar', list[str]) | ('at_login', None)."""
        if self.kind == "interval":
            n = self.minutes or 0
            if n <= 0:
                raise ScheduleError("Interval must be at least one minute.")
            return ("interval", n * 60)
        if self.kind == "atLogin":
            return ("at_login", None)

        parsed = self._parsed_expressions()
        if not parsed:
            raise ScheduleError(self.validation_message or "Invalid schedule.")
        calendars: list[str] = []
        for expr in parsed:
            if (
                len(expr.minutes) == 60
                and len(expr.hours) == 24
                and not expr.dom_restricted
                and not expr.dow_restricted
                and len(expr.months) == 12
            ):
                return ("interval", 60)
            more = expr.systemd_calendars()
            if more is None:
                raise ScheduleError("This cron expression expands to too many systemd entries.")
            calendars.extend(more)
        if len(calendars) > 256:
            raise ScheduleError("This cron expression expands to too many systemd entries.")
        return ("calendar", calendars)

    @property
    def validation_message(self) -> str | None:
        if self.kind == "interval":
            return None if (self.minutes or 0) >= 1 else "Interval must be at least one minute."
        if self.kind == "hourly":
            m = self.minute if self.minute is not None else -1
            return None if 0 <= m <= 59 else "Minute must be between 0 and 59."
        if self.kind == "daily":
            return None if self.times else "Add at least one time."
        if self.kind == "weekly":
            if not self.weekdays:
                return "Pick at least one weekday."
            return None if self.times else "Add at least one time."
        if self.kind == "monthly":
            return None if self.days else "Pick at least one day of the month."
        if self.kind == "atLogin":
            return None
        if self.kind == "cron":
            try:
                CronExpression.parse(self.expression or "")
                return None
            except CronParseError as exc:
                return str(exc)
        return f"Unknown schedule kind: {self.kind}"

    @property
    def is_approximate(self) -> bool:
        return self.kind == "interval"

    def next_dates(
        self, after: datetime.datetime, count: int, last_run: datetime.datetime | None = None
    ) -> list[datetime.datetime]:
        if self.kind == "atLogin":
            return []
        if self.kind == "interval":
            n = self.minutes or 0
            if n <= 0:
                return []
            step = datetime.timedelta(minutes=n)
            nxt = (last_run or after) + step
            if nxt <= after:
                missed = int((after - nxt).total_seconds() // step.total_seconds()) + 1
                nxt = nxt + step * missed
            return [nxt + step * i for i in range(count)]
        parsed = self._parsed_expressions()
        if not parsed:
            return []
        merged: set[datetime.datetime] = set()
        for expr in parsed:
            merged.update(expr.next_dates(after, count))
        return sorted(merged)[:count]

    @property
    def summary(self) -> str:
        if self.kind == "interval":
            n = self.minutes or 0
            if n == 1:
                return "Every minute"
            if n % 1440 == 0:
                return "Every day" if n == 1440 else f"Every {n // 1440} days"
            if n % 60 == 0:
                return "Every hour" if n == 60 else f"Every {n // 60} hours"
            return f"Every {n} minutes"
        if self.kind == "hourly":
            m = self.minute or 0
            return "Every hour, on the hour" if m == 0 else f"Every hour at :{m:02d}"
        if self.kind == "daily":
            return f"Every day at {_join_list([t.formatted for t in sorted(self.times)])}"
        if self.kind == "weekly":
            return f"{_describe_weekdays(self.weekdays)} at {_join_list([t.formatted for t in sorted(self.times)])}"
        if self.kind == "monthly":
            ordinals = [_ordinal(d) for d in sorted(set(self.days))]
            t = self.time or TimeOfDay(0, 0)
            return f"Monthly on the {_join_list(ordinals)} at {t.formatted}"
        if self.kind == "atLogin":
            return "At login"
        if self.kind == "cron":
            expr = self.expression or ""
            structured = Schedule.structured_from_cron(expr)
            if structured is not None and structured.kind != "cron":
                return structured.summary
            return f"Cron · {expr}"
        return self.kind

    @classmethod
    def structured_from_cron(cls, expression: str) -> "Schedule | None":
        trimmed = expression.strip()
        if trimmed.lower() == "@reboot":
            return cls.at_login()
        try:
            e = CronExpression.parse(trimmed)
        except CronParseError:
            return None
        if len(e.months) != 12:
            return cls.cron(trimmed)

        if not e.dom_restricted and not e.dow_restricted:
            if len(e.hours) == 24:
                if len(e.minutes) == 1:
                    return cls.hourly(next(iter(e.minutes)))
                for step in (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30):
                    if e.minutes == frozenset(range(0, 60, step)):
                        return cls.interval(step)
            elif e.minutes == frozenset({0}):
                for step in (2, 3, 4, 6, 8, 12):
                    if e.hours == frozenset(range(0, 24, step)):
                        return cls.interval(step * 60)

        times = sorted(TimeOfDay(h, m) for h in e.hours for m in e.minutes)
        if len(e.hours) < 24 and times and len(times) <= 12:
            if not e.dom_restricted and not e.dow_restricted:
                return cls.daily(times)
            if not e.dom_restricted and e.dow_restricted:
                return cls.weekly(sorted(e.days_of_week), times)
            if e.dom_restricted and not e.dow_restricted and len(times) == 1:
                return cls.monthly(sorted(e.days_of_month), times[0])
        return cls.cron(trimmed)

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {"kind": self.kind}
        if self.kind == "interval":
            d["minutes"] = self.minutes
        elif self.kind == "hourly":
            d["minute"] = self.minute
        elif self.kind == "daily":
            d["times"] = [t.to_dict() for t in self.times]
        elif self.kind == "weekly":
            d["weekdays"] = list(self.weekdays)
            d["times"] = [t.to_dict() for t in self.times]
        elif self.kind == "monthly":
            d["days"] = list(self.days)
            d["time"] = self.time.to_dict() if self.time else TimeOfDay(9, 0).to_dict()
        elif self.kind == "cron":
            d["expression"] = self.expression or ""
        return d

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Schedule":
        kind = data["kind"]
        if kind == "interval":
            return cls.interval(int(data["minutes"]))
        if kind == "hourly":
            return cls.hourly(int(data["minute"]))
        if kind == "daily":
            return cls.daily([TimeOfDay.from_dict(t) for t in data.get("times", [])])
        if kind == "weekly":
            return cls.weekly(
                [int(w) for w in data.get("weekdays", [])],
                [TimeOfDay.from_dict(t) for t in data.get("times", [])],
            )
        if kind == "monthly":
            return cls.monthly(
                [int(d) for d in data.get("days", [])],
                TimeOfDay.from_dict(data["time"]),
            )
        if kind == "atLogin":
            return cls.at_login()
        if kind == "cron":
            return cls.cron(str(data.get("expression", "")))
        raise ValueError(f"Unknown schedule kind: {kind}")
