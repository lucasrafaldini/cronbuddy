import datetime

import pytest

import job_runner
from job_runner import parse_run_args, run_job, unwrap_command, wrap_command


@pytest.fixture
def logs_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(job_runner, "LOGS_DIR", str(tmp_path))
    return tmp_path


def test_wrap_and_unwrap_roundtrip():
    command = "bash ~/scripts/sync.sh --dest '/Volumes/My Disk' && echo \"done\""
    wrapped = wrap_command(command, "Nightly sync", "/Applications/CronBuddy.app")

    assert wrapped.startswith("/usr/bin/open -g -W -n -a /Applications/CronBuddy.app --args --run ")
    assert unwrap_command(wrapped) == (command, True)


def test_wrap_quotes_app_path_with_spaces():
    wrapped = wrap_command("ls", "job", "/Users/me/My Apps/CronBuddy.app")

    assert "-a '/Users/me/My Apps/CronBuddy.app' --args" in wrapped
    assert unwrap_command(wrapped) == ("ls", True)


def test_unwrap_plain_command():
    assert unwrap_command("ls -la") == ("ls -la", False)


def test_parse_run_args():
    argv = ["CronBuddy", "--run", "echo hi", "--name", "Greeting"]

    assert parse_run_args(argv) == ("echo hi", "Greeting")
    assert parse_run_args(["CronBuddy", "--run", "echo hi"]) == ("echo hi", "job")
    assert parse_run_args(["CronBuddy"]) is None


def test_run_job_writes_log_and_returns_exit_code(logs_dir):
    now = datetime.datetime(2026, 10, 31, 2, 0)

    assert run_job("echo hello; exit 3", "My Job!", now=now) == 3

    log = (logs_dir / "cronbuddy_My_Job_2026-10-31.log").read_text()
    assert "=== My Job! — 2026-10-31 02:00:00 ===" in log
    assert "hello" in log
    assert "=== exit 3 ===" in log


def test_run_job_hides_bundle_python_environment(logs_dir, monkeypatch):
    monkeypatch.setenv("PYTHONHOME", "/Applications/CronBuddy.app/Contents/Resources")
    monkeypatch.setenv("RESOURCEPATH", "/Applications/CronBuddy.app/Contents/Resources")
    now = datetime.datetime(2026, 10, 31)

    assert (
        run_job('echo "home=${PYTHONHOME:-clean} res=${RESOURCEPATH:-clean}"', "env", now=now) == 0
    )

    log = (logs_dir / "cronbuddy_env_2026-10-31.log").read_text()
    assert "home=clean res=clean" in log


def test_run_job_without_command(logs_dir):
    assert run_job("", "empty", now=datetime.datetime(2026, 10, 31)) == 2
