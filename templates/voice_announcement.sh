#!/bin/bash
# Voice Announcement using macOS native text-to-speech
ANNOUNCEMENT="Hello! This is a voice announcement from CronBuddy. Your scheduled cron job has run successfully."

echo "🔊 Playing announcement: '$ANNOUNCEMENT'"
say "$ANNOUNCEMENT"
