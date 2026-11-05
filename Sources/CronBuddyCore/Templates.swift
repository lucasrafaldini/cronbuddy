import Foundation

public enum TemplateCategory: String, CaseIterable, Identifiable, Sendable {
    case system, developer, information, finance, wellbeing, automation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .developer: "Developer"
        case .information: "Information"
        case .finance: "Finance"
        case .wellbeing: "Wellbeing"
        case .automation: "Automation"
        }
    }

    public var symbol: String {
        switch self {
        case .system: "desktopcomputer"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .information: "newspaper"
        case .finance: "chart.line.uptrend.xyaxis"
        case .wellbeing: "leaf"
        case .automation: "gearshape.2"
        }
    }
}

public struct JobTemplate: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let category: TemplateCategory
    public let symbol: String
    public let action: JobAction
    public let schedule: Schedule
    public let environment: [String: String]
    public let requirements: [String]

    public func makeJob() -> Job {
        Job(name: name, action: action, schedule: schedule, environment: environment)
    }
}

private func at(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

public enum Templates {
    public static let all: [JobTemplate] = [
        // MARK: System
        JobTemplate(
            id: "disk-report", name: "Disk Space Report",
            summary: "Free space on your startup disk plus the size of Downloads and caches.",
            category: .system, symbol: "internaldrive",
            action: .shell(command: """
            df -h / | awk 'NR==1 || NR==2'
            echo
            du -sh "$HOME/Downloads" "$HOME/Library/Caches" 2>/dev/null
            """),
            schedule: .weekly(weekdays: [1], times: [at(9)]), environment: [:], requirements: []
        ),
        JobTemplate(
            id: "system-snapshot", name: "CPU & Memory Snapshot",
            summary: "The ten busiest processes and memory pressure, for spotting what slows the Mac down.",
            category: .system, symbol: "cpu",
            action: .shell(command: """
            top -l 1 -n 10 -o cpu -stats pid,command,cpu,mem | tail -n 12
            echo
            memory_pressure | tail -n 1
            """),
            schedule: .interval(minutes: 60), environment: [:], requirements: []
        ),
        JobTemplate(
            id: "backup-documents", name: "Back Up Documents",
            summary: "Copies ~/Documents to a backup folder with rsync. Nothing is ever deleted from the backup.",
            category: .system, symbol: "externaldrive.badge.timemachine",
            action: .shell(command: """
            DEST="${BACKUP_DIR:-$HOME/Backups}/Documents"
            mkdir -p "$DEST"
            rsync -a --stats "$HOME/Documents/" "$DEST/"
            """),
            schedule: .daily(times: [at(21)]), environment: ["BACKUP_DIR": "~/Backups"], requirements: []
        ),
        JobTemplate(
            id: "tidy-downloads", name: "Tidy Downloads",
            summary: "Moves files untouched for 30 days from Downloads to the Trash, where they can still be recovered.",
            category: .system, symbol: "tray.and.arrow.down",
            action: .shell(command: """
            DAYS="${DAYS:-30}"
            find "$HOME/Downloads" -mindepth 1 -maxdepth 1 -mtime +"$DAYS" -print -exec mv {} "$HOME/.Trash/" ';'
            """),
            schedule: .weekly(weekdays: [0], times: [at(10)]), environment: ["DAYS": "30"], requirements: []
        ),
        JobTemplate(
            id: "empty-trash", name: "Empty the Trash",
            summary: "Asks Finder to empty the Trash, the same as choosing Finder › Empty Trash.",
            category: .system, symbol: "trash",
            action: .appleScript(source: "tell application \"Finder\" to empty the trash"),
            schedule: .monthly(days: [1], time: at(12)), environment: [:], requirements: ["Automation permission for Finder"]
        ),

        // MARK: Developer
        JobTemplate(
            id: "uptime-check", name: "Website Uptime Check",
            summary: "Fails when a site stops answering with a 2xx or 3xx status, so you get notified.",
            category: .developer, symbol: "network",
            action: .shell(command: """
            URL="${CHECK_URL:-https://example.com}"
            read -r CODE TIME <<< "$(curl -s -o /dev/null -m 20 -w '%{http_code} %{time_total}' "$URL")"
            echo "$URL → HTTP $CODE in ${TIME}s"
            [[ "$CODE" == 2* || "$CODE" == 3* ]]
            """),
            schedule: .interval(minutes: 5), environment: ["CHECK_URL": "https://example.com"], requirements: ["Internet"]
        ),
        JobTemplate(
            id: "brew-outdated", name: "Homebrew Outdated",
            summary: "Refreshes Homebrew and lists formulae and casks with pending upgrades.",
            category: .developer, symbol: "mug",
            action: .shell(command: """
            brew update --quiet >/dev/null
            OUTDATED="$(brew outdated --verbose)"
            if [[ -z "$OUTDATED" ]]; then echo "Everything is up to date."; else echo "$OUTDATED"; fi
            """),
            schedule: .daily(times: [at(10)]), environment: [:], requirements: ["Homebrew"]
        ),
        JobTemplate(
            id: "git-status", name: "Uncommitted Work",
            summary: "Lists repositories under a folder that have uncommitted changes or unpushed commits.",
            category: .developer, symbol: "arrow.triangle.branch",
            action: .shell(command: """
            ROOT="${REPOS_DIR:-$HOME/Code}"
            find "$ROOT" -maxdepth 3 -name .git -type d -prune 2>/dev/null | while read -r gitdir; do
              repo="${gitdir:h}"
              state="$(git -C "$repo" status --porcelain=v1 --branch 2>/dev/null)"
              dirty="$(echo "$state" | grep -vc '^##')"
              ahead="$(echo "$state" | head -1 | grep -o 'ahead [0-9]*')"
              if (( dirty > 0 )) || [[ -n "$ahead" ]]; then
                echo "${repo#$ROOT/}: $dirty changed file(s) ${ahead:+· $ahead}"
              fi
            done
            """),
            schedule: .weekly(weekdays: [1, 2, 3, 4, 5], times: [at(18)]), environment: ["REPOS_DIR": "~/Code"], requirements: []
        ),
        JobTemplate(
            id: "docker-snapshot", name: "Docker Containers",
            summary: "Running containers with their status and resource usage.",
            category: .developer, symbol: "shippingbox",
            action: .shell(command: """
            docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}'
            echo
            docker stats --no-stream --format 'table {{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}'
            """),
            schedule: .interval(minutes: 30), environment: [:], requirements: ["Docker"]
        ),

        // MARK: Information
        JobTemplate(
            id: "weather", name: "Weather Forecast",
            summary: "Today’s forecast for your city from wttr.in.",
            category: .information, symbol: "cloud.sun",
            action: .shell(command: """
            CITY="${CITY:-São Paulo}"
            curl -sf -m 20 "https://wttr.in/${CITY// /+}?format=4"
            echo
            curl -sf -m 20 "https://wttr.in/${CITY// /+}?0Tq"
            """),
            schedule: .daily(times: [at(7)]), environment: ["CITY": "São Paulo"], requirements: ["Internet"]
        ),
        JobTemplate(
            id: "hacker-news", name: "Hacker News Top 10",
            summary: "The ten highest-ranked stories on Hacker News right now.",
            category: .information, symbol: "flame",
            action: .shell(command: """
            curl -sf -m 20 https://hacker-news.firebaseio.com/v0/topstories.json | /usr/bin/python3 -c '
            import json, sys, urllib.request
            for n, i in enumerate(json.load(sys.stdin)[:10], 1):
                item = json.load(urllib.request.urlopen("https://hacker-news.firebaseio.com/v0/item/%d.json" % i, timeout=20))
                link = item.get("url") or "https://news.ycombinator.com/item?id=%d" % i
                print("%2d. %s\\n    %s" % (n, item.get("title", ""), link))
            '
            """),
            schedule: .daily(times: [at(8), at(17)]), environment: [:], requirements: ["Internet"]
        ),

        // MARK: Finance
        JobTemplate(
            id: "fx-rates", name: "Dollar, Euro & Bitcoin",
            summary: "USD, EUR and BTC quotes in Brazilian reais from AwesomeAPI.",
            category: .finance, symbol: "dollarsign.circle",
            action: .shell(command: """
            curl -sf -m 20 "https://economia.awesomeapi.com.br/json/last/USD-BRL,EUR-BRL,BTC-BRL" | /usr/bin/python3 -c '
            import json, sys
            for v in json.load(sys.stdin).values():
                print("%-32s R$ %12s   %+.2f%%" % (v["name"], "{:,.2f}".format(float(v["bid"])), float(v["pctChange"])))
            '
            """),
            schedule: .weekly(weekdays: [1, 2, 3, 4, 5], times: [at(9), at(18)]), environment: [:], requirements: ["Internet"]
        ),
        JobTemplate(
            id: "crypto", name: "Crypto Prices",
            summary: "Bitcoin, Ethereum and Solana prices with 24-hour change, from CoinGecko.",
            category: .finance, symbol: "bitcoinsign.circle",
            action: .shell(command: """
            curl -sf -m 20 "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=${CURRENCY:-usd}&include_24hr_change=true" | /usr/bin/python3 -c '
            import json, os, sys
            cur = os.environ.get("CURRENCY", "usd")
            for coin, v in json.load(sys.stdin).items():
                print("%-10s %14s %s   %+.2f%%" % (coin.title(), "{:,.2f}".format(v[cur]), cur.upper(), v[cur + "_24h_change"]))
            '
            """),
            schedule: .daily(times: [at(9), at(21)]), environment: ["CURRENCY": "usd"], requirements: ["Internet"]
        ),
        JobTemplate(
            id: "bcb-indicators", name: "SELIC, CDI & IPCA",
            summary: "Latest Brazilian economic indicators straight from the Central Bank’s open data.",
            category: .finance, symbol: "building.columns",
            action: .shell(command: """
            for pair in "432:SELIC target (% p.a.)" "12:CDI (% p.d.)" "433:IPCA (% month)"; do
              code="${pair%%:*}"; label="${pair#*:}"
              value="$(curl -sf -m 20 "https://api.bcb.gov.br/dados/serie/bcdata.sgs.$code/dados/ultimos/1?formato=json" |
                /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin)[0]; print(d["valor"], "·", d["data"])')"
              printf '%-22s %s\\n' "$label" "$value"
            done
            """),
            schedule: .weekly(weekdays: [1, 2, 3, 4, 5], times: [at(9)]), environment: [:], requirements: ["Internet"]
        ),

        // MARK: Wellbeing
        JobTemplate(
            id: "break-reminder", name: "Take a Break",
            summary: "A gentle notification to drink water, stretch and look away from the screen.",
            category: .wellbeing, symbol: "drop",
            action: .appleScript(source: "display notification \"Drink some water, stretch, and rest your eyes.\" with title \"CronBuddy\" subtitle \"Time for a break\" sound name \"Glass\""),
            schedule: .weekly(weekdays: [1, 2, 3, 4, 5], times: [at(10), at(14), at(17)]), environment: [:], requirements: []
        ),
        JobTemplate(
            id: "spoken-time", name: "Spoken Announcement",
            summary: "Says the time out loud, a hands-free way to keep track of long sessions.",
            category: .wellbeing, symbol: "speaker.wave.2",
            action: .shell(command: "say \"It is $(date '+%-H:%M'). ${MESSAGE:-Keep going.}\""),
            schedule: .weekly(weekdays: [1, 2, 3, 4, 5], times: [at(12), at(18)]), environment: ["MESSAGE": "Keep going."], requirements: []
        ),

        // MARK: Automation
        JobTemplate(
            id: "run-shortcut", name: "Run a Shortcut",
            summary: "Runs any shortcut from the Shortcuts app on a schedule. Pick it after choosing this template.",
            category: .automation, symbol: "square.stack.3d.up",
            action: .shortcut(name: ""),
            schedule: .daily(times: [at(8)]), environment: [:], requirements: ["Shortcuts"]
        ),
        JobTemplate(
            id: "dark-mode-evening", name: "Dark Mode in the Evening",
            summary: "Switches macOS to Dark Mode at the end of the day.",
            category: .automation, symbol: "moon",
            action: .appleScript(source: """
            tell application "System Events"
              tell appearance preferences to set dark mode to true
            end tell
            """),
            schedule: .daily(times: [at(19)]), environment: [:], requirements: ["Automation permission for System Events"]
        ),
        JobTemplate(
            id: "end-of-day", name: "End of Workday",
            summary: "Quits work apps at the end of the day so the evening stays yours.",
            category: .automation, symbol: "sunset",
            action: .appleScript(source: """
            repeat with appName in {"Slack", "Microsoft Teams", "Mail"}
              if application appName is running then tell application appName to quit
            end repeat
            display notification "Work apps closed. See you tomorrow." with title "CronBuddy"
            """),
            schedule: .weekly(weekdays: [1, 2, 3, 4, 5], times: [at(19)]), environment: [:], requirements: []
        ),
        JobTemplate(
            id: "daily-digest", name: "Daily Run Digest",
            summary: "Collects the output of everything CronBuddy ran today into one report.",
            category: .automation, symbol: "doc.richtext",
            action: .shell(command: """
            TODAY="$(date +%Y%m%d)"
            find "$HOME/Library/Logs/CronBuddy" -name "$TODAY-*.log" -type f 2>/dev/null | sort | while read -r log; do
              echo "━━━ ${${log:h}:t} · ${${log:t}:0:15}"
              head -n 40 "$log"
              echo
            done
            """),
            schedule: .daily(times: [at(23)]), environment: [:], requirements: []
        ),
    ]
}
