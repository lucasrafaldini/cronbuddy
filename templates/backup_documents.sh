#!/bin/bash
# Backup user's Documents directory
BACKUP_DIR="$HOME/CronBuddyBackups"
SOURCE_DIR="$HOME/Documents"

echo "📂 Starting Documents backup..."
mkdir -p "$BACKUP_DIR"

# Perform backup using rsync
rsync -av --delete "$SOURCE_DIR/" "$BACKUP_DIR/Documents_Backup/"

echo "✅ Backup completed successfully at $(date)!"
