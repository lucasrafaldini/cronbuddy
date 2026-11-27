"""Linux crontab, systemd --user backends, and JobStore persistence."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from .cron_expr import CronExpression
from .models import Job
from .paths import Paths
from .runner import ActionScript, RunHistory, shell_quote


class BackendError(RuntimeError):
    """Raised when applying a job to cron or systemd fails."""


@dataclass(frozen=True)
class ExternalCronEntry:
    line: str
    schedule: str
    command: str
    comment: str | None

    @property
    def id(self) -> str:
        return self.line


@dataclass(frozen=True)
class ExternalSystemdTimer:
    unit: str
    next_trigger: str
    left: str
    last_trigger: str
    activates: str


def default_runner_command() -> list[str]:
    """Command used by systemd/cron to invoke CronBuddy in --run-job mode."""
    exe = shutil.which("cronbuddy") or shutil.which("cronbuddy-linux")
    if exe:
        return [exe]
    return [sys.executable, "-m", "cronbuddy_linux"]


class CrontabBackend:
    MARKER = "# cronbuddy:"

    @staticmethod
    def read() -> str:
        if os.environ.get("CRONBUDDY_HOME"):
            return ""
        cron_bin = shutil.which("crontab")
        if not cron_bin:
            return ""
        proc = subprocess.run([cron_bin, "-l"], capture_output=True, text=True, check=False)
        if proc.returncode == 0:
            return proc.stdout
        if "no crontab" in proc.stderr.lower():
            return ""
        raise BackendError(f"Couldn’t read your crontab: {proc.stderr.strip()}")

    @staticmethod
    def write(text: str) -> None:
        if os.environ.get("CRONBUDDY_HOME"):
            return
        cron_bin = shutil.which("crontab")
        if not cron_bin:
            raise BackendError("crontab command is not installed on this system.")
        proc = subprocess.run(
            [cron_bin, "-"], input=text, capture_output=True, text=True, check=False
        )
        if proc.returncode != 0:
            raise BackendError(f"Couldn’t update your crontab: {proc.stderr.strip()}")

    @classmethod
    def lines_for(
        cls, job: Job, runner_cmd: list[str] | None = None
    ) -> list[str]:
        if job.backend != "cron" or not job.is_enabled:
            return []
        exprs = job.schedule.cron_expressions()
        if not exprs:
            return []
        cmd_parts = [shell_quote(p) for p in (runner_cmd or default_runner_command())]
        cmd = " ".join(cmd_parts) + f" --run-job {shell_quote(job.id)} --trigger schedule"
        return [f"{expr} {cmd} {cls.MARKER}{job.id}" for expr in exprs]

    @classmethod
    def merged(
        cls, existing: str, jobs: list[Job], runner_cmd: list[str] | None = None
    ) -> str:
        kept = [ln for ln in existing.splitlines() if cls.MARKER not in ln]
        while kept and not kept[-1].strip():
            kept.pop()
        managed = [ln for job in jobs for ln in cls.lines_for(job, runner_cmd=runner_cmd)]
        all_lines = kept + managed
        return "\n".join(all_lines) + "\n" if all_lines else ""

    @classmethod
    def sync(cls, jobs: list[Job], runner_cmd: list[str] | None = None) -> None:
        if os.environ.get("CRONBUDDY_HOME"):
            return
        has_cron_jobs = any(j.backend == "cron" and j.is_enabled for j in jobs)
        existing = cls.read()
        if not existing and not has_cron_jobs:
            return
        updated = cls.merged(existing, jobs, runner_cmd=runner_cmd)
        if updated.strip() != existing.strip():
            cls.write(updated)

    @classmethod
    def external_entries(cls, text: str) -> list[ExternalCronEntry]:
        entries: list[ExternalCronEntry] = []
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or cls.MARKER in line:
                continue
            tokens = line.split()
            if tokens[0].startswith("@"):
                sched_count = 1
            else:
                if "=" in tokens[0]:
                    continue
                sched_count = 5
            if len(tokens) <= sched_count:
                continue
            schedule = " ".join(tokens[:sched_count])
            if schedule.lower() != "@reboot" and not CronExpression.is_valid(schedule):
                continue
            command = " ".join(tokens[sched_count:])
            comment: str | None = None
            idx = command.rfind(" # ")
            if idx != -1:
                comment = command[idx + 3 :].strip()
                command = command[:idx]
            entries.append(
                ExternalCronEntry(line=raw, schedule=schedule, command=command, comment=comment)
            )
        return entries

    @staticmethod
    def removing(entry: ExternalCronEntry, from_text: str) -> str:
        lines = from_text.splitlines()
        if entry.line in lines:
            lines.remove(entry.line)
        return ("\n".join(lines) + "\n") if lines else ""


class SystemdBackend:
    @staticmethod
    def render_service(
        job: Job, paths: Paths, runner_cmd: list[str] | None = None
    ) -> str:
        cmd = " ".join(shell_quote(p) for p in (runner_cmd or default_runner_command()))
        exec_line = f"{cmd} --run-job {shell_quote(job.id)} --trigger schedule"
        lines = [
            "[Unit]",
            f"Description=CronBuddy: {job.name}",
            "After=network-online.target",
            "",
            "[Service]",
            "Type=oneshot",
            f"ExecStart={exec_line}",
            "",
        ]
        if job.backend == "systemd":
            trig_kind, _ = job.schedule.systemd_trigger()
            if trig_kind == "at_login":
                lines.extend(["[Install]", "WantedBy=default.target", ""])
        return "\n".join(lines)

    @staticmethod
    def render_timer(job: Job, paths: Paths) -> str | None:
        if job.backend != "systemd":
            return None
        trig_kind, payload = job.schedule.systemd_trigger()
        if trig_kind == "at_login":
            return None
        lines = [
            "[Unit]",
            f"Description=CronBuddy timer: {job.name}",
            "",
            "[Timer]",
        ]
        if trig_kind == "interval":
            seconds = int(payload)
            lines.append("OnBootSec=1min")
            lines.append(f"OnUnitActiveSec={seconds}s")
        elif trig_kind == "calendar":
            for cal in payload:
                lines.append(f"OnCalendar={cal}")
        lines.extend(
            [
                "Persistent=true",
                "",
                "[Install]",
                "WantedBy=timers.target",
                "",
            ]
        )
        return "\n".join(lines)

    @staticmethod
    def _systemctl(*args: str) -> subprocess.CompletedProcess[str] | None:
        if os.environ.get("CRONBUDDY_HOME"):
            return None
        sc = shutil.which("systemctl")
        if not sc:
            return None
        return subprocess.run(
            [sc, "--user", *args], capture_output=True, text=True, check=False
        )

    @classmethod
    def install(
        cls, job: Job, paths: Paths, runner_cmd: list[str] | None = None
    ) -> None:
        paths.systemd_user_dir.mkdir(parents=True, exist_ok=True)
        svc_text = cls.render_service(job, paths, runner_cmd=runner_cmd)
        timer_text = cls.render_timer(job, paths)

        svc_path = paths.service_file(job.id)
        timer_path = paths.timer_file(job.id)
        svc_changed = not svc_path.exists() or svc_path.read_text(encoding="utf-8") != svc_text
        timer_changed = (
            (timer_text is None and timer_path.exists())
            or (
                timer_text is not None
                and (not timer_path.exists() or timer_path.read_text(encoding="utf-8") != timer_text)
            )
        )

        if svc_changed:
            svc_path.write_text(svc_text, encoding="utf-8")
        if timer_text is None:
            if timer_path.exists():
                cls._systemctl("disable", "--now", f"{paths.unit_name(job.id)}.timer")
                timer_path.unlink(missing_ok=True)
        elif timer_changed:
            timer_path.write_text(timer_text, encoding="utf-8")

        if os.environ.get("CRONBUDDY_HOME") or paths.sandboxed:
            return

        cls._systemctl("daemon-reload")
        unit = paths.unit_name(job.id)
        if job.backend == "systemd" and job.is_enabled:
            if timer_text is not None:
                res = cls._systemctl("enable", "--now", f"{unit}.timer")
                if res and res.returncode != 0:
                    raise BackendError(f"systemd refused “{job.name}”: {res.stderr.strip()}")
            else:
                res = cls._systemctl("enable", f"{unit}.service")
                if res and res.returncode != 0:
                    raise BackendError(f"systemd refused “{job.name}”: {res.stderr.strip()}")

    @classmethod
    def uninstall(cls, job_id: str, paths: Paths) -> None:
        unit = paths.unit_name(job_id)
        if not paths.sandboxed and not os.environ.get("CRONBUDDY_HOME"):
            cls._systemctl("disable", "--now", f"{unit}.timer")
            cls._systemctl("disable", f"{unit}.service")
        paths.timer_file(job_id).unlink(missing_ok=True)
        paths.service_file(job_id).unlink(missing_ok=True)
        if not paths.sandboxed and not os.environ.get("CRONBUDDY_HOME"):
            cls._systemctl("daemon-reload")

    @staticmethod
    def installed_ids(paths: Paths) -> list[str]:
        if not paths.systemd_user_dir.exists():
            return []
        ids: set[str] = set()
        for fp in paths.systemd_user_dir.iterdir():
            if fp.name.startswith(paths.label_prefix) and fp.suffix in (".service", ".timer"):
                ids.add(fp.name[len(paths.label_prefix) : -len(fp.suffix)])
        return sorted(ids)

    @classmethod
    def external_timers(cls, paths: Paths) -> list[ExternalSystemdTimer]:
        res = cls._systemctl("list-timers", "--all", "--output=json")
        if not res or res.returncode != 0:
            return []
        try:
            items = json.loads(res.stdout)
        except Exception:
            return []
        timers: list[ExternalSystemdTimer] = []
        for item in items:
            unit = str(item.get("unit", ""))
            if not unit or unit.startswith(paths.label_prefix):
                continue
            timers.append(
                ExternalSystemdTimer(
                    unit=unit,
                    next_trigger=str(item.get("next") or "—"),
                    left=str(item.get("left") or "—"),
                    last_trigger=str(item.get("last") or "—"),
                    activates=str(item.get("activates") or "—"),
                )
            )
        return timers


class JobStore:
    def __init__(self, paths: Paths | None = None, runner_cmd: list[str] | None = None):
        self.paths = paths or Paths.standard()
        self.runner_cmd = runner_cmd

    def load(self) -> list[Job]:
        if not self.paths.jobs_file.exists():
            return []
        data = json.loads(self.paths.jobs_file.read_text(encoding="utf-8"))
        return [Job.from_dict(item) for item in data]

    def save(self, jobs: list[Job]) -> None:
        self.paths.config_dir.mkdir(parents=True, exist_ok=True)
        tmp = self.paths.jobs_file.with_suffix(".tmp")
        payload = json.dumps([j.to_dict() for j in jobs], indent=2, sort_keys=True) + "\n"
        tmp.write_text(payload, encoding="utf-8")
        tmp.replace(self.paths.jobs_file)

    def apply(self, job: Job, all_jobs: list[Job], previous: Job | None = None) -> None:
        ActionScript.write(job, self.paths.action_script(job.id))
        if previous and previous.backend != job.backend:
            self._remove_from_backend(previous, all_jobs)

        if job.backend == "systemd":
            if job.is_enabled:
                SystemdBackend.install(job, self.paths, runner_cmd=self.runner_cmd)
            else:
                SystemdBackend.uninstall(job.id, self.paths)
        elif job.backend == "cron":
            SystemdBackend.uninstall(job.id, self.paths)
            CrontabBackend.sync(all_jobs, runner_cmd=self.runner_cmd)

    def delete(self, job: Job, remaining: list[Job]) -> None:
        self._remove_from_backend(job, remaining)
        self.paths.action_script(job.id).unlink(missing_ok=True)
        RunHistory.remove_all(job.id, self.paths)

    def _remove_from_backend(self, job: Job, all_jobs: list[Job]) -> None:
        SystemdBackend.uninstall(job.id, self.paths)
        if job.backend == "cron":
            CrontabBackend.sync(
                [j for j in all_jobs if j.id != job.id], runner_cmd=self.runner_cmd
            )

    def reconcile(self, jobs: list[Job]) -> list[str]:
        failures: list[str] = []
        valid_ids = {j.id for j in jobs}
        for orphan in SystemdBackend.installed_ids(self.paths):
            if orphan not in valid_ids:
                SystemdBackend.uninstall(orphan, self.paths)

        for job in jobs:
            try:
                ActionScript.write(job, self.paths.action_script(job.id))
                if job.backend == "systemd" and job.is_enabled:
                    SystemdBackend.install(job, self.paths, runner_cmd=self.runner_cmd)
                else:
                    SystemdBackend.uninstall(job.id, self.paths)
            except Exception as exc:
                failures.append(f"{job.name}: {exc}")

        try:
            CrontabBackend.sync(jobs, runner_cmd=self.runner_cmd)
        except Exception as exc:
            failures.append(str(exc))
        return failures
