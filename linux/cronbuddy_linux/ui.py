"""GTK3 + AyatanaAppIndicator3 desktop GUI for CronBuddy on Linux."""

from __future__ import annotations

import datetime
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from typing import Callable

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402

try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
except Exception:  # pragma: no cover - optional tray daemon
    AppIndicator = None

from . import __version__
from .backends import CrontabBackend, ExternalCronEntry, JobStore, SystemdBackend
from .models import Job, JobAction, Settings
from .paths import Paths
from .runner import ActionScript, RunHistory, RunRecord, ScheduledRun
from .schedule import Schedule, TimeOfDay
from .templates import CATEGORIES, TEMPLATES, JobTemplate
from .themes import THEMES, build_gtk_css, theme_by_id


def _format_duration(seconds: float) -> str:
    if seconds < 1:
        return f"{int(seconds * 1000)}ms"
    if seconds < 60:
        return f"{seconds:.1f}s"
    mins, secs = divmod(int(seconds), 60)
    hours, mins = divmod(mins, 60)
    if hours:
        return f"{hours}h {mins}m"
    return f"{mins}m {secs}s"


def _format_countdown(delta: datetime.timedelta) -> str:
    total = max(0, int(delta.total_seconds()))
    if total < 60:
        return f"{total}s"
    mins, _ = divmod(total, 60)
    hours, mins = divmod(mins, 60)
    days, hours = divmod(hours, 24)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {mins}m"
    return f"{mins}m"


def _icon_path() -> str | None:
    root = Path(__file__).resolve().parents[2]
    for candidate in (
        root / "assets" / "cronbuddy.png",
        root / "assets" / "genfavicon-256.png",
        Path("/usr/local/share/icons/hicolor/256x256/apps/cronbuddy.png"),
        Path.home() / ".local" / "share" / "icons" / "hicolor" / "256x256" / "apps" / "cronbuddy.png",
    ):
        if candidate.exists():
            return str(candidate)
    return None


class CronBuddyController:
    """Shared state and mutations between the tray indicator and main window."""

    def __init__(self, paths: Paths | None = None):
        self.paths = paths or Paths.standard()
        self.store = JobStore(self.paths)
        self.settings = Settings.load(self.paths.settings_file)
        self.jobs: list[Job] = self.store.load()
        self.listeners: list[Callable[[], None]] = []

    def subscribe(self, fn: Callable[[], None]) -> None:
        self.listeners.append(fn)

    def notify_listeners(self) -> None:
        for fn in list(self.listeners):
            try:
                fn()
            except Exception:
                pass

    def reload(self) -> None:
        self.jobs = self.store.load()
        self.settings = Settings.load(self.paths.settings_file)
        self.notify_listeners()

    def save_job(self, job: Job) -> None:
        previous = next((j for j in self.jobs if j.id == job.id), None)
        if previous is None:
            self.jobs.append(job)
        else:
            self.jobs = [job if j.id == job.id else j for j in self.jobs]
        self.store.save(self.jobs)
        self.store.apply(job, self.jobs, previous=previous)
        self.notify_listeners()

    def toggle_job(self, job_id: str) -> None:
        job = next((j for j in self.jobs if j.id == job_id), None)
        if not job:
            return
        job.is_enabled = not job.is_enabled
        self.save_job(job)

    def delete_job(self, job_id: str) -> None:
        job = next((j for j in self.jobs if j.id == job_id), None)
        if not job:
            return
        self.jobs = [j for j in self.jobs if j.id != job_id]
        self.store.save(self.jobs)
        self.store.delete(job, self.jobs)
        self.notify_listeners()

    def reconcile_all(self) -> list[str]:
        failures = self.store.reconcile(self.jobs)
        self.notify_listeners()
        return failures

    def save_settings(self, settings: Settings) -> None:
        self.settings = settings
        settings.save(self.paths.settings_file)
        self._sync_autostart(settings.open_at_login)
        self.notify_listeners()

    def _sync_autostart(self, enabled: bool) -> None:
        if self.paths.sandboxed:
            return
        dest = self.paths.autostart_file
        if not enabled:
            dest.unlink(missing_ok=True)
            return
        dest.parent.mkdir(parents=True, exist_ok=True)
        exe = shutil.which("cronbuddy") or shutil.which("cronbuddy-linux") or "cronbuddy-linux"
        desktop = (
            "[Desktop Entry]\n"
            "Type=Application\n"
            "Name=CronBuddy\n"
            "Comment=Schedule scripts and track logs from the system tray\n"
            f"Exec={exe} --tray\n"
            "Icon=cronbuddy\n"
            "Terminal=false\n"
            "Categories=Utility;System;\n"
            "X-GNOME-Autostart-enabled=true\n"
        )
        dest.write_text(desktop, encoding="utf-8")

    def next_upcoming(self) -> tuple[Job, datetime.datetime] | None:
        now = datetime.datetime.now().astimezone()
        best: tuple[Job, datetime.datetime] | None = None
        for job in self.jobs:
            if not job.is_enabled:
                continue
            runs = RunHistory.load(job.id, self.paths)
            last_dt = runs[0].started_at if runs else None
            nxt = job.schedule.next_dates(now, 1, last_run=last_dt)
            if nxt and (best is None or nxt[0] < best[1]):
                best = (job, nxt[0])
        return best


class JobEditorDialog(Gtk.Dialog):
    """Create/Edit job dialog with live schedule preview and Test Run console."""

    def __init__(
        self,
        parent: Gtk.Window | None,
        controller: CronBuddyController,
        job: Job | None = None,
    ):
        is_new = job is None
        super().__init__(
            title="New Job" if is_new else f"Edit · {job.name}",
            transient_for=parent,
            modal=True,
        )
        self.set_default_size(640, 680)
        self.controller = controller
        self.editing_job = job or Job()
        self.result_job: Job | None = None

        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        self.save_btn = self.add_button(
            "Create Job" if is_new else "Save Changes", Gtk.ResponseType.OK
        )
        self.save_btn.get_style_context().add_class("suggested-action")

        box = self.get_content_area()
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(14)
        box.set_margin_end(14)
        box.set_spacing(10)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_vexpand(True)
        box.pack_start(scrolled, True, True, 0)

        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        scrolled.add(form)

        # Name
        self.name_entry = Gtk.Entry()
        self.name_entry.set_placeholder_text("e.g. Back Up Documents")
        self.name_entry.set_text(self.editing_job.name)
        self.name_entry.connect("changed", lambda *_: self._refresh_validation())
        form.pack_start(self._labeled("Name", self.name_entry), False, False, 0)

        # Action kind + value
        self.action_kind_combo = Gtk.ComboBoxText()
        self.action_kind_combo.append("shell", "Shell Command")
        self.action_kind_combo.append("script", "Script File")
        self.action_kind_combo.set_active_id(self.editing_job.action.kind)
        self.action_kind_combo.connect("changed", lambda *_: self._on_action_kind_changed())
        form.pack_start(self._labeled("Action Type", self.action_kind_combo), False, False, 0)

        self.shell_view = Gtk.TextView()
        self.shell_view.set_monospace(True)
        self.shell_buf = self.shell_view.get_buffer()
        if self.editing_job.action.kind == "shell":
            self.shell_buf.set_text(self.editing_job.action.value)
        self.shell_buf.connect("changed", lambda *_: self._refresh_validation())
        shell_scroll = Gtk.ScrolledWindow()
        shell_scroll.set_min_content_height(90)
        shell_scroll.add(self.shell_view)
        self.shell_box = self._labeled("Command (runs in bash)", shell_scroll)
        form.pack_start(self.shell_box, False, False, 0)

        script_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.script_entry = Gtk.Entry()
        self.script_entry.set_placeholder_text("/path/to/script.sh or .py")
        if self.editing_job.action.kind == "script":
            self.script_entry.set_text(self.editing_job.action.value)
        self.script_entry.connect("changed", lambda *_: self._refresh_validation())
        browse_btn = Gtk.Button(label="Browse…")
        browse_btn.connect("clicked", self._on_browse_script)
        script_row.pack_start(self.script_entry, True, True, 0)
        script_row.pack_start(browse_btn, False, False, 0)
        self.script_box = self._labeled("Script File", script_row)
        form.pack_start(self.script_box, False, False, 0)

        # Schedule kind
        self.sched_combo = Gtk.ComboBoxText()
        for sid, title in [
            ("interval", "Every N minutes"),
            ("hourly", "Hourly"),
            ("daily", "Daily"),
            ("weekly", "Weekly"),
            ("monthly", "Monthly"),
            ("atLogin", "At login"),
            ("cron", "Custom (cron)"),
        ]:
            self.sched_combo.append(sid, title)
        self.sched_combo.set_active_id(self.editing_job.schedule.kind)
        self.sched_combo.connect("changed", lambda *_: self._on_sched_kind_changed())
        form.pack_start(self._labeled("Schedule", self.sched_combo), False, False, 0)

        # Schedule parameter widgets
        self.sched_params_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        form.pack_start(self.sched_params_box, False, False, 0)

        # Interval spin
        self.interval_spin = Gtk.SpinButton.new_with_range(1, 10080, 1)
        self.interval_spin.set_value(self.editing_job.schedule.minutes or 15)
        self.interval_spin.connect("value-changed", lambda *_: self._refresh_validation())
        self.interval_row = self._labeled("Interval (minutes)", self.interval_spin)
        self.sched_params_box.pack_start(self.interval_row, False, False, 0)

        # Hourly minute spin
        self.hourly_spin = Gtk.SpinButton.new_with_range(0, 59, 1)
        self.hourly_spin.set_value(self.editing_job.schedule.minute or 0)
        self.hourly_spin.connect("value-changed", lambda *_: self._refresh_validation())
        self.hourly_row = self._labeled("At minute (:MM)", self.hourly_spin)
        self.sched_params_box.pack_start(self.hourly_row, False, False, 0)

        # Weekdays checkboxes
        wd_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.weekday_checks: dict[int, Gtk.CheckButton] = {}
        active_wds = set(self.editing_job.schedule.weekdays or (1, 2, 3, 4, 5))
        for wd, lbl in [(1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat"), (0, "Sun")]:
            cb = Gtk.CheckButton(label=lbl)
            cb.set_active(wd in active_wds)
            cb.connect("toggled", lambda *_: self._refresh_validation())
            self.weekday_checks[wd] = cb
            wd_box.pack_start(cb, False, False, 0)
        self.weekdays_row = self._labeled("Weekdays", wd_box)
        self.sched_params_box.pack_start(self.weekdays_row, False, False, 0)

        # Days of month entry
        self.dom_entry = Gtk.Entry()
        self.dom_entry.set_placeholder_text("1, 15")
        days_init = self.editing_job.schedule.days or (1,)
        self.dom_entry.set_text(", ".join(str(d) for d in days_init))
        self.dom_entry.connect("changed", lambda *_: self._refresh_validation())
        self.dom_row = self._labeled("Days of month (1-31, comma-separated)", self.dom_entry)
        self.sched_params_box.pack_start(self.dom_row, False, False, 0)

        # Times entry (HH:MM, comma-separated)
        self.times_entry = Gtk.Entry()
        self.times_entry.set_placeholder_text("09:00, 18:00")
        if self.editing_job.schedule.times:
            self.times_entry.set_text(", ".join(t.formatted for t in self.editing_job.schedule.times))
        elif self.editing_job.schedule.time:
            self.times_entry.set_text(self.editing_job.schedule.time.formatted)
        else:
            self.times_entry.set_text("09:00")
        self.times_entry.connect("changed", lambda *_: self._refresh_validation())
        self.times_row = self._labeled("Time(s) (HH:MM, comma-separated)", self.times_entry)
        self.sched_params_box.pack_start(self.times_row, False, False, 0)

        # Raw cron expression
        self.cron_entry = Gtk.Entry()
        self.cron_entry.set_placeholder_text("0 9 * * 1-5")
        self.cron_entry.set_text(self.editing_job.schedule.expression or "0 9 * * *")
        self.cron_entry.connect("changed", lambda *_: self._refresh_validation())
        self.cron_row = self._labeled("Cron expression (min hour dom month dow)", self.cron_entry)
        self.sched_params_box.pack_start(self.cron_row, False, False, 0)

        # Next runs preview label
        self.preview_label = Gtk.Label(xalign=0)
        self.preview_label.set_line_wrap(True)
        self.preview_label.get_style_context().add_class("cb-subtitle")
        form.pack_start(self.preview_label, False, False, 0)

        # Backend
        self.backend_combo = Gtk.ComboBoxText()
        self.backend_combo.append("systemd", "systemd user timer (recommended — catches missed runs)")
        self.backend_combo.append("cron", "cron (classic crontab)")
        self.backend_combo.set_active_id(self.editing_job.backend)
        self.backend_combo.connect("changed", lambda *_: self._refresh_validation())
        form.pack_start(self._labeled("Runs with", self.backend_combo), False, False, 0)

        # Environment variables
        self.env_view = Gtk.TextView()
        self.env_view.set_monospace(True)
        self.env_buf = self.env_view.get_buffer()
        self.env_buf.set_text(
            "\n".join(f"{k}={v}" for k, v in sorted(self.editing_job.environment.items()))
        )
        self.env_buf.connect("changed", lambda *_: self._refresh_validation())
        env_scroll = Gtk.ScrolledWindow()
        env_scroll.set_min_content_height(60)
        env_scroll.add(self.env_view)
        form.pack_start(self._labeled("Environment (KEY=VALUE per line)", env_scroll), False, False, 0)

        # Notifications
        notif_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self.notify_fail_cb = Gtk.CheckButton(label="Notify on failure")
        self.notify_fail_cb.set_active(self.editing_job.notify_on_failure)
        self.notify_ok_cb = Gtk.CheckButton(label="Notify on success")
        self.notify_ok_cb.set_active(self.editing_job.notify_on_success)
        notif_row.pack_start(self.notify_fail_cb, False, False, 0)
        notif_row.pack_start(self.notify_ok_cb, False, False, 0)
        form.pack_start(notif_row, False, False, 0)

        # Validation + Test Run console
        self.problem_label = Gtk.Label(xalign=0)
        self.problem_label.set_line_wrap(True)
        self.problem_label.get_style_context().add_class("cb-dot-fail")
        form.pack_start(self.problem_label, False, False, 0)

        test_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.test_btn = Gtk.Button(label="Test Run")
        self.test_btn.connect("clicked", self._on_test_run)
        self.test_status = Gtk.Label(xalign=0)
        test_row.pack_start(self.test_btn, False, False, 0)
        test_row.pack_start(self.test_status, True, True, 0)
        form.pack_start(test_row, False, False, 0)

        self.test_out_view = Gtk.TextView()
        self.test_out_view.set_editable(False)
        self.test_out_view.set_monospace(True)
        self.test_out_buf = self.test_out_view.get_buffer()
        out_scroll = Gtk.ScrolledWindow()
        out_scroll.set_min_content_height(100)
        out_scroll.add(self.test_out_view)
        form.pack_start(out_scroll, False, False, 0)

        self.show_all()
        self._on_action_kind_changed()
        self._on_sched_kind_changed()

    def _labeled(self, label: str, widget: Gtk.Widget) -> Gtk.Box:
        b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.get_style_context().add_class("cb-subtitle")
        b.pack_start(lbl, False, False, 0)
        b.pack_start(widget, False, False, 0)
        return b

    def _on_browse_script(self, *_args) -> None:
        dlg = Gtk.FileChooserDialog(
            title="Choose Script File",
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dlg.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK)
        if dlg.run() == Gtk.ResponseType.OK:
            self.script_entry.set_text(dlg.get_filename() or "")
        dlg.destroy()

    def _on_action_kind_changed(self) -> None:
        kind = self.action_kind_combo.get_active_id() or "shell"
        self.shell_box.set_visible(kind == "shell")
        self.script_box.set_visible(kind == "script")
        self._refresh_validation()

    def _on_sched_kind_changed(self) -> None:
        kind = self.sched_combo.get_active_id() or "daily"
        self.interval_row.set_visible(kind == "interval")
        self.hourly_row.set_visible(kind == "hourly")
        self.weekdays_row.set_visible(kind == "weekly")
        self.dom_row.set_visible(kind == "monthly")
        self.times_row.set_visible(kind in ("daily", "weekly", "monthly"))
        self.cron_row.set_visible(kind == "cron")
        self._refresh_validation()

    def _parse_times(self) -> list[TimeOfDay] | None:
        raw = self.times_entry.get_text().strip()
        if not raw:
            return []
        out: list[TimeOfDay] = []
        for token in raw.split(","):
            part = token.strip()
            if not part or ":" not in part:
                return None
            h_s, m_s = part.split(":", 1)
            try:
                h, m = int(h_s), int(m_s)
            except ValueError:
                return None
            if not (0 <= h <= 23 and 0 <= m <= 59):
                return None
            out.append(TimeOfDay(h, m))
        return out

    def _build_candidate(self) -> tuple[Job, str | None]:
        kind = self.action_kind_combo.get_active_id() or "shell"
        if kind == "shell":
            s, e = self.shell_buf.get_bounds()
            action = JobAction.shell(self.shell_buf.get_text(s, e, False))
        else:
            action = JobAction.script(self.script_entry.get_text().strip())

        skind = self.sched_combo.get_active_id() or "daily"
        parse_err: str | None = None
        if skind == "interval":
            sched = Schedule.interval(int(self.interval_spin.get_value()))
        elif skind == "hourly":
            sched = Schedule.hourly(int(self.hourly_spin.get_value()))
        elif skind == "daily":
            times = self._parse_times()
            if times is None:
                parse_err = "Enter times as HH:MM (for example 09:00, 18:30)."
                times = []
            sched = Schedule.daily(times)
        elif skind == "weekly":
            wds = [wd for wd, cb in self.weekday_checks.items() if cb.get_active()]
            times = self._parse_times()
            if times is None:
                parse_err = "Enter times as HH:MM (for example 09:00, 18:30)."
                times = []
            sched = Schedule.weekly(wds, times)
        elif skind == "monthly":
            days: list[int] = []
            for tok in self.dom_entry.get_text().split(","):
                t = tok.strip()
                if not t:
                    continue
                try:
                    d = int(t)
                    if 1 <= d <= 31:
                        days.append(d)
                    else:
                        parse_err = "Days of month must be between 1 and 31."
                except ValueError:
                    parse_err = "Days of month must be numbers (e.g. 1, 15)."
            times = self._parse_times()
            if times is None or not times:
                parse_err = parse_err or "Enter a time as HH:MM."
                t_val = TimeOfDay(9, 0)
            else:
                t_val = times[0]
            sched = Schedule.monthly(days, t_val)
        elif skind == "atLogin":
            sched = Schedule.at_login()
        else:
            sched = Schedule.cron(self.cron_entry.get_text().strip())

        es, ee = self.env_buf.get_bounds()
        env: dict[str, str] = {}
        for line in self.env_buf.get_text(es, ee, False).splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                parse_err = parse_err or f"Environment line “{line}” must be KEY=VALUE."
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()

        job = Job(
            id=self.editing_job.id,
            name=self.name_entry.get_text().strip(),
            action=action,
            schedule=sched,
            backend=self.backend_combo.get_active_id() or "systemd",
            is_enabled=self.editing_job.is_enabled,
            notify_on_failure=self.notify_fail_cb.get_active(),
            notify_on_success=self.notify_ok_cb.get_active(),
            environment=env,
            created_at=self.editing_job.created_at,
        )
        return job, parse_err

    def _refresh_validation(self) -> None:
        job, parse_err = self._build_candidate()
        problems = ([parse_err] if parse_err else []) + job.problems
        if problems:
            self.problem_label.set_text(" · ".join(problems))
            self.problem_label.set_visible(True)
            self.save_btn.set_sensitive(False)
        else:
            warnings = job.warnings
            if warnings:
                self.problem_label.set_text("Note: " + " · ".join(warnings))
                self.problem_label.set_visible(True)
            else:
                self.problem_label.set_visible(False)
            self.save_btn.set_sensitive(True)

        now = datetime.datetime.now().astimezone()
        nxt = job.schedule.next_dates(now, 4)
        if nxt:
            formatted = ", ".join(d.strftime("%a %d %b %H:%M") for d in nxt)
            self.preview_label.set_text(f"{job.schedule.summary} — Next: {formatted}")
        else:
            self.preview_label.set_text(job.schedule.summary)

        self.test_btn.set_sensitive(not job.action.is_empty)
        self.result_job = job

    def _on_test_run(self, *_args) -> None:
        job, _ = self._build_candidate()
        if job.action.is_empty:
            return
        self.test_btn.set_sensitive(False)
        self.test_status.set_text("Running…")
        self.test_out_buf.set_text("")

        def worker() -> None:
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as tf:
                tf.write(ActionScript.render(job))
                script_path = Path(tf.name)
            os.chmod(script_path, 0o755)
            try:
                def on_chunk(chunk: str) -> None:
                    GLib.idle_add(self._append_test_output, chunk)

                code, _out, start, end = ScheduledRun.run_streaming(
                    script_path, self.controller.paths, on_chunk=on_chunk
                )
                GLib.idle_add(self._finish_test_run, code, end - start)
            finally:
                script_path.unlink(missing_ok=True)

        threading.Thread(target=worker, daemon=True).start()

    def _append_test_output(self, chunk: str) -> bool:
        end_iter = self.test_out_buf.get_end_iter()
        self.test_out_buf.insert(end_iter, chunk)
        return False

    def _finish_test_run(self, code: int, dur: float) -> bool:
        self.test_btn.set_sensitive(True)
        status = "Succeeded" if code == 0 else f"Failed (exit {code})"
        self.test_status.set_text(f"{status} · {_format_duration(dur)}")
        return False


class CronBuddyWindow(Gtk.ApplicationWindow):
    """Main desktop window with sidebar, views, live run console, and themes."""

    def __init__(self, app: Gtk.Application, controller: CronBuddyController):
        super().__init__(application=app, title="CronBuddy")
        self.set_default_size(1020, 680)
        self.controller = controller
        self.selected_job_id: str | None = None
        self.css_provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            self.css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        icon = _icon_path()
        if icon:
            try:
                self.set_icon_from_file(icon)
            except Exception:
                pass

        self.connect("delete-event", self._on_delete_event)

        # HeaderBar
        hb = Gtk.HeaderBar()
        hb.set_show_close_button(True)
        hb.set_title("CronBuddy")
        hb.set_subtitle(f"Linux v{__version__}")
        self.set_titlebar(hb)

        new_btn = Gtk.Button(label="+ New Job")
        new_btn.get_style_context().add_class("suggested-action")
        new_btn.connect("clicked", lambda *_: self.open_new_job_dialog())
        hb.pack_end(new_btn)

        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.connect("clicked", lambda *_: self.controller.reload())
        hb.pack_end(refresh_btn)

        # Root split
        root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        root.get_style_context().add_class("cb-root")
        self.add(root)

        # Sidebar
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        sidebar.set_size_request(250, -1)
        sidebar.get_style_context().add_class("cb-sidebar")
        sidebar.set_margin_top(10)
        sidebar.set_margin_bottom(10)
        sidebar.set_margin_start(8)
        sidebar.set_margin_end(8)
        root.pack_start(sidebar, False, False, 0)

        self.nav_list = Gtk.ListBox()
        self.nav_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.nav_list.connect("row-selected", self._on_nav_selected)
        sidebar.pack_start(self.nav_list, False, False, 0)

        jobs_hdr = Gtk.Label(label="JOBS", xalign=0)
        jobs_hdr.set_margin_top(10)
        jobs_hdr.set_margin_start(6)
        jobs_hdr.get_style_context().add_class("cb-subtitle")
        sidebar.pack_start(jobs_hdr, False, False, 0)

        jobs_scroll = Gtk.ScrolledWindow()
        jobs_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        jobs_scroll.set_vexpand(True)
        self.jobs_list = Gtk.ListBox()
        self.jobs_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.jobs_list.connect("row-selected", self._on_job_selected)
        jobs_scroll.add(self.jobs_list)
        sidebar.pack_start(jobs_scroll, True, True, 0)

        # Stack content
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        root.pack_start(self.stack, True, True, 0)

        self._nav_items = [
            ("overview", "Overview"),
            ("activity", "Activity"),
            ("templates", "Templates"),
            ("import", "Import"),
            ("settings", "Settings"),
        ]
        for key, label in self._nav_items:
            row = Gtk.ListBoxRow()
            row._nav_key = key  # type: ignore[attr-defined]
            lbl = Gtk.Label(label=label, xalign=0)
            lbl.set_margin_top(7)
            lbl.set_margin_bottom(7)
            lbl.set_margin_start(8)
            row.add(lbl)
            self.nav_list.add(row)

        self.overview_page = self._make_scroll_container()
        self.detail_page = self._make_scroll_container()
        self.activity_page = self._make_scroll_container()
        self.templates_page = self._make_scroll_container()
        self.import_page = self._make_scroll_container()
        self.settings_page = self._make_scroll_container()

        self.stack.add_named(self.overview_page[0], "overview")
        self.stack.add_named(self.detail_page[0], "detail")
        self.stack.add_named(self.activity_page[0], "activity")
        self.stack.add_named(self.templates_page[0], "templates")
        self.stack.add_named(self.import_page[0], "import")
        self.stack.add_named(self.settings_page[0], "settings")

        self.controller.subscribe(self.refresh_ui)
        self.apply_theme(self.controller.settings.theme)
        self.nav_list.select_row(self.nav_list.get_row_at_index(0))
        self.refresh_ui()
        GLib.timeout_add_seconds(5, self._poll_tick)

    def _on_delete_event(self, *_args) -> bool:
        if AppIndicator is not None:
            self.hide()
            return True
        return False

    def _poll_tick(self) -> bool:
        if self.get_visible():
            self.refresh_ui()
        return True

    def _make_scroll_container(self) -> tuple[Gtk.ScrolledWindow, Gtk.Box]:
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_margin_top(18)
        box.set_margin_bottom(18)
        box.set_margin_start(22)
        box.set_margin_end(22)
        sw.add(box)
        return sw, box

    def apply_theme(self, theme_id: str) -> None:
        theme = theme_by_id(theme_id)
        css = build_gtk_css(theme)
        self.css_provider.load_from_data(css.encode("utf-8"))
        settings = Gtk.Settings.get_default()
        if settings and not theme.is_native:
            settings.set_property("gtk-application-prefer-dark-theme", theme.is_dark)

    def show_section(self, key: str) -> None:
        self.selected_job_id = None
        self.jobs_list.unselect_all()
        for idx, (k, _) in enumerate(self._nav_items):
            if k == key:
                self.nav_list.select_row(self.nav_list.get_row_at_index(idx))
                break
        self.stack.set_visible_child_name(key)
        self.refresh_ui()
        self.present()

    def _on_nav_selected(self, _lb: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        if row is None:
            return
        self.selected_job_id = None
        self.jobs_list.unselect_all()
        key = getattr(row, "_nav_key", "overview")
        self.stack.set_visible_child_name(key)
        self.refresh_ui()

    def _on_job_selected(self, _lb: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        if row is None:
            return
        self.nav_list.unselect_all()
        self.selected_job_id = getattr(row, "_job_id", None)
        self.stack.set_visible_child_name("detail")
        self._render_detail()

    def refresh_ui(self) -> None:
        self._populate_sidebar_jobs()
        current = self.stack.get_visible_child_name()
        if current == "overview":
            self._render_overview()
        elif current == "detail":
            self._render_detail()
        elif current == "activity":
            self._render_activity()
        elif current == "templates":
            self._render_templates()
        elif current == "import":
            self._render_import()
        elif current == "settings":
            self._render_settings()

    def _populate_sidebar_jobs(self) -> None:
        for child in self.jobs_list.get_children():
            self.jobs_list.remove(child)
        for job in sorted(self.controller.jobs, key=lambda j: j.name.lower()):
            row = Gtk.ListBoxRow()
            row._job_id = job.id  # type: ignore[attr-defined]
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            box.set_margin_top(6)
            box.set_margin_bottom(6)
            box.set_margin_start(8)
            box.set_margin_end(8)

            dot = Gtk.Label(label="●")
            running = RunHistory.running_pid(job.id, self.controller.paths)
            runs = RunHistory.load(job.id, self.controller.paths)
            if not job.is_enabled:
                dot.get_style_context().add_class("cb-dot-muted")
            elif running is not None:
                dot.get_style_context().add_class("cb-dot-warn")
            elif runs and not runs[0].succeeded:
                dot.get_style_context().add_class("cb-dot-fail")
            else:
                dot.get_style_context().add_class("cb-dot-ok")

            lbl = Gtk.Label(label=job.name, xalign=0)
            lbl.set_ellipsize(Pango.EllipsizeMode.END)
            box.pack_start(dot, False, False, 0)
            box.pack_start(lbl, True, True, 0)
            row.add(box)
            self.jobs_list.add(row)
        self.jobs_list.show_all()

    def _clear(self, box: Gtk.Box) -> None:
        for ch in box.get_children():
            box.remove(ch)

    def _render_overview(self) -> None:
        box = self.overview_page[1]
        self._clear(box)

        title = Gtk.Label(label="Overview", xalign=0)
        title.get_style_context().add_class("cb-title")
        box.pack_start(title, False, False, 0)

        jobs = self.controller.jobs
        enabled = [j for j in jobs if j.is_enabled]
        all_runs = [r for j in jobs for r in RunHistory.load(j.id, self.controller.paths)]
        failures = [r for r in all_runs if not r.succeeded]
        upcoming = self.controller.next_upcoming()

        cards = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        cards.set_homogeneous(True)
        cards.pack_start(self._stat_card("Active Jobs", f"{len(enabled)} / {len(jobs)}"), True, True, 0)
        if upcoming:
            nxt_txt = f"{upcoming[0].name}\nin {_format_countdown(upcoming[1] - datetime.datetime.now().astimezone())}"
        else:
            nxt_txt = "No scheduled runs"
        cards.pack_start(self._stat_card("Up Next", nxt_txt), True, True, 0)
        cards.pack_start(
            self._stat_card("Recorded Runs", f"{len(all_runs)} total · {len(failures)} failed"),
            True,
            True,
            0,
        )
        box.pack_start(cards, False, False, 0)

        if not jobs:
            empty = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            empty.get_style_context().add_class("cb-card")
            empty.pack_start(
                Gtk.Label(label="No jobs scheduled yet. Create one or pick a ready-made template.", xalign=0),
                False,
                False,
                0,
            )
            btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            b1 = Gtk.Button(label="+ New Job")
            b1.get_style_context().add_class("suggested-action")
            b1.connect("clicked", lambda *_: self.open_new_job_dialog())
            b2 = Gtk.Button(label="Browse Templates")
            b2.connect("clicked", lambda *_: self.show_section("templates"))
            btns.pack_start(b1, False, False, 0)
            btns.pack_start(b2, False, False, 0)
            empty.pack_start(btns, False, False, 0)
            box.pack_start(empty, False, False, 0)
        else:
            now = datetime.datetime.now().astimezone()
            for job in jobs:
                card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                card.get_style_context().add_class("cb-card")
                info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
                h = Gtk.Label(label=f"{job.name}  [{job.backend}]", xalign=0)
                h.get_style_context().add_class("cb-title")
                runs = RunHistory.load(job.id, self.controller.paths)
                last_dt = runs[0].started_at if runs else None
                nxt = job.schedule.next_dates(now, 1, last_run=last_dt)
                nxt_str = nxt[0].strftime("%a %H:%M") if nxt and job.is_enabled else ("Paused" if not job.is_enabled else "At login")
                sub = Gtk.Label(label=f"{job.schedule.summary} · Next: {nxt_str}", xalign=0)
                sub.get_style_context().add_class("cb-subtitle")
                info.pack_start(h, False, False, 0)
                info.pack_start(sub, False, False, 0)
                card.pack_start(info, True, True, 0)

                run_btn = Gtk.Button(label="Run Now")
                run_btn.connect("clicked", lambda _w, jid=job.id: self._run_job_from_ui(jid))
                open_btn = Gtk.Button(label="Details")
                open_btn.connect("clicked", lambda _w, jid=job.id: self._select_job(jid))
                card.pack_start(run_btn, False, False, 0)
                card.pack_start(open_btn, False, False, 0)
                box.pack_start(card, False, False, 0)

        box.show_all()

    def _stat_card(self, label: str, value: str) -> Gtk.Box:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        card.get_style_context().add_class("cb-card")
        l1 = Gtk.Label(label=label, xalign=0)
        l1.get_style_context().add_class("cb-subtitle")
        l2 = Gtk.Label(label=value, xalign=0)
        l2.get_style_context().add_class("cb-title")
        l2.set_line_wrap(True)
        card.pack_start(l1, False, False, 0)
        card.pack_start(l2, False, False, 0)
        return card

    def _select_job(self, job_id: str) -> None:
        self.selected_job_id = job_id
        for row in self.jobs_list.get_children():
            if getattr(row, "_job_id", None) == job_id:
                self.jobs_list.select_row(row)
                break
        self.stack.set_visible_child_name("detail")
        self._render_detail()

    def _render_detail(self) -> None:
        box = self.detail_page[1]
        self._clear(box)
        job = next((j for j in self.controller.jobs if j.id == self.selected_job_id), None)
        if job is None:
            self.stack.set_visible_child_name("overview")
            self._render_overview()
            return

        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        title = Gtk.Label(label=job.name, xalign=0)
        title.get_style_context().add_class("cb-title")
        hdr.pack_start(title, True, True, 0)

        run_btn = Gtk.Button(label="Run Now")
        run_btn.get_style_context().add_class("suggested-action")
        run_btn.connect("clicked", lambda *_: self._run_job_from_ui(job.id))
        pause_btn = Gtk.Button(label="Pause" if job.is_enabled else "Resume")
        pause_btn.connect("clicked", lambda *_: self.controller.toggle_job(job.id))
        edit_btn = Gtk.Button(label="Edit")
        edit_btn.connect("clicked", lambda *_: self.open_edit_job_dialog(job))
        del_btn = Gtk.Button(label="Delete")
        del_btn.connect("clicked", lambda *_: self._confirm_delete(job))
        for b in (run_btn, pause_btn, edit_btn, del_btn):
            hdr.pack_start(b, False, False, 0)
        box.pack_start(hdr, False, False, 0)

        # Summary card
        meta = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        meta.get_style_context().add_class("cb-card")
        meta.pack_start(Gtk.Label(label=f"Action: {job.action.subtitle} ({job.action.kind})", xalign=0), False, False, 0)
        meta.pack_start(Gtk.Label(label=f"Schedule: {job.schedule.summary} · Backend: {job.backend}", xalign=0), False, False, 0)
        now = datetime.datetime.now().astimezone()
        runs = RunHistory.load(job.id, self.controller.paths)
        last_dt = runs[0].started_at if runs else None
        nxt = job.schedule.next_dates(now, 4, last_run=last_dt)
        if nxt and job.is_enabled:
            meta.pack_start(
                Gtk.Label(label="Next runs: " + ", ".join(d.strftime("%a %d %b %H:%M") for d in nxt), xalign=0),
                False,
                False,
                0,
            )
        if runs:
            ok_pct = int(round(100 * sum(1 for r in runs if r.succeeded) / len(runs)))
            meta.pack_start(Gtk.Label(label=f"Success rate: {ok_pct}% ({len(runs)} runs)", xalign=0), False, False, 0)

        script_btn = Gtk.Button(label=f"Action script: {self.controller.paths.action_script(job.id)}")
        script_btn.connect("clicked", lambda *_: self._open_path(self.controller.paths.action_script(job.id).parent))
        meta.pack_start(script_btn, False, False, 0)
        box.pack_start(meta, False, False, 0)

        # History + log viewer
        hist_hdr = Gtk.Label(label="Run History", xalign=0)
        hist_hdr.get_style_context().add_class("cb-title")
        box.pack_start(hist_hdr, False, False, 0)

        log_view = Gtk.TextView()
        log_view.set_editable(False)
        log_view.set_monospace(True)
        log_buf = log_view.get_buffer()

        if not runs:
            log_buf.set_text("No runs recorded yet. Click Run Now to test this job.")
        else:
            log_buf.set_text(RunHistory.log_text(runs[0], self.controller.paths) or "(no output)")
            runs_box = Gtk.ListBox()
            for r in runs[:15]:
                row = Gtk.ListBoxRow()
                row._run_record = r  # type: ignore[attr-defined]
                rline = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                rline.set_margin_top(4)
                rline.set_margin_bottom(4)
                rline.set_margin_start(6)
                rline.set_margin_end(6)
                dot = Gtk.Label(label="●" if r.succeeded else "✕")
                dot.get_style_context().add_class("cb-dot-ok" if r.succeeded else "cb-dot-fail")
                rline.pack_start(dot, False, False, 0)
                rline.pack_start(
                    Gtk.Label(
                        label=f"{r.started_at.strftime('%Y-%m-%d %H:%M:%S')} · {r.trigger} · exit {r.exit_code} · {_format_duration(r.duration)}",
                        xalign=0,
                    ),
                    True,
                    True,
                    0,
                )
                row.add(rline)
                runs_box.add(row)
            runs_box.connect(
                "row-selected",
                lambda _lb, r_row: log_buf.set_text(
                    RunHistory.log_text(r_row._run_record, self.controller.paths) or "(no output)"
                )
                if r_row
                else None,
            )
            rscroll = Gtk.ScrolledWindow()
            rscroll.set_min_content_height(150)
            rscroll.add(runs_box)
            box.pack_start(rscroll, False, False, 0)

        lscroll = Gtk.ScrolledWindow()
        lscroll.set_min_content_height(180)
        lscroll.add(log_view)
        box.pack_start(lscroll, True, True, 0)
        box.show_all()

    def _render_activity(self) -> None:
        box = self.activity_page[1]
        self._clear(box)
        title = Gtk.Label(label="Activity", xalign=0)
        title.get_style_context().add_class("cb-title")
        box.pack_start(title, False, False, 0)

        job_map = {j.id: j for j in self.controller.jobs}
        all_runs = [r for j in self.controller.jobs for r in RunHistory.load(j.id, self.controller.paths)]
        all_runs.sort(key=lambda r: r.start, reverse=True)

        if not all_runs:
            box.pack_start(Gtk.Label(label="No runs recorded yet.", xalign=0), False, False, 0)
            box.show_all()
            return

        log_view = Gtk.TextView()
        log_view.set_editable(False)
        log_view.set_monospace(True)
        log_buf = log_view.get_buffer()
        log_buf.set_text(RunHistory.log_text(all_runs[0], self.controller.paths) or "(no output)")

        lb = Gtk.ListBox()
        for r in all_runs[:50]:
            row = Gtk.ListBoxRow()
            row._run_record = r  # type: ignore[attr-defined]
            line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            line.set_margin_top(4)
            line.set_margin_bottom(4)
            line.set_margin_start(6)
            line.set_margin_end(6)
            dot = Gtk.Label(label="●" if r.succeeded else "✕")
            dot.get_style_context().add_class("cb-dot-ok" if r.succeeded else "cb-dot-fail")
            jname = job_map[r.job_id].name if r.job_id in job_map else r.job_id
            line.pack_start(dot, False, False, 0)
            line.pack_start(
                Gtk.Label(
                    label=f"{jname} · {r.started_at.strftime('%Y-%m-%d %H:%M:%S')} · exit {r.exit_code} · {_format_duration(r.duration)}",
                    xalign=0,
                ),
                True,
                True,
                0,
            )
            row.add(line)
            lb.add(row)
        lb.connect(
            "row-selected",
            lambda _lb, r_row: log_buf.set_text(
                RunHistory.log_text(r_row._run_record, self.controller.paths) or "(no output)"
            )
            if r_row
            else None,
        )
        sw = Gtk.ScrolledWindow()
        sw.set_min_content_height(240)
        sw.add(lb)
        box.pack_start(sw, False, False, 0)

        lsw = Gtk.ScrolledWindow()
        lsw.set_min_content_height(200)
        lsw.add(log_view)
        box.pack_start(lsw, True, True, 0)
        box.show_all()

    def _render_templates(self) -> None:
        box = self.templates_page[1]
        self._clear(box)
        title = Gtk.Label(label="Templates", xalign=0)
        title.get_style_context().add_class("cb-title")
        box.pack_start(title, False, False, 0)

        for cat in CATEGORIES:
            items = [t for t in TEMPLATES if t.category == cat]
            if not items:
                continue
            cat_lbl = Gtk.Label(label=cat, xalign=0)
            cat_lbl.get_style_context().add_class("cb-subtitle")
            box.pack_start(cat_lbl, False, False, 0)
            for tpl in items:
                card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
                card.get_style_context().add_class("cb-card")
                col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                n_lbl = Gtk.Label(label=tpl.name, xalign=0)
                n_lbl.get_style_context().add_class("cb-title")
                s_lbl = Gtk.Label(label=f"{tpl.summary} ({tpl.schedule.summary})", xalign=0)
                s_lbl.set_line_wrap(True)
                s_lbl.get_style_context().add_class("cb-subtitle")
                col.pack_start(n_lbl, False, False, 0)
                col.pack_start(s_lbl, False, False, 0)
                card.pack_start(col, True, True, 0)
                btn = Gtk.Button(label="Use Template")
                btn.connect("clicked", lambda _w, t=tpl: self._use_template(t))
                card.pack_start(btn, False, False, 0)
                box.pack_start(card, False, False, 0)
        box.show_all()

    def _use_template(self, tpl: JobTemplate) -> None:
        dlg = JobEditorDialog(self, self.controller, job=tpl.make_job())
        if dlg.run() == Gtk.ResponseType.OK and dlg.result_job:
            self.controller.save_job(dlg.result_job)
            self._select_job(dlg.result_job.id)
        dlg.destroy()

    def _render_import(self) -> None:
        box = self.import_page[1]
        self._clear(box)
        title = Gtk.Label(label="Import from crontab & systemd", xalign=0)
        title.get_style_context().add_class("cb-title")
        box.pack_start(title, False, False, 0)

        try:
            cron_text = CrontabBackend.read()
            entries = CrontabBackend.external_entries(cron_text)
        except Exception:
            cron_text = ""
            entries = []

        sec1 = Gtk.Label(label="Unmanaged crontab entries", xalign=0)
        sec1.get_style_context().add_class("cb-subtitle")
        box.pack_start(sec1, False, False, 0)
        if not entries:
            box.pack_start(Gtk.Label(label="No unmanaged crontab entries found.", xalign=0), False, False, 0)
        else:
            for entry in entries:
                card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                card.get_style_context().add_class("cb-card")
                col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                col.pack_start(Gtk.Label(label=entry.comment or entry.command, xalign=0), False, False, 0)
                sub = Gtk.Label(label=f"{entry.schedule} · {entry.command}", xalign=0)
                sub.get_style_context().add_class("cb-subtitle")
                col.pack_start(sub, False, False, 0)
                card.pack_start(col, True, True, 0)
                btn = Gtk.Button(label="Adopt")
                btn.connect("clicked", lambda _w, e=entry: self._adopt_cron_entry(e))
                card.pack_start(btn, False, False, 0)
                box.pack_start(card, False, False, 0)

        timers = SystemdBackend.external_timers(self.controller.paths)
        sec2 = Gtk.Label(label="Active systemd --user timers", xalign=0)
        sec2.get_style_context().add_class("cb-subtitle")
        box.pack_start(sec2, False, False, 0)
        if not timers:
            box.pack_start(Gtk.Label(label="No external systemd user timers found.", xalign=0), False, False, 0)
        else:
            for tm in timers:
                card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
                card.get_style_context().add_class("cb-card")
                card.pack_start(Gtk.Label(label=f"{tm.unit} → {tm.activates}", xalign=0), False, False, 0)
                sub = Gtk.Label(label=f"Next: {tm.next_trigger} · Last: {tm.last_trigger}", xalign=0)
                sub.get_style_context().add_class("cb-subtitle")
                card.pack_start(sub, False, False, 0)
                box.pack_start(card, False, False, 0)
        box.show_all()

    def _adopt_cron_entry(self, entry: ExternalCronEntry) -> None:
        sched = Schedule.structured_from_cron(entry.schedule) or Schedule.cron(entry.schedule)
        job = Job(
            name=entry.comment or Path(entry.command.split()[0]).name,
            action=JobAction.shell(entry.command),
            schedule=sched,
            backend="cron",
        )
        new_cron = CrontabBackend.removing(entry, CrontabBackend.read())
        CrontabBackend.write(new_cron)
        self.controller.save_job(job)
        self._select_job(job.id)

    def _render_settings(self) -> None:
        box = self.settings_page[1]
        self._clear(box)
        title = Gtk.Label(label="Settings", xalign=0)
        title.get_style_context().add_class("cb-title")
        box.pack_start(title, False, False, 0)

        s = self.controller.settings
        theme_combo = Gtk.ComboBoxText()
        for t in THEMES:
            theme_combo.append(t.id, f"{t.name} — {t.tagline}")
        theme_combo.set_active_id(s.theme)

        def on_theme(_w) -> None:
            tid = theme_combo.get_active_id() or "system"
            s.theme = tid
            self.apply_theme(tid)
            self.controller.save_settings(s)

        theme_combo.connect("changed", on_theme)
        box.pack_start(Gtk.Label(label="Theme", xalign=0), False, False, 0)
        box.pack_start(theme_combo, False, False, 0)

        autostart_cb = Gtk.CheckButton(label="Open CronBuddy in system tray at login")
        autostart_cb.set_active(s.open_at_login)
        autostart_cb.connect("toggled", lambda w: self._update_setting("open_at_login", w.get_active()))
        box.pack_start(autostart_cb, False, False, 0)

        countdown_cb = Gtk.CheckButton(label="Show countdown to next run in tray")
        countdown_cb.set_active(s.show_countdown)
        countdown_cb.connect("toggled", lambda w: self._update_setting("show_countdown", w.get_active()))
        box.pack_start(countdown_cb, False, False, 0)

        keep_spin = Gtk.SpinButton.new_with_range(5, 500, 5)
        keep_spin.set_value(s.keep_runs)
        keep_spin.connect("value-changed", lambda w: self._update_setting("keep_runs", int(w.get_value())))
        keep_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        keep_row.pack_start(Gtk.Label(label="Runs to keep per job:", xalign=0), False, False, 0)
        keep_row.pack_start(keep_spin, False, False, 0)
        box.pack_start(keep_row, False, False, 0)

        reconcile_btn = Gtk.Button(label="Reinstall every job")
        reconcile_btn.connect("clicked", lambda *_: self.controller.reconcile_all())
        box.pack_start(reconcile_btn, False, False, 0)

        paths_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        paths_card.get_style_context().add_class("cb-card")
        paths_card.pack_start(Gtk.Label(label=f"Jobs config: {self.controller.paths.jobs_file}", xalign=0), False, False, 0)
        paths_card.pack_start(Gtk.Label(label=f"Action scripts: {self.controller.paths.actions_dir}", xalign=0), False, False, 0)
        paths_card.pack_start(Gtk.Label(label=f"Run logs: {self.controller.paths.logs_dir}", xalign=0), False, False, 0)
        paths_card.pack_start(Gtk.Label(label=f"Systemd units: {self.controller.paths.systemd_user_dir}", xalign=0), False, False, 0)
        box.pack_start(paths_card, False, False, 0)
        box.show_all()

    def _update_setting(self, field: str, value: object) -> None:
        setattr(self.controller.settings, field, value)
        self.controller.save_settings(self.controller.settings)

    def open_new_job_dialog(self) -> None:
        dlg = JobEditorDialog(self, self.controller)
        if dlg.run() == Gtk.ResponseType.OK and dlg.result_job:
            self.controller.save_job(dlg.result_job)
            self._select_job(dlg.result_job.id)
        dlg.destroy()

    def open_edit_job_dialog(self, job: Job) -> None:
        dlg = JobEditorDialog(self, self.controller, job=job)
        if dlg.run() == Gtk.ResponseType.OK and dlg.result_job:
            self.controller.save_job(dlg.result_job)
            self._select_job(dlg.result_job.id)
        dlg.destroy()

    def _confirm_delete(self, job: Job) -> None:
        dlg = Gtk.MessageDialog(
            transient_for=self,
            flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Delete “{job.name}”?",
        )
        dlg.format_secondary_text("Its timer/cron entry, action script, and logs will be removed.")
        if dlg.run() == Gtk.ResponseType.YES:
            self.controller.delete_job(job.id)
            self.selected_job_id = None
            self.stack.set_visible_child_name("overview")
            self.refresh_ui()
        dlg.destroy()

    def _run_job_from_ui(self, job_id: str) -> None:
        job = next((j for j in self.controller.jobs if j.id == job_id), None)
        if not job:
            return
        ActionScript.write(job, self.controller.paths.action_script(job.id))

        def worker() -> None:
            ScheduledRun.run(
                job.id,
                self.controller.paths,
                trigger="manual",
                job=job,
                keep_runs=self.controller.settings.keep_runs,
            )
            GLib.idle_add(self.controller.notify_listeners)

        threading.Thread(target=worker, daemon=True).start()

    def _open_path(self, path: Path) -> None:
        xdg = shutil.which("xdg-open")
        if xdg:
            subprocess.Popen([xdg, str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class TrayIndicator:
    """AyatanaAppIndicator3 menu bar / system tray item."""

    def __init__(
        self,
        app: Gtk.Application,
        controller: CronBuddyController,
        window_getter: Callable[[], CronBuddyWindow],
    ):
        self.app = app
        self.controller = controller
        self.get_window = window_getter
        self.indicator = None
        if AppIndicator is None:
            return
        icon = _icon_path() or "appointment-soon"
        self.indicator = AppIndicator.Indicator.new(
            "cronbuddy-linux",
            icon,
            AppIndicator.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.controller.subscribe(self.rebuild_menu)
        self.rebuild_menu()
        GLib.timeout_add_seconds(15, self._tick)

    def _tick(self) -> bool:
        self.rebuild_menu()
        return True

    def rebuild_menu(self) -> None:
        if self.indicator is None:
            return
        menu = Gtk.Menu()
        upcoming = self.controller.next_upcoming()
        if upcoming and self.controller.settings.show_countdown:
            delta = upcoming[1] - datetime.datetime.now().astimezone()
            self.indicator.set_label(f" {_format_countdown(delta)}", "88d 88h")
            up_item = Gtk.MenuItem(label=f"Up next: {upcoming[0].name} ({_format_countdown(delta)})")
            up_item.set_sensitive(False)
            menu.append(up_item)
        else:
            self.indicator.set_label("", "")

        if self.controller.jobs:
            menu.append(Gtk.SeparatorMenuItem())
            for job in sorted(self.controller.jobs, key=lambda j: j.name.lower()):
                runs = RunHistory.load(job.id, self.controller.paths)
                running = RunHistory.running_pid(job.id, self.controller.paths)
                badge = "⏸" if not job.is_enabled else ("⟳" if running else ("✕" if runs and not runs[0].succeeded else "●"))
                item = Gtk.MenuItem(label=f"{badge} {job.name} — {job.schedule.summary}")
                sub = Gtk.Menu()
                run_now = Gtk.MenuItem(label="Run Now")
                run_now.connect("activate", lambda _w, jid=job.id: self._run_now(jid))
                toggle = Gtk.MenuItem(label="Pause" if job.is_enabled else "Resume")
                toggle.connect("activate", lambda _w, jid=job.id: self.controller.toggle_job(jid))
                details = Gtk.MenuItem(label="Open Details")
                details.connect("activate", lambda _w, jid=job.id: self._open_job(jid))
                sub.append(run_now)
                sub.append(toggle)
                sub.append(details)
                item.set_submenu(sub)
                menu.append(item)

        menu.append(Gtk.SeparatorMenuItem())
        open_item = Gtk.MenuItem(label="Open CronBuddy")
        open_item.connect("activate", lambda *_: self.get_window().present())
        new_item = Gtk.MenuItem(label="New Job…")
        new_item.connect("activate", lambda *_: self._open_new())
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", lambda *_: self.app.quit())
        menu.append(open_item)
        menu.append(new_item)
        menu.append(quit_item)
        menu.show_all()
        self.indicator.set_menu(menu)

    def _run_now(self, job_id: str) -> None:
        win = self.get_window()
        win._run_job_from_ui(job_id)

    def _open_job(self, job_id: str) -> None:
        win = self.get_window()
        win.present()
        win._select_job(job_id)

    def _open_new(self) -> None:
        win = self.get_window()
        win.present()
        win.open_new_job_dialog()


class CronBuddyApplication(Gtk.Application):
    def __init__(self, start_in_tray: bool = False):
        super().__init__(application_id="com.lucasrafaldini.cronbuddy")
        self.start_in_tray = start_in_tray
        self.controller = CronBuddyController()
        self.window: CronBuddyWindow | None = None
        self.tray: TrayIndicator | None = None

    def _get_window(self) -> CronBuddyWindow:
        if self.window is None:
            self.window = CronBuddyWindow(self, self.controller)
        return self.window

    def do_activate(self) -> None:
        self.controller.reconcile_all()
        if self.tray is None:
            self.tray = TrayIndicator(self, self.controller, self._get_window)
        win = self._get_window()
        if not self.start_in_tray or AppIndicator is None:
            win.present()
        self.start_in_tray = False


def run_gui(start_in_tray: bool = False) -> int:
    app = CronBuddyApplication(start_in_tray=start_in_tray)
    return app.run(None)
