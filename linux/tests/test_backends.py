import os
import stat
from pathlib import Path

from cronbuddy_linux.backends import CrontabBackend, JobStore, SystemdBackend
from cronbuddy_linux.cli import main as cli_main
from cronbuddy_linux.models import Job, JobAction, Settings
from cronbuddy_linux.paths import Paths
from cronbuddy_linux.runner import ActionScript, RunHistory, ScheduledRun, shell_quote
from cronbuddy_linux.schedule import Schedule, TimeOfDay
from cronbuddy_linux.templates import TEMPLATES


def test_crontab_merge_and_external_entries():
    job = Job(
        id="abc123",
        name="Backup",
        action=JobAction.shell("echo hi"),
        schedule=Schedule.daily([TimeOfDay(21, 0)]),
        backend="cron",
    )
    existing = 'MAILTO=""\n0 5 * * * /usr/local/bin/mine\n1 1 * * * /old/cb --run-job gone # cronbuddy:gone\n\n'
    merged = CrontabBackend.merged(existing, [job], runner_cmd=["/usr/local/bin/cronbuddy"])
    assert merged == (
        'MAILTO=""\n'
        "0 5 * * * /usr/local/bin/mine\n"
        "0 21 * * * /usr/local/bin/cronbuddy --run-job abc123 --trigger schedule # cronbuddy:abc123\n"
    )

    paused = Job(id="p1", name="Paused", action=JobAction.shell("true"), backend="cron", is_enabled=False)
    sys_job = Job(id="s1", name="Sys", action=JobAction.shell("true"), backend="systemd", is_enabled=True)
    assert CrontabBackend.merged("", [paused, sys_job], runner_cmd=["cb"]) == ""

    ext_text = (
        "SHELL=/bin/bash\n"
        "# comment\n"
        "*/5 * * * * /usr/bin/true # My Job\n"
        "@reboot /usr/local/bin/startup\n"
        "0 21 * * * /usr/local/bin/cronbuddy --run-job abc123 # cronbuddy:abc123\n"
        "not a cron line\n"
    )
    entries = CrontabBackend.external_entries(ext_text)
    assert len(entries) == 2
    assert entries[0].schedule == "*/5 * * * *"
    assert entries[0].command == "/usr/bin/true"
    assert entries[0].comment == "My Job"
    assert entries[1].schedule == "@reboot"
    removed = CrontabBackend.removing(entries[0], ext_text)
    assert "/usr/bin/true" not in removed
    assert "@reboot" in removed


def test_action_script_rendering():
    assert shell_quote("it's") == "'it'\"'\"'s'"
    job = Job(
        id="x",
        name="PyJob",
        action=JobAction.script("/tmp/a b.py"),
        environment={"CITY": "São Paulo", "bad-name": "ignored"},
    )
    script = ActionScript.render(job)
    assert script.startswith("#!/bin/bash\n")
    assert "export CITY='São Paulo'" in script
    assert "bad-name" not in script
    assert "exec /usr/bin/env python3 '/tmp/a b.py' \"$@\"" in script


def test_validation_and_all_templates_valid():
    bad = Job(name="", action=JobAction.shell(" "), schedule=Schedule.interval(7), backend="cron")
    assert len(bad.problems) == 3

    good = Job(name="Ok", action=JobAction.shell("true"), schedule=Schedule.interval(7), backend="systemd")
    assert good.problems == []

    bad_env = Job(name="Ok", action=JobAction.shell("true"), environment={"1BAD": "x"})
    assert len(bad_env.problems) == 1

    assert len({t.id for t in TEMPLATES}) == len(TEMPLATES)
    for tpl in TEMPLATES:
        j = tpl.make_job()
        assert j.problems == [], f"{tpl.id} failed systemd validation: {j.problems}"
        j.backend = "cron"
        assert j.problems == [], f"{tpl.id} failed cron validation: {j.problems}"


def test_systemd_unit_generation_and_store_reconcile(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("CRONBUDDY_HOME", str(tmp_path))
    paths = Paths.standard()
    store = JobStore(paths, runner_cmd=["/usr/local/bin/cronbuddy"])

    job_interval = Job(
        id="jint",
        name="Every 7m",
        action=JobAction.shell("echo ok"),
        schedule=Schedule.interval(7),
        backend="systemd",
    )
    job_login = Job(
        id="jlog",
        name="At login",
        action=JobAction.shell("echo boot"),
        schedule=Schedule.at_login(),
        backend="systemd",
    )
    store.save([job_interval, job_login])
    failures = store.reconcile([job_interval, job_login])
    assert failures == []

    assert paths.service_file("jint").exists()
    assert paths.timer_file("jint").exists()
    timer_txt = paths.timer_file("jint").read_text(encoding="utf-8")
    assert "OnUnitActiveSec=420s" in timer_txt
    assert "Persistent=true" in timer_txt

    assert paths.service_file("jlog").exists()
    assert not paths.timer_file("jlog").exists()
    assert "WantedBy=default.target" in paths.service_file("jlog").read_text(encoding="utf-8")

    # Executable bit on action script
    mode = paths.action_script("jint").stat().st_mode
    assert mode & stat.S_IXUSR

    # Delete removes units, script, and logs
    store.delete(job_interval, [job_login])
    assert not paths.service_file("jint").exists()
    assert not paths.timer_file("jint").exists()
    assert not paths.action_script("jint").exists()


def test_run_history_prune_and_cli_end_to_end(tmp_path: Path, monkeypatch, capsys):
    monkeypatch.setenv("CRONBUDDY_HOME", str(tmp_path))
    paths = Paths.standard()
    store = JobStore(paths)
    job = Job(id="run1", name="Echo", action=JobAction.shell("echo hello; echo oops >&2; exit 3"))
    store.save([job])
    ActionScript.write(job, paths.action_script(job.id))

    code = cli_main(["--run-job", "run1", "--trigger", "schedule"])
    assert code == 3

    runs = RunHistory.load("run1", paths)
    assert len(runs) == 1
    assert runs[0].exit_code == 3
    assert runs[0].trigger == "schedule"
    assert RunHistory.log_text(runs[0], paths) == "hello\noops\n"
    assert not paths.running_marker("run1").exists()

    # Add 4 more manual runs and prune to 2
    for i in range(4):
        RunHistory.append("run1", 1000.0 + i, 1001.0 + i, 0, f"out {i}", paths)
    RunHistory.prune("run1", 2, paths)
    assert len(RunHistory.load("run1", paths)) == 2

    # --list works cleanly
    assert cli_main(["--list"]) == 0
    captured = capsys.readouterr().out
    assert "run1\tenabled\tsystemd\tEcho" in captured

    # Settings round-trip
    s = Settings(theme="thoth", keep_runs=25, show_countdown=False, open_at_login=True)
    s.save(paths.settings_file)
    loaded = Settings.load(paths.settings_file)
    assert loaded == s
