import datetime
import os
import re
import shlex
import subprocess

from logger import logger

DEFAULT_APP_PATH = "/Applications/CronBuddy.app"
RUN_FLAG = "--run"
NAME_FLAG = "--name"
LOGS_DIR = os.path.expanduser("~/CronBuddyScripts/logs")
_BUNDLE_ENV = {
    "PYTHONHOME",
    "PYTHONPATH",
    "PYTHONUNBUFFERED",
    "PYTHONDONTWRITEBYTECODE",
    "RESOURCEPATH",
    "ARGVZERO",
    "EXECUTABLEPATH",
}

# cron runs jobs without any macOS privacy permission. Launching them through CronBuddy.app makes
# the app the "responsible process", so a single Full Disk Access grant to CronBuddy covers them.
_WRAPPED = re.compile(r"^/usr/bin/open -g -W -n -a (?P<app>\S+|'[^']*') --args --run (?P<rest>.+)$")


def wrap_command(command: str, name: str, app_path: str = DEFAULT_APP_PATH) -> str:
    """Builds a crontab command that asks CronBuddy.app to run `command`.

    Args:
        command: The shell command to execute.
        name: The job name, used for the log file.
        app_path: Path to the CronBuddy.app bundle.

    Returns:
        The command to store in the crontab.
    """
    return (
        f"/usr/bin/open -g -W -n -a {shlex.quote(app_path)} --args "
        f"{RUN_FLAG} {shlex.quote(command)} {NAME_FLAG} {shlex.quote(name)}"
    )


def unwrap_command(command: str) -> tuple[str, bool]:
    """Extracts the original command from a CronBuddy-wrapped crontab command.

    Args:
        command: The command as stored in the crontab.

    Returns:
        A tuple of (original command, whether it was wrapped).
    """
    match = _WRAPPED.match(command.strip())
    if not match:
        return command, False
    try:
        parts = shlex.split(match.group("rest"))
    except ValueError:
        return command, False
    if not parts:
        return command, False
    return parts[0], True


def parse_run_args(argv: list[str]) -> tuple[str, str] | None:
    """Reads `--run <command> [--name <name>]` from the process arguments.

    Args:
        argv: The process arguments.

    Returns:
        A tuple of (command, name), or None when not in run mode.
    """
    if RUN_FLAG not in argv:
        return None
    index = argv.index(RUN_FLAG)
    command = argv[index + 1] if index + 1 < len(argv) else ""
    name = "job"
    if NAME_FLAG in argv and argv.index(NAME_FLAG) + 1 < len(argv):
        name = argv[argv.index(NAME_FLAG) + 1]
    return command, name


def job_environment() -> dict[str, str]:
    """Returns the environment for a job without the variables py2app sets for the bundled Python.

    Leaking PYTHONHOME/PYTHONPATH into a job breaks any other Python interpreter it starts
    ("No module named 'encodings'").
    """
    return {k: v for k, v in os.environ.items() if k not in _BUNDLE_ENV}


def log_path(name: str, now: datetime.datetime) -> str:
    """Returns the daily log file for a job inside ~/CronBuddyScripts/logs."""
    slug = re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_") or "job"
    return os.path.join(LOGS_DIR, f"cronbuddy_{slug}_{now:%Y-%m-%d}.log")


def run_job(command: str, name: str, now: datetime.datetime | None = None) -> int:
    """Runs a job command, appending its output to the job's daily log.

    Args:
        command: The shell command to execute.
        name: The job name.
        now: The current time (for tests).

    Returns:
        The command's exit code.
    """
    now = now or datetime.datetime.now()
    os.makedirs(LOGS_DIR, exist_ok=True)
    path = log_path(name, now)
    # Explicit UTF-8: inside the .app bundle Python has no locale and would default to ASCII
    with open(path, "a", encoding="utf-8") as log:
        log.write(f"=== {name} — {now:%Y-%m-%d %H:%M:%S} ===\n$ {command}\n")
        log.flush()
        if not command:
            log.write("No command given.\n=== exit 2 ===\n\n")
            return 2
        try:
            code = subprocess.run(
                ["/bin/bash", "-lc", command],
                stdout=log,
                stderr=subprocess.STDOUT,
                env=job_environment(),
            ).returncode
        except OSError as e:
            log.write(f"Failed to start: {e}\n")
            code = 127
        log.write(f"=== exit {code} ===\n\n")
    logger.info(f"Ran job '{name}' through CronBuddy (exit {code}), log at {path}")
    return code
