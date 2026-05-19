#!/bin/bash
# Log Memory usage on macOS
LOG_FILE="$HOME/CronBuddyScripts/logs/memory_usage.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "--- Memory Usage Log - $(date) ---" >> "$LOG_FILE"

# Get virtual memory statistics
vm_stat | head -n 5 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
