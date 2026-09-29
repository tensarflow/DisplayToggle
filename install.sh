#!/bin/bash
# Installs DisplayToggle.app into ~/Applications, links displayctl into ~/.local/bin, and starts it.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

APPS="$HOME/Applications"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$APPS" "$BIN_DIR"

pkill -x DisplayToggle 2>/dev/null || true
rm -rf "$APPS/DisplayToggle.app"
cp -R build/DisplayToggle.app "$APPS/"
ln -sf "$APPS/DisplayToggle.app/Contents/MacOS/DisplayToggle" "$BIN_DIR/displayctl"
open "$APPS/DisplayToggle.app"

echo "Installed $APPS/DisplayToggle.app and $BIN_DIR/displayctl"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Note: $BIN_DIR is not on your PATH" ;; esac
