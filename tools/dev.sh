#!/bin/bash
# Native macOS development commands. Compatible with macOS's bundled Bash.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$ROOT/.dev"
KOREADER="$DEV/koreader"
KOREADER_REF=v2026.07.1
KOREADER_COMMIT=9192014d8bd82a91dc1012473be0f238dedfdb54

die() { echo "$*" >&2; exit 1; }
usage() {
    echo 'Usage: tools/dev.sh {setup|check [spec/file_spec.lua]|sync|run [book.epub]}'
}

case "${1:-help}" in
    help|-h|--help) usage; exit 0 ;;
    setup|check|sync|run) command_name="$1"; shift ;;
    *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }
case "$command_name" in setup|sync) [ "$#" -eq 0 ] || { usage >&2; exit 2; } ;; esac
[ "$(uname -s)" = Darwin ] || die 'This workflow requires macOS.'
command -v brew >/dev/null || die 'Install Homebrew first: https://brew.sh'
BREW_PREFIX="$(brew --prefix)"
export PATH="$BREW_PREFIX/opt/findutils/libexec/gnubin:$BREW_PREFIX/opt/gnu-getopt/bin:$BREW_PREFIX/opt/make/libexec/gnubin:$BREW_PREFIX/opt/util-linux/bin:$BREW_PREFIX/bin:$PATH"
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "$DEV"

rocks() {
    luarocks --lua-version=5.1 --lua-dir="$BREW_PREFIX/opt/luajit" --tree="$DEV/rocks" "$@"
}

if [ "$command_name" = setup ]; then
    xcode-select -p >/dev/null || die 'Install Apple command line tools with xcode-select --install.'
    formulae=(autoconf automake bash binutils cmake coreutils findutils gettext
        gnu-getopt libtool make meson nasm ninja pkgconf sdl3 util-linux luajit luarocks wget python@3.14)
    missing=()
    for formula in "${formulae[@]}"; do
        [ -d "$BREW_PREFIX/opt/$formula" ] || missing+=("$formula")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install "${missing[@]}"
    fi
    if [ ! -x "$DEV/venv/bin/python" ]; then
        "$BREW_PREFIX/opt/python@3.14/bin/python3.14" -m venv "$DEV/venv"
    fi
    "$DEV/venv/bin/python" -m pip install -r "$ROOT/tools/dev-requirements.txt"
    rocks show busted 2.3.0-1 >/dev/null 2>&1 || rocks install busted 2.3.0-1
    rocks show dkjson 2.8-1 >/dev/null 2>&1 || rocks install dkjson 2.8-1
    if [ ! -d "$KOREADER" ]; then
        git clone --branch "$KOREADER_REF" --depth 1 https://github.com/koreader/koreader.git "$KOREADER"
    fi
    [ "$(git -C "$KOREADER" rev-parse HEAD)" = "$KOREADER_COMMIT" ] || die "Unexpected KOReader revision in $KOREADER; expected $KOREADER_REF."
    (
        cd "$KOREADER"
        "$BREW_PREFIX/bin/bash" ./kodev fetch-thirdparty
        PARALLEL_JOBS="${XRAY_BUILD_JOBS:-4}" "$BREW_PREFIX/bin/bash" ./kodev build
    )
    "$DEV/venv/bin/python" "$ROOT/tools/dev.py" sync
    echo 'Setup complete. Run tools/dev.sh check, then tools/dev.sh run.'
    exit 0
fi

[ -x "$DEV/venv/bin/python" ] || die 'Run tools/dev.sh setup first.'
if [ "$command_name" = check ]; then
    [ -f "$DEV/rocks/bin/busted" ] || die 'Run tools/dev.sh setup first.'
    export LUA_PATH="$DEV/rocks/share/lua/5.1/?.lua;$DEV/rocks/share/lua/5.1/?/init.lua;;"
    export LUA_CPATH="$DEV/rocks/lib/lua/5.1/?.so;;"
fi
exec "$DEV/venv/bin/python" "$ROOT/tools/dev.py" "$command_name" "$@"
