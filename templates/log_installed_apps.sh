#!/bin/bash
# Log installed macOS Applications
LOG_FILE="$HOME/CronBuddyScripts/logs/installed_apps.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "--- Installed Applications - $(date) ---" > "$LOG_FILE"

# List applications in the main Applications folder
ls -1 /Applications | grep "\.app$" >> "$LOG_FILE"
echo "✅ Log updated at $LOG_FILE"
