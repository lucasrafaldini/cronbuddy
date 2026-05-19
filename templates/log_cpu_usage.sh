#!/bin/bash
# Log CPU usage on macOS
LOG_FILE="$HOME/CronBuddyScripts/logs/cpu_usage.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "--- CPU Usage Log - $(date) ---" >> "$LOG_FILE"

# Extract CPU usage percentage using native top command on macOS
top -l 1 | grep "CPU usage" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
