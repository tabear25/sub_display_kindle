#!/bin/sh
# Runs KoPlay + DeskDeck in KOReader's Linux desktop build (AppImage) at the Kindle
# Paperwhite 4 screen size (1072x1448, 300 dpi). Works on Linux, and on Windows through
# WSL2 (the window shows up through WSLg). See docs/EMULATOR.md.
#
# Usage: tools/emulator_linux.sh [--half] /path/to/koreader-....AppImage
#   --half  536x724 window at 150 dpi (same proportions, half the pixels), for screens
#           shorter than 1448 px. Pixel sizes are halved too: do final checks at full size.
# The AppImage can also be given as KOREADER_APPIMAGE=/path/to/file.
#
# Plugins are symlinked, so restarting the emulator picks up code changes.
# If tools/koplay.json exists, the emulator uses that Spotify login. Use a separate
# login from the Kindle's (run tools/koplay_auth.py again) so the two don't share a token.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="$ROOT/.emulator/home"

W=1072
H=1448
DPI=300
if [ "$1" = "--half" ]; then
    W=536
    H=724
    DPI=150
    shift
fi
APP="${1:-$KOREADER_APPIMAGE}"

if [ -z "$APP" ] || [ ! -f "$APP" ]; then
    echo "KOReader の AppImage を指定してください:"
    echo "  tools/emulator_linux.sh [--half] /path/to/koreader-....AppImage"
    echo "入手先: https://github.com/koreader/koreader/releases （Linux x86_64 用の .AppImage）"
    exit 1
fi
chmod +x "$APP"

mkdir -p "$HOME_DIR/plugins" "$HOME_DIR/settings"
for plugin in "$ROOT"/*.koplugin; do
    ln -sfn "$plugin" "$HOME_DIR/plugins/$(basename "$plugin")"
done
if [ -f "$ROOT/tools/koplay.json" ]; then
    ln -sfn "$ROOT/tools/koplay.json" "$HOME_DIR/settings/koplay.json"
fi

echo "KOReader を ${W}x${H} (${DPI} dpi) で起動します。設定とログ: $HOME_DIR"
# KO_HOME: keep the emulator's settings inside the repository (.emulator/ is ignored by git).
# APPIMAGE_EXTRACT_AND_RUN: run without FUSE, which WSL2 usually lacks.
KO_HOME="$HOME_DIR" \
EMULATE_READER_W="$W" EMULATE_READER_H="$H" EMULATE_READER_DPI="$DPI" \
APPIMAGE_EXTRACT_AND_RUN=1 \
exec "$APP"
