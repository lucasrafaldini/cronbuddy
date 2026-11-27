import os
from pathlib import Path

import pytest

from cronbuddy_linux.themes import THEMES, build_gtk_css

gi = pytest.importorskip("gi")
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402


def test_all_themes_compile_to_valid_gtk_css():
    for theme in THEMES:
        provider = Gtk.CssProvider()
        css = build_gtk_css(theme)
        # In PyGObject, load_from_data raises GLib.Error on invalid CSS and returns None on success.
        provider.load_from_data(css.encode("utf-8"))
        assert provider.to_string()


def test_gtk_window_and_editor_smoke(tmp_path: Path, monkeypatch):
    if Gdk.Display.get_default() is None:
        pytest.skip("No X11/Wayland display available in headless environment")

    monkeypatch.setenv("CRONBUDDY_HOME", str(tmp_path))
    from cronbuddy_linux.models import Job, JobAction
    from cronbuddy_linux.schedule import Schedule
    from cronbuddy_linux.ui import CronBuddyController, CronBuddyWindow, JobEditorDialog

    ctrl = CronBuddyController()
    job = Job(id="ui1", name="UI Smoke Job", action=JobAction.shell("echo ok"), schedule=Schedule.interval(15))
    ctrl.save_job(job)

    app = Gtk.Application(application_id="com.lucasrafaldini.cronbuddy.test")
    win = CronBuddyWindow(app, ctrl)
    for section in ("overview", "activity", "templates", "import", "settings"):
        win.show_section(section)
    win._select_job("ui1")

    dlg = JobEditorDialog(win, ctrl, job=job)
    assert dlg.result_job is not None
    assert dlg.save_btn.get_sensitive()
    dlg.destroy()
    win.destroy()
