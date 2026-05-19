#!/bin/bash
# Ping Google to test internet connection
LOG_FILE="$HOME/CronBuddyScripts/logs/ping_test.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "🔌 Testing internet connectivity at $(date)..." | tee -a "$LOG_FILE"

if ping -c 3 google.com &> /dev/null; then
    echo "✅ Success! Internet is active." | tee -a "$LOG_FILE"
else
    echo "❌ Error! Failed to reach google.com." | tee -a "$LOG_FILE"
fi
echo "" >> "$LOG_FILE"
