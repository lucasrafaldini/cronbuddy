"""Five-field cron expression parser, next-run calculator, and systemd OnCalendar converter."""

from __future__ import annotations

import datetime
from dataclasses import dataclass

MACROS: dict[str, str] = {
    "@yearly": "0 0 1 1 *",
    "@annually": "0 0 1 1 *",
    "@monthly": "0 0 1 * *",
    "@weekly": "0 0 * * 0",
    "@daily": "0 0 * * *",
    "@midnight": "0 0 * * *",
    "@hourly": "0 * * * *",
}

MONTH_NAMES: dict[str, int] = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

DAY_NAMES: dict[str, int] = {
    "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
}

SYSTEMD_DAY_NAMES: dict[int, str] = {
    0: "Sun", 1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat",
}


class CronParseError(ValueError):
    """Raised when a cron expression cannot be parsed."""


def _parse_field(
    field: str, name: str, min_val: int, max_val: int, names: dict[str, int] | None = None
) -> set[int]:
    names = names or {}

    def resolve(token: str) -> int | None:
        try:
            return int(token)
        except ValueError:
            return names.get(token.lower())

    result: set[int] = set()
    for item in field.split(","):
        step_parts = item.split("/")
        if len(step_parts) not in (1, 2) or not step_parts[0]:
            raise CronParseError(f"Invalid {name} field: “{field}”.")
        step = 1
        if len(step_parts) == 2:
            try:
                step = int(step_parts[1])
            except ValueError as exc:
                raise CronParseError(f"Invalid {name} field: “{field}”.") from exc
            if step <= 0:
                raise CronParseError(f"Invalid {name} field: “{field}”.")

        base = step_parts[0]
        if base == "*":
            lower, upper = min_val, max_val
        elif "-" in base:
            parts = base.split("-", 1)
            a, b = resolve(parts[0]), resolve(parts[1])
            if a is None or b is None or a > b:
                raise CronParseError(f"Invalid {name} field: “{field}”.")
            lower, upper = a, b
        else:
            a = resolve(base)
            if a is None:
                raise CronParseError(f"Invalid {name} field: “{field}”.")
            lower = a
            upper = max_val if len(step_parts) == 2 else a

        if not (min_val <= lower <= max_val and min_val <= upper <= max_val):
            raise CronParseError(f"Invalid {name} field: “{field}”.")
        result.update(range(lower, upper + 1, step))
    return result


@dataclass(frozen=True)
class CronExpression:
    minutes: frozenset[int]
    hours: frozenset[int]
    days_of_month: frozenset[int]
    months: frozenset[int]
    days_of_week: frozenset[int]
    dom_restricted: bool
    dow_restricted: bool
    source: str

    @classmethod
    def parse(cls, expression: str) -> "CronExpression":
        trimmed = expression.strip()
        expanded = MACROS.get(trimmed.lower(), trimmed)
        parts = expanded.split()
        if len(parts) != 5:
            raise CronParseError(
                f"Expected 5 fields (minute hour day month weekday), found {len(parts)}."
            )
        minutes = frozenset(_parse_field(parts[0], "minute", 0, 59))
        hours = frozenset(_parse_field(parts[1], "hour", 0, 23))
        dom = frozenset(_parse_field(parts[2], "day of month", 1, 31))
        months = frozenset(_parse_field(parts[3], "month", 1, 12, MONTH_NAMES))
        dow_set = _parse_field(parts[4], "weekday", 0, 7, DAY_NAMES)
        if 7 in dow_set:
            dow_set.discard(7)
            dow_set.add(0)
        return cls(
            minutes=minutes,
            hours=hours,
            days_of_month=dom,
            months=months,
            days_of_week=frozenset(dow_set),
            dom_restricted=not parts[2].startswith("*"),
            dow_restricted=not parts[4].startswith("*"),
            source=trimmed,
        )

    @classmethod
    def is_valid(cls, expression: str) -> bool:
        try:
            cls.parse(expression)
            return True
        except CronParseError:
            return False

    def day_matches(self, day: int, cron_weekday: int) -> bool:
        dom_ok = day in self.days_of_month
        dow_ok = cron_weekday in self.days_of_week
        if self.dom_restricted and self.dow_restricted:
            return dom_ok or dow_ok
        return dom_ok and dow_ok

    def next_date(self, after: datetime.datetime) -> datetime.datetime | None:
        minute_start = after.replace(second=0, microsecond=0)
        earliest = minute_start + datetime.timedelta(minutes=1)
        sorted_hours = sorted(self.hours)
        sorted_minutes = sorted(self.minutes)
        day = earliest.date()

        for _ in range(366 * 5):
            # Python weekday(): Monday=0..Sunday=6; cron: Sunday=0..Saturday=6
            cron_wd = (day.weekday() + 1) % 7
            if day.month in self.months and self.day_matches(day.day, cron_wd):
                for hour in sorted_hours:
                    for minute in sorted_minutes:
                        candidate = datetime.datetime(
                            day.year, day.month, day.day, hour, minute, tzinfo=after.tzinfo
                        )
                        if candidate >= earliest:
                            return candidate
            day += datetime.timedelta(days=1)
        return None

    def next_dates(self, after: datetime.datetime, count: int) -> list[datetime.datetime]:
        result: list[datetime.datetime] = []
        cursor = after
        while len(result) < count:
            nxt = self.next_date(cursor)
            if nxt is None:
                break
            result.append(nxt)
            cursor = nxt
        return result

    def systemd_calendars(self, limit: int = 256) -> list[str] | None:
        """Convert this cron expression to systemd.time(7) OnCalendar strings."""
        min_str = "*" if len(self.minutes) == 60 else ",".join(f"{m:02d}" for m in sorted(self.minutes))
        hour_str = "*" if len(self.hours) == 24 else ",".join(f"{h:02d}" for h in sorted(self.hours))
        month_str = "*" if len(self.months) == 12 else ",".join(f"{m:02d}" for m in sorted(self.months))

        # When both DOM and DOW are restricted, cron ORs them, so emit separate OnCalendar lines.
        variants: list[tuple[str | None, str]] = []
        if not self.dom_restricted and not self.dow_restricted:
            variants = [(None, "*")]
        elif self.dom_restricted and not self.dow_restricted:
            dom_str = ",".join(f"{d:02d}" for d in sorted(self.days_of_month))
            variants = [(None, dom_str)]
        elif not self.dom_restricted and self.dow_restricted:
            if len(self.days_of_week) == 7:
                variants = [(None, "*")]
            else:
                dow_str = ",".join(SYSTEMD_DAY_NAMES[d] for d in sorted(self.days_of_week))
                variants = [(dow_str, "*")]
        else:
            dom_str = ",".join(f"{d:02d}" for d in sorted(self.days_of_month))
            dow_str = ",".join(SYSTEMD_DAY_NAMES[d] for d in sorted(self.days_of_week))
            variants = [(None, dom_str), (dow_str, "*")]

        if len(variants) > limit:
            return None
        lines: list[str] = []
        for dow_prefix, dom_part in variants:
            date_part = f"*-{month_str}-{dom_part}"
            time_part = f"{hour_str}:{min_str}:00"
            if dow_prefix:
                lines.append(f"{dow_prefix} {date_part} {time_part}")
            else:
                lines.append(f"{date_part} {time_part}")
        return lines
