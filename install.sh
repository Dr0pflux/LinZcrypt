#!/usr/bin/env bash
#
# install.sh - install dependencies and build AZdecrypt on any Linux distribution
#
# Usage:
#   ./install.sh              detect distro, install deps, build, install to ~/.local
#   ./install.sh --deps-only  install dependencies, do not build
#   ./install.sh --build-only skip dependency installation
#   ./install.sh --system     install to /usr/local instead of ~/.local
#   ./install.sh --no-install build only, do not install anywhere
#   ./install.sh --yes        do not prompt before installing packages
#   ./install.sh --check      only verify the environment, change nothing
#   ./install.sh --help       show this message
#
set -euo pipefail

#-----------------------------------------------------------------------------
# Output helpers. Colour only when stdout is a terminal.
#-----------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RED=$(tput setaf 1); C_GRN=$(tput setaf 2); C_YEL=$(tput setaf 3)
    C_BLU=$(tput setaf 4); C_BLD=$(tput bold);    C_RST=$(tput sgr0)
else
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_BLD=""; C_RST=""
fi

info()  { printf '%s==>%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()   { printf '%serror%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
step()  { printf '\n%s%s%s\n' "$C_BLD" "$*" "$C_RST"; }

#-----------------------------------------------------------------------------
# Options
#-----------------------------------------------------------------------------
DO_DEPS=1
DO_BUILD=1
DO_INSTALL=1
ASSUME_YES=0
CHECK_ONLY=0
PREFIX="${HOME}/.local"

while [ $# -gt 0 ]; do
    case "$1" in
        --deps-only)  DO_BUILD=0; DO_INSTALL=0 ;;
        --build-only) DO_DEPS=0 ;;
        --no-install) DO_INSTALL=0 ;;
        --system)     PREFIX="/usr/local" ;;
        --prefix=*)   PREFIX="${1#*=}" ;;
        --yes|-y)     ASSUME_YES=1 ;;
        --check)      DO_DEPS=0; DO_BUILD=0; DO_INSTALL=0; CHECK_ONLY=1 ;;
        --help|-h)
            sed -n '3,14p' "$0" | sed 's/^#$//; s/^# \{0,1\}//'
            exit 0
            ;;
        *) die "unknown option: $1  (try --help)" ;;
    esac
    shift
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#-----------------------------------------------------------------------------
# Privilege escalation: use sudo only if we are not already root.
#-----------------------------------------------------------------------------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    fi
fi

run_priv() {
    if [ -n "$SUDO" ]; then
        $SUDO "$@"
    else
        "$@"
    fi
}

#-----------------------------------------------------------------------------
# Distribution detection
#
# Prefer ID_LIKE so derivatives (Mint, Pop, Manjaro, EndeavourOS, Rocky, ...)
# resolve to their parent family without needing an entry each.
#-----------------------------------------------------------------------------
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_NAME="unknown"

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    # shellcheck disable=SC2034  # kept for diagnostics/future use
    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
fi

# Package manager is the real decider; os-release is only a hint.
PKG_MGR=""
for c in apt-get dnf yum pacman zypper apk xbps-install emerge eopkg nix-env; do
    if command -v "$c" >/dev/null 2>&1; then
        PKG_MGR="$c"
        break
    fi
done

FAMILY="unknown"
case "$PKG_MGR" in
    apt-get)      FAMILY="debian" ;;
    dnf|yum)      FAMILY="fedora" ;;
    pacman)       FAMILY="arch" ;;
    zypper)       FAMILY="suse" ;;
    apk)          FAMILY="alpine" ;;
    xbps-install) FAMILY="void" ;;
    emerge)       FAMILY="gentoo" ;;
    eopkg)        FAMILY="solus" ;;
    nix-env)      FAMILY="nix" ;;
esac

#-----------------------------------------------------------------------------
# Package name tables per family.
#
# FreeBASIC is deliberately excluded here: only a few distros package it, so it
# is handled separately by install_freebasic().
#-----------------------------------------------------------------------------
pkgs_for_family() {
    case "$1" in
        debian) echo "build-essential pkg-config libgtk-3-dev zlib1g-dev libjemalloc-dev libncurses-dev libx11-dev libxext-dev libxrender-dev libxrandr-dev libxpm-dev" ;;
        fedora) echo "gcc gcc-c++ make pkgconf-pkg-config gtk3-devel zlib-devel jemalloc-devel ncurses-devel libX11-devel libXext-devel libXrender-devel libXrandr-devel libXpm-devel" ;;
        arch)   echo "base-devel pkgconf gtk3 zlib jemalloc ncurses libx11 libxext libxrender libxrandr libxpm" ;;
        suse)   echo "gcc gcc-c++ make pkg-config gtk3-devel zlib-devel jemalloc-devel ncurses-devel libX11-devel libXext-devel libXrender-devel libXrandr-devel libXpm-devel" ;;
        alpine) echo "build-base pkgconf gtk+3.0-dev zlib-dev jemalloc-dev ncurses-dev libx11-dev libxext-dev libxrender-dev libxrandr-dev libxpm-dev" ;;
        void)   echo "base-devel pkg-config gtk+3-devel zlib-devel jemalloc-devel ncurses-devel libX11-devel libXext-devel libXrender-devel libXrandr-devel libXpm-devel" ;;
        gentoo) echo "x11-libs/gtk+ sys-libs/zlib dev-libs/jemalloc sys-libs/ncurses x11-libs/libX11 x11-libs/libXext x11-libs/libXrender x11-libs/libXrandr x11-libs/libXpm" ;;
        solus)  echo "-c system.devel libgtk-3-devel zlib-devel jemalloc-devel ncurses-devel libx11-devel libxext-devel libxrender-devel libxrandr-devel libxpm-devel" ;;
        *)      echo "" ;;
    esac
}

install_packages() {
    local pkgs="$1"
    [ -z "$pkgs" ] && return 0

    info "Packages to install:"
    printf '     %s\n' "$pkgs"

    if [ "$ASSUME_YES" -eq 0 ]; then
        printf 'Proceed? [Y/n] '
        read -r reply </dev/tty || reply="y"
        case "$reply" in
            [nN]*) warn "skipping dependency installation"; return 0 ;;
        esac
    fi

    # shellcheck disable=SC2086
    case "$PKG_MGR" in
        apt-get)
            run_priv apt-get update
            run_priv apt-get install -y $pkgs
            ;;
        dnf)          run_priv dnf install -y $pkgs ;;
        yum)          run_priv yum install -y $pkgs ;;
        pacman)       run_priv pacman -Sy --needed --noconfirm $pkgs ;;
        zypper)       run_priv zypper --non-interactive install $pkgs ;;
        apk)          run_priv apk add --no-cache $pkgs ;;
        xbps-install) run_priv xbps-install -Sy $pkgs ;;
        emerge)       run_priv emerge --noreplace $pkgs ;;
        eopkg)        run_priv eopkg install -y $pkgs ;;
        *) warn "no supported package manager found; install manually: $pkgs"; return 1 ;;
    esac
}

#-----------------------------------------------------------------------------
# FreeBASIC
#
# Packaged on Arch (AUR), Void, Gentoo and a few others, but not on Debian,
# Ubuntu or Fedora. Where it is missing we point at the upstream tarball rather
# than silently failing, because building fbc from source is a long detour.
#-----------------------------------------------------------------------------
FBC_MIN_MAJOR=1
FBC_MIN_MINOR=10

fbc_version_ok() {
    command -v fbc >/dev/null 2>&1 || return 1
    local v major minor
    v="$(fbc -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    [ -z "$v" ] && return 1
    major="${v%%.*}"
    minor="${v#*.}"; minor="${minor%%.*}"
    if [ "$major" -gt "$FBC_MIN_MAJOR" ]; then return 0; fi
    if [ "$major" -eq "$FBC_MIN_MAJOR" ] && [ "$minor" -ge "$FBC_MIN_MINOR" ]; then return 0; fi
    return 1
}

install_freebasic() {
    if fbc_version_ok; then
        ok "FreeBASIC $(fbc -version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1) already present"
        return 0
    fi

    if command -v fbc >/dev/null 2>&1; then
        warn "FreeBASIC found but older than ${FBC_MIN_MAJOR}.${FBC_MIN_MINOR}; a newer version is recommended"
    fi

    case "$FAMILY" in
        arch)
            info "FreeBASIC is in the AUR. Trying an AUR helper..."
            for h in yay paru pikaur trizen; do
                if command -v "$h" >/dev/null 2>&1; then
                    "$h" -S --needed --noconfirm freebasic && return 0
                fi
            done
            warn "no AUR helper found. Install manually:  yay -S freebasic"
            ;;
        void)
            run_priv xbps-install -Sy freebasic && return 0
            ;;
        gentoo)
            run_priv emerge --noreplace dev-lang/fbc && return 0
            ;;
        alpine)
            warn "FreeBASIC is not in Alpine repos and upstream builds are glibc-linked."
            warn "Alpine (musl) requires building fbc from source."
            ;;
    esac

    cat <<EOF

${C_YEL}FreeBASIC is not available from your package manager.${C_RST}

Install it manually, then re-run this script with --build-only:

  1. Download the 64-bit Linux binary from:
       https://www.freebasic.net/get
     (choose "FreeBASIC-1.10.x-linux-x86_64.tar.gz" or newer)

  2. Extract and install:
       tar xf FreeBASIC-*-linux-x86_64.tar.gz
       cd FreeBASIC-*-linux-x86_64
       sudo ./install.sh -i

  3. Verify:
       fbc -version

EOF
    return 1
}

#-----------------------------------------------------------------------------
# Verification
#-----------------------------------------------------------------------------
have_lib() {
    # Try pkg-config first, then the linker, then ldconfig. Any one suffices.
    local pc="$1" lib="$2"
    if [ -n "$pc" ] && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$pc"; then
        return 0
    fi
    if command -v cc >/dev/null 2>&1; then
        if echo 'int main(void){return 0;}' | cc -x c - -o /dev/null "-l$lib" >/dev/null 2>&1; then
            return 0
        fi
    fi
    if command -v ldconfig >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -q "lib$lib\.so"; then
        return 0
    fi
    return 1
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------
step "AZdecrypt installer"
info "Distribution : $DISTRO_NAME"
info "Family       : $FAMILY${DISTRO_LIKE:+  (ID_LIKE: $DISTRO_LIKE)}"
info "Package mgr  : ${PKG_MGR:-none found}"
info "Prefix       : $PREFIX"

if [ "$FAMILY" = "unknown" ]; then
    warn "unrecognised distribution; dependency installation will be skipped."
    warn "You need: a C toolchain, pkg-config, GTK3 dev files, zlib dev files, FreeBASIC >= 1.10."
    DO_DEPS=0
fi

if [ "$DO_DEPS" -eq 1 ]; then
    step "1. Installing system dependencies"
    install_packages "$(pkgs_for_family "$FAMILY")" || warn "some packages may have failed"

    step "2. Installing FreeBASIC"
    if ! install_freebasic; then
        die "FreeBASIC is required. Install it and re-run with --build-only."
    fi
fi

step "3. Verifying build environment"

MISSING=0
if fbc_version_ok; then
    ok "fbc $(fbc -version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
elif command -v fbc >/dev/null 2>&1; then
    warn "fbc present but version could not be confirmed >= ${FBC_MIN_MAJOR}.${FBC_MIN_MINOR}"
else
    warn "fbc not found"; MISSING=1
fi

if command -v pkg-config >/dev/null 2>&1; then ok "pkg-config"; else warn "pkg-config not found"; MISSING=1; fi

if have_lib "gtk+-3.0" "gtk-3"; then ok "GTK3"; else warn "GTK3 development files not found"; MISSING=1; fi
if have_lib "zlib" "z";          then ok "zlib"; else warn "zlib development files not found"; MISSING=1; fi
if have_lib "" "jemalloc";       then ok "jemalloc (optional)"; else info "jemalloc not found - will build without it"; fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ "$MISSING" -ne 0 ]; then
        die "environment is NOT ready (see warnings above)"
    fi
    ok "environment is ready to build"
    exit 0
fi

if [ "$MISSING" -ne 0 ]; then
    die "missing required dependencies (see warnings above)"
fi

if [ "$DO_BUILD" -eq 1 ]; then
    step "4. Building"
    ./build.sh
    [ -x ./AZdecrypt ] || die "build did not produce ./AZdecrypt"
    ok "built ./AZdecrypt"
fi

if [ "$DO_INSTALL" -eq 1 ] && [ -x ./AZdecrypt ]; then
    step "5. Installing to $PREFIX"

    BIN_DIR="$PREFIX/bin"
    DATA_DIR="$PREFIX/share/azdecrypt"
    APP_DIR="$PREFIX/share/applications"

    # Writing under /usr or /usr/local needs privileges; a home prefix does not.
    NEED_PRIV=0
    case "$PREFIX" in
        /usr|/usr/*|/opt|/opt/*) NEED_PRIV=1 ;;
    esac
    if [ ! -w "$(dirname "$PREFIX")" ] && [ ! -w "$PREFIX" ] 2>/dev/null; then
        NEED_PRIV=1
    fi

    inst() {
        if [ "$NEED_PRIV" -eq 1 ]; then
            run_priv "$@"
        else
            "$@"
        fi
    }

    inst mkdir -p "$BIN_DIR" "$DATA_DIR" "$APP_DIR"
    inst cp AZdecrypt "$DATA_DIR/AZdecrypt"
    inst chmod 0755 "$DATA_DIR/AZdecrypt"

    # Data directories the program expects in its working directory.
    for d in Ciphers Output Misc N-grams; do
        inst mkdir -p "$DATA_DIR/$d"
    done

    # Launcher: run from the data directory so relative paths resolve, but let
    # the user override with AZDECRYPT_HOME.
    LAUNCHER="$(mktemp)"
    cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# AZdecrypt launcher
AZDECRYPT_HOME="\${AZDECRYPT_HOME:-\$HOME/.local/share/azdecrypt}"
if [ ! -d "\$AZDECRYPT_HOME" ]; then
    AZDECRYPT_HOME="$DATA_DIR"
fi
for d in Ciphers Output Misc N-grams; do
    mkdir -p "\$AZDECRYPT_HOME/\$d"
done
cd "\$AZDECRYPT_HOME" || exit 1
exec "$DATA_DIR/AZdecrypt" "\$@"
EOF
    inst cp "$LAUNCHER" "$BIN_DIR/azdecrypt"
    inst chmod 0755 "$BIN_DIR/azdecrypt"
    rm -f "$LAUNCHER"

    # Desktop entry
    DESKTOP="$(mktemp)"
    cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=AZdecrypt
GenericName=Cipher Solver
Comment=Cryptanalysis tool for substitution and transposition ciphers
Exec=$BIN_DIR/azdecrypt
Terminal=false
Categories=Utility;
Keywords=cipher;cryptanalysis;zodiac;cicada;runes;
EOF
    inst cp "$DESKTOP" "$APP_DIR/azdecrypt.desktop"
    inst chmod 0644 "$APP_DIR/azdecrypt.desktop"
    rm -f "$DESKTOP"

    ok "installed"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            warn "$BIN_DIR is not on your PATH."
            warn "Add this to your ~/.bashrc or ~/.zshrc:"
            # shellcheck disable=SC2016  # $PATH must stay literal in the printed advice
            printf '\n    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
            ;;
    esac
fi

step "Done"
cat <<EOF
Run it with:
    azdecrypt              (if $PREFIX/bin is on your PATH)
    ./AZdecrypt            (directly from this directory)

N-gram files are not bundled. Copy them from a Windows AZdecrypt install into:
    ${DATA_DIR:-$PWD/N-grams}

They are plain .txt/.gz and are platform-neutral.
EOF
