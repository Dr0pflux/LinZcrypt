#!/usr/bin/env bash
#
# uninstall.sh - remove an installed AZdecrypt
#
# Usage:
#   ./uninstall.sh              remove from ~/.local
#   ./uninstall.sh --system     remove from /usr/local
#   ./uninstall.sh --prefix=DIR remove from a custom prefix
#   ./uninstall.sh --purge      also delete Ciphers/Output/Misc/N-grams data
#
set -euo pipefail

PREFIX="${HOME}/.local"
PURGE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --system)   PREFIX="/usr/local" ;;
        --prefix=*) PREFIX="${1#*=}" ;;
        --purge)    PURGE=1 ;;
        --help|-h)  sed -n '3,10p' "$0" | sed 's/^#$//; s/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
    elif command -v doas >/dev/null 2>&1; then SUDO="doas"
    fi
fi

NEED_PRIV=0
case "$PREFIX" in
    /usr|/usr/*|/opt|/opt/*) NEED_PRIV=1 ;;
esac

rm_path() {
    local p="$1"
    [ -e "$p" ] || return 0
    if [ "$NEED_PRIV" -eq 1 ] && [ -n "$SUDO" ]; then
        $SUDO rm -rf "$p"
    else
        rm -rf "$p"
    fi
    printf '  removed %s\n' "$p"
}

BIN="$PREFIX/bin/azdecrypt"
DATA="$PREFIX/share/azdecrypt"
DESK="$PREFIX/share/applications/azdecrypt.desktop"

printf 'Removing AZdecrypt from %s\n' "$PREFIX"

rm_path "$BIN"
rm_path "$DESK"

if [ "$PURGE" -eq 1 ]; then
    rm_path "$DATA"
    # The launcher may also have created a per-user data directory.
    if [ -d "$HOME/.local/share/azdecrypt" ] && [ "$DATA" != "$HOME/.local/share/azdecrypt" ]; then
        rm_path "$HOME/.local/share/azdecrypt"
    fi
else
    rm_path "$DATA/AZdecrypt"
    if [ -d "$DATA" ]; then
        printf '\nKept your data in %s\n' "$DATA"
        printf 'Remove it with:  ./uninstall.sh --purge%s\n' \
               "$([ "$PREFIX" = "/usr/local" ] && printf ' --system' || printf '')"
    fi
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
fi

printf '\nDone.\n'
