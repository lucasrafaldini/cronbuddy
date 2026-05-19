#!/bin/bash
# Fetch web page headers to verify status
URL="https://www.google.com"
LOG_FILE="$HOME/CronBuddyScripts/logs/fetch_web_page.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "🌐 Checking URL: $URL" | tee -a "$LOG_FILE"

# Fetch headers and log response code
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" "$URL")
echo "[$(date)] Status code for $URL: $HTTP_STATUS" | tee -a "$LOG_FILE"
