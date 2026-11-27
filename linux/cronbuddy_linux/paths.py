"""XDG-compliant filesystem paths for CronBuddy on Linux."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Paths:
    home: Path
    sandboxed: bool = False
    label_prefix: str = "cronbuddy-job-"

    @classmethod
    def standard(cls) -> "Paths":
        env_home = os.environ.get("CRONBUDDY_HOME")
        if env_home:
            return cls(home=Path(env_home).expanduser(), sandboxed=True)
        return cls(home=Path.home(), sandboxed=False)

    @property
    def default_path(self) -> str:
        local_bin = str(self.home / ".local" / "bin")
        return f"{local_bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    @property
    def config_dir(self) -> Path:
        if not self.sandboxed and os.environ.get("XDG_CONFIG_HOME"):
            return Path(os.environ["XDG_CONFIG_HOME"]).expanduser() / "cronbuddy"
        return self.home / ".config" / "cronbuddy"

    @property
    def data_dir(self) -> Path:
        if not self.sandboxed and os.environ.get("XDG_DATA_HOME"):
            return Path(os.environ["XDG_DATA_HOME"]).expanduser() / "cronbuddy"
        return self.home / ".local" / "share" / "cronbuddy"

    @property
    def state_dir(self) -> Path:
        if not self.sandboxed and os.environ.get("XDG_STATE_HOME"):
            return Path(os.environ["XDG_STATE_HOME"]).expanduser() / "cronbuddy"
        return self.home / ".local" / "state" / "cronbuddy"

    @property
    def jobs_file(self) -> Path:
        return self.config_dir / "jobs.json"

    @property
    def settings_file(self) -> Path:
        return self.config_dir / "settings.json"

    @property
    def actions_dir(self) -> Path:
        return self.data_dir / "actions"

    @property
    def logs_dir(self) -> Path:
        return self.state_dir / "logs"

    @property
    def systemd_user_dir(self) -> Path:
        if not self.sandboxed and os.environ.get("XDG_CONFIG_HOME"):
            return Path(os.environ["XDG_CONFIG_HOME"]).expanduser() / "systemd" / "user"
        return self.home / ".config" / "systemd" / "user"

    @property
    def autostart_file(self) -> Path:
        if not self.sandboxed and os.environ.get("XDG_CONFIG_HOME"):
            return Path(os.environ["XDG_CONFIG_HOME"]).expanduser() / "autostart" / "cronbuddy.desktop"
        return self.home / ".config" / "autostart" / "cronbuddy.desktop"

    def action_script(self, job_id: str) -> Path:
        return self.actions_dir / f"{job_id}.sh"

    def log_dir(self, job_id: str) -> Path:
        return self.logs_dir / job_id

    def runs_file(self, job_id: str) -> Path:
        return self.log_dir(job_id) / "runs.jsonl"

    def running_marker(self, job_id: str) -> Path:
        return self.log_dir(job_id) / ".running"

    def unit_name(self, job_id: str) -> str:
        return f"{self.label_prefix}{job_id}"

    def service_file(self, job_id: str) -> Path:
        return self.systemd_user_dir / f"{self.unit_name(job_id)}.service"

    def timer_file(self, job_id: str) -> Path:
        return self.systemd_user_dir / f"{self.unit_name(job_id)}.timer"
