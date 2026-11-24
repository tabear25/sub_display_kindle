#!/usr/bin/env python3
"""Builds dist/koreader/, the files you copy onto the Kindle.

The result mirrors the Kindle's own koreader folder; copy the plugin folders into
koreader/plugins/ (and koplay.json into koreader/settings/) on the Kindle:

    dist/koreader/plugins/koplay.koplugin/     (KoPlay, from this repository)
    dist/koreader/plugins/deskdeck.koplugin/   (DeskDeck)
    dist/koreader/settings/koplay.json         (only with --with-auth)

Do not drag the whole koreader folder over the Kindle's: Finder on macOS replaces folders
instead of merging them, which would delete KOReader itself.

Usage:
    python3 tools/make_dist.py               (Windows: py tools\\make_dist.py)
    python3 tools/make_dist.py --with-auth   also copy tools/koplay.json (your Spotify login)

dist/ is in .gitignore. koplay.json is never put anywhere else than settings/.
"""

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
KOREADER = DIST / "koreader"
AUTH_FILE = ROOT / "tools" / "koplay.json"

# Files that never belong on the device.
SKIP_NAMES = {"__pycache__", ".DS_Store", "Thumbs.db", "koplay.json"}


def skip(name: str) -> bool:
    return name in SKIP_NAMES or name.startswith(".")


def copy_plugin(src: Path, dest: Path) -> int:
    count = 0
    for path in sorted(src.rglob("*")):
        rel = path.relative_to(src)
        if any(skip(part) for part in rel.parts):
            continue
        target = dest / rel
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description="Build dist/koreader for copying onto the Kindle.")
    parser.add_argument("--with-auth", action="store_true",
                        help="also copy tools/koplay.json into dist/koreader/settings/")
    args = parser.parse_args()

    plugins = sorted(p for p in ROOT.glob("*.koplugin") if p.is_dir())
    if not plugins:
        print("エラー: *.koplugin フォルダが見つかりません。リポジトリの中で実行してください。")
        return 1

    if KOREADER.exists():
        shutil.rmtree(KOREADER)

    for plugin in plugins:
        n = copy_plugin(plugin, KOREADER / "plugins" / plugin.name)
        print(f"  plugins/{plugin.name}  ({n} ファイル)")

    if args.with_auth:
        if AUTH_FILE.is_file():
            (KOREADER / "settings").mkdir(parents=True, exist_ok=True)
            shutil.copy2(AUTH_FILE, KOREADER / "settings" / "koplay.json")
            print("  settings/koplay.json  (Spotify のログイン情報)")
        else:
            print(f"注意: {AUTH_FILE} がありません。先に tools/koplay_auth.py を実行してください。")

    print()
    print(f"できました: {KOREADER}")
    print("Kindle をつないだら、次をコピーしてください:")
    print("  dist/koreader/plugins の中のフォルダ  →  Kindle の koreader/plugins")
    if args.with_auth:
        print("  dist/koreader/settings/koplay.json    →  Kindle の koreader/settings")
    print("koreader フォルダごと上書きはしないでください（Mac では中身が置き換わり、KOReader が消えます）。")
    if args.with_auth:
        print("コピーが終わったら、PC 側の dist フォルダと tools/koplay.json は削除してください。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
