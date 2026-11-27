#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
ICON_DIR="${HOME}/.local/share/icons/hicolor/256x256/apps"
SHARE_DIR="${HOME}/.local/share/cronbuddy-app"

mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR" "$SHARE_DIR"

rm -rf "$SHARE_DIR/cronbuddy_linux"
cp -R "$ROOT_DIR/cronbuddy_linux" "$SHARE_DIR/cronbuddy_linux"
cp "$REPO_ROOT/VERSION" "$SHARE_DIR/VERSION"

if [[ -f "$REPO_ROOT/assets/cronbuddy.png" ]]; then
  cp "$REPO_ROOT/assets/cronbuddy.png" "$ICON_DIR/cronbuddy.png"
fi

cat > "$BIN_DIR/cronbuddy" <<EOF
#!/usr/bin/env bash
export PYTHONPATH="$SHARE_DIR\${PYTHONPATH:+:\$PYTHONPATH}"
exec /usr/bin/python3 -m cronbuddy_linux "\$@"
EOF
chmod +x "$BIN_DIR/cronbuddy"
ln -sf "$BIN_DIR/cronbuddy" "$BIN_DIR/cronbuddy-linux"

cat > "$APP_DIR/cronbuddy.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=CronBuddy
Comment=Schedule scripts and track logs from the system tray
Exec=$BIN_DIR/cronbuddy
Icon=cronbuddy
Terminal=false
Categories=Utility;System;
StartupWMClass=com.lucasrafaldini.cronbuddy
EOF

echo "Installed CronBuddy Linux to $BIN_DIR/cronbuddy"
echo "Desktop entry written to $APP_DIR/cronbuddy.desktop"
