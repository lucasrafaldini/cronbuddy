#!/bin/bash
# Clear macOS User Trash safely
TRASH_DIR="$HOME/.Trash"

echo "🗑️ Cleaning macOS Trash..."
if [ -d "$TRASH_DIR" ]; then
    # Delete contents but not the .Trash folder itself
    rm -rf "$TRASH_DIR"/*
    echo "✅ Trash cleaned successfully at $(date)!"
else
    echo "⚠️ Trash directory not found."
fi
