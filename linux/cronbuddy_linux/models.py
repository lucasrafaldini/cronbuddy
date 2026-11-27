"""Job, Action, Backend, and Settings data models for CronBuddy Linux."""

from __future__ import annotations

import datetime
import json
import os
import re
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .schedule import Schedule, ScheduleError, TimeOfDay

VALID_BACKENDS = ("systemd", "cron")
ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def make_job_id() -> str:
    return uuid.uuid4().hex[:10].lower()


@dataclass(frozen=True)
class JobAction:
    kind: str  # "shell" | "script"
    value: str  # command text for "shell", file path for "script"

    @classmethod
    def shell(cls, command: str) -> "JobAction":
        return cls(kind="shell", value=command)

    @classmethod
    def script(cls, path: str) -> "JobAction":
        return cls(kind="script", value=path)

    @property
    def is_empty(self) -> bool:
        return not self.value.strip()

    @property
    def subtitle(self) -> str:
        if self.kind == "shell":
            first = self.value.splitlines()[0].strip() if self.value.strip() else ""
            return first or "Command"
        return Path(self.value).name if self.value.strip() else "Script"

    def to_dict(self) -> dict[str, str]:
        return {"kind": self.kind, "value": self.value}

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "JobAction":
        return cls(kind=str(data["kind"]), value=str(data.get("value", "")))


@dataclass
class Job:
    id: str = field(default_factory=make_job_id)
    name: str = ""
    action: JobAction = field(default_factory=lambda: JobAction.shell(""))
    schedule: Schedule = field(default_factory=lambda: Schedule.daily([TimeOfDay(9, 0)]))
    backend: str = "systemd"
    is_enabled: bool = True
    notify_on_failure: bool = True
    notify_on_success: bool = False
    environment: dict[str, str] = field(default_factory=dict)
    created_at: str = field(
        default_factory=lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
    )

    @staticmethod
    def is_valid_env_name(name: str) -> bool:
        return bool(ENV_NAME_RE.match(name))

    @property
    def problems(self) -> list[str]:
        probs: list[str] = []
        if not self.name.strip():
            probs.append("Give the job a name.")
        if self.action.is_empty:
            probs.append(
                "Enter a command to run."
                if self.action.kind == "shell"
                else "Choose a script file."
            )
        for key in self.environment:
            if not self.is_valid_env_name(key):
                probs.append(f"“{key}” isn’t a valid environment variable name.")
        msg = self.schedule.validation_message
        if msg:
            probs.append(msg)
        else:
            if self.backend == "cron":
                if self.schedule.cron_expressions() is None:
                    probs.append(
                        "cron can’t repeat at this interval. Use systemd, or an interval that divides an hour or a day evenly."
                    )
            elif self.backend == "systemd":
                try:
                    self.schedule.systemd_trigger()
                except ScheduleError as exc:
                    probs.append(str(exc))
            else:
                probs.append(f"Unknown backend: {self.backend}")
        return probs

    @property
    def warnings(self) -> list[str]:
        warns: list[str] = []
        if self.backend == "cron" and self.schedule.kind == "atLogin":
            warns.append("cron runs @reboot jobs when the machine boots, not when you log in.")
        if self.schedule.kind == "monthly" and any(d > 28 for d in self.schedule.days):
            warns.append("Months without that day are skipped.")
        if self.action.kind == "script" and self.action.value.strip():
            if not os.path.exists(os.path.expanduser(self.action.value.strip())):
                warns.append("The script file doesn’t exist at that path.")
        return warns

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "action": self.action.to_dict(),
            "schedule": self.schedule.to_dict(),
            "backend": self.backend,
            "isEnabled": self.is_enabled,
            "notifyOnFailure": self.notify_on_failure,
            "notifyOnSuccess": self.notify_on_success,
            "environment": dict(self.environment),
            "createdAt": self.created_at,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Job":
        return cls(
            id=str(data["id"]),
            name=str(data.get("name", "")),
            action=JobAction.from_dict(data["action"]),
            schedule=Schedule.from_dict(data["schedule"]),
            backend=str(data.get("backend", "systemd")),
            is_enabled=bool(data.get("isEnabled", True)),
            notify_on_failure=bool(data.get("notifyOnFailure", True)),
            notify_on_success=bool(data.get("notifyOnSuccess", False)),
            environment={str(k): str(v) for k, v in data.get("environment", {}).items()},
            created_at=str(
                data.get(
                    "createdAt",
                    datetime.datetime.now(datetime.timezone.utc).isoformat(),
                )
            ),
        )


@dataclass
class Settings:
    theme: str = "system"
    keep_runs: int = 50
    show_countdown: bool = True
    open_at_login: bool = False

    def to_dict(self) -> dict[str, Any]:
        return {
            "theme": self.theme,
            "keepRuns": self.keep_runs,
            "showCountdown": self.show_countdown,
            "openAtLogin": self.open_at_login,
        }

    @classmethod
    def load(cls, path: Path) -> "Settings":
        if not path.exists():
            return cls()
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return cls()
        return cls(
            theme=str(data.get("theme", "system")),
            keep_runs=max(5, int(data.get("keepRuns", 50))),
            show_countdown=bool(data.get("showCountdown", True)),
            open_at_login=bool(data.get("openAtLogin", False)),
        )

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.to_dict(), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        tmp.replace(path)
