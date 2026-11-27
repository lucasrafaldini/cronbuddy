"""CLI and headless runner entrypoint for CronBuddy Linux."""

from __future__ import annotations

import argparse
import sys

from . import __version__
from .backends import JobStore
from .paths import Paths
from .runner import ActionScript, ScheduledRun


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="cronbuddy", description="CronBuddy for Linux")
    p.add_argument("--version", action="store_true", help="Print version and exit")
    p.add_argument("--tray", action="store_true", help="Start minimized in the system tray")
    p.add_argument("--run-job", metavar="ID", help="Run a saved job headless and log output")
    p.add_argument(
        "--trigger",
        choices=["schedule", "manual"],
        default="schedule",
        help="Trigger label recorded in runs.jsonl",
    )
    p.add_argument("--list", action="store_true", help="List saved jobs and exit")
    p.add_argument("--reconcile", action="store_true", help="Reinstall systemd/cron backends for all jobs")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.version:
        print(f"CronBuddy Linux {__version__}")
        return 0

    paths = Paths.standard()
    store = JobStore(paths)

    if args.run_job:
        jobs = store.load()
        job = next((j for j in jobs if j.id == args.run_job), None)
        if job is not None and not paths.action_script(job.id).exists():
            ActionScript.write(job, paths.action_script(job.id))
        from .models import Settings

        settings = Settings.load(paths.settings_file)
        return ScheduledRun.run(
            args.run_job,
            paths,
            trigger=args.trigger,
            job=job,
            keep_runs=settings.keep_runs,
        )

    if args.list:
        jobs = store.load()
        for j in jobs:
            state = "enabled" if j.is_enabled else "paused"
            print(f"{j.id}\t{state}\t{j.backend}\t{j.name}\t{j.schedule.summary}")
        return 0

    if args.reconcile:
        jobs = store.load()
        failures = store.reconcile(jobs)
        for f in failures:
            print(f"error: {f}", file=sys.stderr)
        return 1 if failures else 0

    from .ui import run_gui

    return run_gui(start_in_tray=args.tray)


if __name__ == "__main__":
    raise SystemExit(main())
