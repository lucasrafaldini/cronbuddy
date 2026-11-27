# CronBuddy for Linux

A native Linux companion port of **CronBuddy** built with Python 3, **GTK 3**, **Ayatana AppIndicator3**, **`systemd --user` timers**, and **`cron`**.

## Features

- **System tray indicator** (`AyatanaAppIndicator3`): shows countdown to the next run, job status badges, and quick `Run Now` / `Pause` / `Open Details` actions.
- **Two scheduling backends:**
  - `systemd` (default, `Persistent=true` user timers that catch up on runs missed while the machine slept).
  - `cron` (classic Unix `crontab` entries tagged `# cronbuddy:<id>`, preserving all your existing lines untouched).
- **Natural schedule editor:** Every N minutes/hours, Hourly, Daily, Weekly, Monthly, At login, or Custom cron expression with live next-run previews and validation.
- **Test Run & Run Now:** executes jobs through generated action scripts with live output streaming, PID `.running` markers, `runs.jsonl` history, log viewer, and desktop notifications (`notify-send`).
- **18 Linux-ready templates**, **crontab & systemd timer importer**, and **all 6 CronBuddy themes** (`System`, `Liquid Glass`, `Thoth`, `Paper`, `Phosphor`, `Nord`).

## Requirements

On Debian / Ubuntu / Linux Mint:

```bash
sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1 libnotify-bin
```

## Install & Run

```bash
cd linux
make install
cronbuddy
```

## Where things live (XDG)

| What | Where |
| --- | --- |
| Job definitions & settings | `~/.config/cronbuddy/` (`jobs.json`, `settings.json`) |
| Generated action scripts | `~/.local/share/cronbuddy/actions/` |
| Run logs & history | `~/.local/state/cronbuddy/logs/<job id>/` |
| systemd user units | `~/.config/systemd/user/cronbuddy-job-*.{service,timer}` |
| cron entries | lines in your crontab ending in `# cronbuddy:<job id>` |

Setting `CRONBUDDY_HOME=/tmp/test-home` sandboxes all paths and disables writes to the real `crontab` and `systemd --user`.

## Tests

```bash
cd linux
make test
```
