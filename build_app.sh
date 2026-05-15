#!/bin/bash

# CronBuddy Build Script for macOS
# This script handles the build process and resolves conflicts between pyproject.toml and py2app.

echo "🚀 Starting CronBuddy build process..."

# Check if pyproject.toml exists
if [ -f "pyproject.toml" ]; then
    echo "📦 Temporarily hiding pyproject.toml to avoid py2app conflicts..."
    mv pyproject.toml pyproject.toml.tmp
fi

# Run the build
echo "🔨 Building .app bundle..."
./venv/bin/python setup.py py2app

# Check build status
BUILD_STATUS=$?

# Restore pyproject.toml
if [ -f "pyproject.toml.tmp" ]; then
    echo "♻️ Restoring pyproject.toml..."
    mv pyproject.toml.tmp pyproject.toml
fi

if [ $BUILD_STATUS -eq 0 ]; then
    echo "✅ Build successful! You can find the app in dist/CronBuddy.app"
else
    echo "❌ Build failed. Please check the errors above."
    exit 1
fi
