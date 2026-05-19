#!/bin/bash
# Log running Docker containers
LOG_FILE="$HOME/CronBuddyScripts/logs/docker_containers.log"

mkdir -p "$(dirname "$LOG_FILE")"
echo "--- Running Docker Containers - $(date) ---" >> "$LOG_FILE"

# Check if docker command is available
if command -v docker &> /dev/null; then
    docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" >> "$LOG_FILE"
else
    echo "⚠️ Docker command not found. Make sure Docker Desktop is installed and running." >> "$LOG_FILE"
fi
echo "" >> "$LOG_FILE"
