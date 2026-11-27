"""Ready-made Linux job templates matching CronBuddy's catalog."""

from __future__ import annotations

from dataclasses import dataclass, field

from .models import Job, JobAction
from .schedule import Schedule, TimeOfDay


def _at(h: int, m: int = 0) -> TimeOfDay:
    return TimeOfDay(h, m)


@dataclass(frozen=True)
class JobTemplate:
    id: str
    name: str
    summary: str
    category: str
    action: JobAction
    schedule: Schedule
    environment: dict[str, str] = field(default_factory=dict)
    requirements: list[str] = field(default_factory=list)

    def make_job(self) -> Job:
        return Job(
            name=self.name,
            action=self.action,
            schedule=self.schedule,
            environment=dict(self.environment),
        )


CATEGORIES = ["System", "Developer", "Information", "Finance", "Wellbeing", "Automation"]

TEMPLATES: list[JobTemplate] = [
    JobTemplate(
        id="disk-report",
        name="Disk Space Report",
        summary="Free space on your root filesystem plus the size of Downloads and caches.",
        category="System",
        action=JobAction.shell(
            'df -h / | awk \'NR==1 || NR==2\'\necho\ndu -sh "$HOME/Downloads" "$HOME/.cache" 2>/dev/null'
        ),
        schedule=Schedule.weekly([1], [_at(9)]),
    ),
    JobTemplate(
        id="system-snapshot",
        name="CPU & Memory Snapshot",
        summary="Top ten busiest processes and RAM/swap usage on Linux.",
        category="System",
        action=JobAction.shell(
            "ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 11\necho\nfree -h"
        ),
        schedule=Schedule.interval(60),
    ),
    JobTemplate(
        id="backup-documents",
        name="Back Up Documents",
        summary="Copies ~/Documents to a backup folder with rsync. Nothing is ever deleted from the backup.",
        category="System",
        action=JobAction.shell(
            'DEST="${BACKUP_DIR:-$HOME/Backups}/Documents"\nmkdir -p "$DEST"\nrsync -a --stats "$HOME/Documents/" "$DEST/"'
        ),
        schedule=Schedule.daily([_at(21)]),
        environment={"BACKUP_DIR": "~/Backups"},
    ),
    JobTemplate(
        id="tidy-downloads",
        name="Tidy Downloads",
        summary="Moves files untouched for 30 days from Downloads to the XDG Trash, where they can still be recovered.",
        category="System",
        action=JobAction.shell(
            'DAYS="${DAYS:-30}"\nTRASH="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"\nmkdir -p "$TRASH"\nfind "$HOME/Downloads" -mindepth 1 -maxdepth 1 -mtime +"$DAYS" -print -exec mv -t "$TRASH" {} +'
        ),
        schedule=Schedule.weekly([0], [_at(10)]),
        environment={"DAYS": "30"},
    ),
    JobTemplate(
        id="empty-trash",
        name="Empty the Trash",
        summary="Clears items in ~/.local/share/Trash older than 30 days.",
        category="System",
        action=JobAction.shell(
            'TRASH="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"\nfind "$TRASH/files" "$TRASH/info" -mindepth 1 -mtime +30 -delete 2>/dev/null || true'
        ),
        schedule=Schedule.monthly([1], _at(12)),
    ),
    JobTemplate(
        id="uptime-check",
        name="Website Uptime Check",
        summary="Fails when a site stops answering with a 2xx or 3xx status, so you get notified.",
        category="Developer",
        action=JobAction.shell(
            'URL="${CHECK_URL:-https://example.com}"\nread -r CODE TIME <<< "$(curl -s -o /dev/null -m 20 -w \'%{http_code} %{time_total}\' "$URL")"\necho "$URL → HTTP $CODE in ${TIME}s"\n[[ "$CODE" == 2* || "$CODE" == 3* ]]'
        ),
        schedule=Schedule.interval(5),
        environment={"CHECK_URL": "https://example.com"},
        requirements=["Internet"],
    ),
    JobTemplate(
        id="apt-upgradable",
        name="Package Updates Check",
        summary="Lists upgradable packages on Debian/Ubuntu/Mint (or Flatpak updates).",
        category="Developer",
        action=JobAction.shell(
            'if command -v apt >/dev/null 2>&1; then apt list --upgradable 2>/dev/null | grep -v "^Listing"; fi\nif command -v flatpak >/dev/null 2>&1; then flatpak remote-ls --updates; fi'
        ),
        schedule=Schedule.daily([_at(10)]),
    ),
    JobTemplate(
        id="git-status",
        name="Uncommitted Work",
        summary="Lists repositories under a folder that have uncommitted changes or unpushed commits.",
        category="Developer",
        action=JobAction.shell(
            'ROOT="${REPOS_DIR:-$HOME/Documents}"\nfind "$ROOT" -maxdepth 3 -name .git -type d -prune 2>/dev/null | while read -r gitdir; do\n  repo="$(dirname "$gitdir")"\n  state="$(git -C "$repo" status --porcelain=v1 --branch 2>/dev/null)"\n  dirty="$(echo "$state" | grep -vc "^##")"\n  ahead="$(echo "$state" | head -1 | grep -o "ahead [0-9]*")"\n  if (( dirty > 0 )) || [[ -n "$ahead" ]]; then\n    echo "${repo#$ROOT/}: $dirty changed file(s) ${ahead:+· $ahead}"\n  fi\ndone'
        ),
        schedule=Schedule.weekly([1, 2, 3, 4, 5], [_at(18)]),
        environment={"REPOS_DIR": "~/Documents"},
    ),
    JobTemplate(
        id="docker-snapshot",
        name="Docker Containers",
        summary="Running containers with their status and resource usage.",
        category="Developer",
        action=JobAction.shell(
            "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}'\necho\ndocker stats --no-stream --format 'table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}'"
        ),
        schedule=Schedule.interval(30),
        requirements=["Docker"],
    ),
    JobTemplate(
        id="weather",
        name="Weather Forecast",
        summary="Today’s forecast for your city from wttr.in.",
        category="Information",
        action=JobAction.shell(
            'CITY="${CITY:-São Paulo}"\ncurl -sf -m 20 "https://wttr.in/${CITY// /+}?format=4"\necho\ncurl -sf -m 20 "https://wttr.in/${CITY// /+}?0Tq"'
        ),
        schedule=Schedule.daily([_at(7)]),
        environment={"CITY": "São Paulo"},
        requirements=["Internet"],
    ),
    JobTemplate(
        id="hacker-news",
        name="Hacker News Top 10",
        summary="The ten highest-ranked stories on Hacker News right now.",
        category="Information",
        action=JobAction.shell(
            'curl -sf -m 20 https://hacker-news.firebaseio.com/v0/topstories.json | /usr/bin/python3 -c \'\nimport json, sys, urllib.request\nfor n, i in enumerate(json.load(sys.stdin)[:10], 1):\n    item = json.load(urllib.request.urlopen("https://hacker-news.firebaseio.com/v0/item/%d.json" % i, timeout=20))\n    link = item.get("url") or "https://news.ycombinator.com/item?id=%d" % i\n    print("%2d. %s\\n    %s" % (n, item.get("title", ""), link))\n\''
        ),
        schedule=Schedule.daily([_at(8), _at(17)]),
        requirements=["Internet"],
    ),
    JobTemplate(
        id="fx-rates",
        name="Dollar, Euro & Bitcoin",
        summary="USD, EUR and BTC quotes in Brazilian reais from AwesomeAPI.",
        category="Finance",
        action=JobAction.shell(
            'curl -sf -m 20 "https://economia.awesomeapi.com.br/json/last/USD-BRL,EUR-BRL,BTC-BRL" | /usr/bin/python3 -c \'\nimport json, sys\nfor v in json.load(sys.stdin).values():\n    print("%-32s R$ %12s   %+.2f%%" % (v["name"], "{:,.2f}".format(float(v["bid"])), float(v["pctChange"])))\n\''
        ),
        schedule=Schedule.weekly([1, 2, 3, 4, 5], [_at(9), _at(18)]),
        requirements=["Internet"],
    ),
    JobTemplate(
        id="crypto",
        name="Crypto Prices",
        summary="Bitcoin, Ethereum and Solana prices with 24-hour change, from CoinGecko.",
        category="Finance",
        action=JobAction.shell(
            'curl -sf -m 20 "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=${CURRENCY:-usd}&include_24hr_change=true" | /usr/bin/python3 -c \'\nimport json, os, sys\ncur = os.environ.get("CURRENCY", "usd")\nfor coin, v in json.load(sys.stdin).items():\n    print("%-10s %14s %s   %+.2f%%" % (coin.title(), "{:,.2f}".format(v[cur]), cur.upper(), v[cur + "_24h_change"]))\n\''
        ),
        schedule=Schedule.daily([_at(9), _at(21)]),
        environment={"CURRENCY": "usd"},
        requirements=["Internet"],
    ),
    JobTemplate(
        id="bcb-indicators",
        name="SELIC, CDI & IPCA",
        summary="Latest Brazilian economic indicators straight from the Central Bank’s open data.",
        category="Finance",
        action=JobAction.shell(
            'for pair in "432:SELIC target (% p.a.)" "12:CDI (% p.d.)" "433:IPCA (% month)"; do\n  code="${pair%%:*}"; label="${pair#*:}"\n  value="$(curl -sf -m 20 "https://api.bcb.gov.br/dados/serie/bcdata.sgs.$code/dados/ultimos/1?formato=json" |\n    /usr/bin/python3 -c \'import json,sys; d=json.load(sys.stdin)[0]; print(d["valor"], "·", d["data"])\')"\n  printf \'%-22s %s\\n\' "$label" "$value"\ndone'
        ),
        schedule=Schedule.weekly([1, 2, 3, 4, 5], [_at(9)]),
        requirements=["Internet"],
    ),
    JobTemplate(
        id="break-reminder",
        name="Take a Break",
        summary="A gentle desktop notification to drink water, stretch and look away from the screen.",
        category="Wellbeing",
        action=JobAction.shell(
            'notify-send -a "CronBuddy" "Time for a break" "Drink some water, stretch, and rest your eyes."'
        ),
        schedule=Schedule.weekly([1, 2, 3, 4, 5], [_at(10), _at(14), _at(17)]),
        requirements=["notify-send"],
    ),
    JobTemplate(
        id="spoken-time",
        name="Spoken Announcement",
        summary="Speaks the time out loud using speech-dispatcher or espeak-ng.",
        category="Wellbeing",
        action=JobAction.shell(
            'MSG="It is $(date \'+%-H:%M\'). ${MESSAGE:-Keep going.}"\nif command -v spd-say >/dev/null 2>&1; then spd-say "$MSG"; elif command -v espeak-ng >/dev/null 2>&1; then espeak-ng "$MSG"; else echo "$MSG"; fi'
        ),
        schedule=Schedule.weekly([1, 2, 3, 4, 5], [_at(12), _at(18)]),
        environment={"MESSAGE": "Keep going."},
    ),
    JobTemplate(
        id="dark-mode-evening",
        name="Dark Mode in the Evening",
        summary="Switches GNOME/GTK desktops to prefer-dark at the end of the day.",
        category="Automation",
        action=JobAction.shell(
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'"
        ),
        schedule=Schedule.daily([_at(19)]),
        requirements=["GNOME / gsettings"],
    ),
    JobTemplate(
        id="daily-digest",
        name="Daily Run Digest",
        summary="Collects the output of everything CronBuddy ran today into one report.",
        category="Automation",
        action=JobAction.shell(
            'TODAY="$(date +%Y%m%d)"\nLOG_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/cronbuddy/logs"\nfind "$LOG_ROOT" -name "$TODAY-*.log" -type f 2>/dev/null | sort | while read -r log; do\n  echo "━━━ $(basename "$(dirname "$log")") · $(basename "$log")"\n  head -n 40 "$log"\n  echo\ndone'
        ),
        schedule=Schedule.daily([_at(23)]),
    ),
]
