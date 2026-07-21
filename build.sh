#!/usr/bin/env bash
#
# build.sh - build AZdecrypt for Linux (GTK3 backend)
#
# Usage:
#   ./build.sh              optimised build
#   ./build.sh debug        debug build with bounds checking
#   ./build.sh nojemalloc   build without jemalloc
#   ./build.sh portable     optimised, but no -march=native (distributable binary)
#
# Environment overrides:
#   FBC=/path/to/fbc        use a specific FreeBASIC compiler
#   EXTRA_FBFLAGS="..."     append arbitrary flags
#
set -euo pipefail

MODE="${1:-release}"
FBC="${FBC:-fbc}"

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

# Detect a library three ways: pkg-config, a real link test, then ldconfig.
# The link test is authoritative and works on musl/Alpine where ldconfig -p
# does not exist or behaves differently.
have_lib() {
    local pc="$1" lib="$2" cc
    if [ -n "$pc" ] && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$pc" 2>/dev/null; then
        return 0
    fi
    for cc in "${CC:-cc}" gcc clang; do
        if command -v "$cc" >/dev/null 2>&1; then
            if echo 'int main(void){return 0;}' | "$cc" -x c - -o /dev/null "-l$lib" >/dev/null 2>&1; then
                return 0
            fi
            break
        fi
    done
    if command -v ldconfig >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -q "lib${lib}\.so"; then
        return 0
    fi
    return 1
}

# Does the C compiler accept a given flag? Used to gate -march=native, which is
# unsupported on some architectures and some compiler builds.
cc_supports() {
    local flag="$1" cc
    for cc in "${CC:-cc}" gcc clang; do
        if command -v "$cc" >/dev/null 2>&1; then
            echo 'int main(void){return 0;}' | "$cc" -x c - -o /dev/null "$flag" >/dev/null 2>&1
            return $?
        fi
    done
    return 1
}

#-----------------------------------------------------------------------------
# Required tooling
#-----------------------------------------------------------------------------
command -v "$FBC" >/dev/null 2>&1 || die "FreeBASIC compiler '$FBC' not found.
  Install it from https://www.freebasic.net/get (need >= 1.10, 64-bit),
  or run ./install.sh which will guide you."

command -v pkg-config >/dev/null 2>&1 || die "pkg-config not found.
  Debian/Ubuntu: sudo apt install pkg-config
  Fedora:        sudo dnf install pkgconf-pkg-config
  Arch:          sudo pacman -S pkgconf
  Alpine:        sudo apk add pkgconf"

pkg-config --exists gtk+-3.0 2>/dev/null || die "GTK3 development files not found.
  Debian/Ubuntu: sudo apt install libgtk-3-dev
  Fedora:        sudo dnf install gtk3-devel
  Arch:          sudo pacman -S gtk3
  openSUSE:      sudo zypper install gtk3-devel
  Alpine:        sudo apk add gtk+3.0-dev
  Void:          sudo xbps-install gtk+3-devel"

have_lib "zlib" "z" || die "zlib development files not found.
  Debian/Ubuntu: sudo apt install zlib1g-dev
  Fedora:        sudo dnf install zlib-devel
  Arch:          sudo pacman -S zlib
  Alpine:        sudo apk add zlib-dev"

HAVE_JEMALLOC=0
if have_lib "jemalloc" "jemalloc"; then
    HAVE_JEMALLOC=1
fi

#-----------------------------------------------------------------------------
# Architecture sanity
#
# The solver is written for 64-bit. A 32-bit fbc will compile but the large
# n-gram tables can exhaust the address space at runtime.
#-----------------------------------------------------------------------------
ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$ARCH" in
    x86_64|amd64|aarch64|arm64|ppc64le|riscv64|s390x) ;;
    i?86|armv7l|armhf)
        printf 'warning: %s is a 32-bit target.\n' "$ARCH" >&2
        printf '         AZdecrypt allocates large n-gram tables and may run out of\n' >&2
        printf '         address space. A 64-bit system is strongly recommended.\n\n' >&2
        ;;
    *) printf 'warning: unrecognised architecture %s; proceeding anyway.\n\n' "$ARCH" >&2 ;;
esac

#-----------------------------------------------------------------------------
# Flags
#-----------------------------------------------------------------------------
FBFLAGS=( -m AZdecrypt )   # AZdecrypt.bas holds the main entry point
FBFLAGS+=( -mt )           # multithreaded runtime; the solver spawns threads
FBFLAGS+=( -w all )

case "$MODE" in
    release)
        FBFLAGS+=( -O 3 )
        if cc_supports "-march=native"; then
            FBFLAGS+=( -Wc -march=native )
            note "using -march=native (binary tuned to THIS machine)"
        else
            note "-march=native unsupported here; building generic"
        fi
        ;;
    portable)
        FBFLAGS+=( -O 3 )
        note "portable build: no -march=native"
        ;;
    debug)
        FBFLAGS+=( -g -exx )
        note "debug build: bounds checking enabled, slow"
        ;;
    nojemalloc)
        FBFLAGS+=( -O 3 )
        HAVE_JEMALLOC=0
        ;;
    *)
        die "unknown mode '$MODE' (use release, portable, debug or nojemalloc)"
        ;;
esac

FBFLAGS+=( -l z )

if [ "$HAVE_JEMALLOC" -eq 1 ]; then
    FBFLAGS+=( -l jemalloc )
    note "linking jemalloc"
else
    FBFLAGS+=( -d AZ_NO_JEMALLOC )
    note "building without jemalloc (glibc malloc will be used)"
    note "for better multithreaded performance, install libjemalloc-dev"
fi

# GTK include and link flags, straight from pkg-config.
while IFS= read -r f; do
    case "$f" in
        -I*) FBFLAGS+=( -i "${f#-I}" ) ;;
    esac
done < <(pkg-config --cflags gtk+-3.0 | tr ' ' '\n')

while IFS= read -r f; do
    case "$f" in
        -l*) FBFLAGS+=( -l "${f#-l}" ) ;;
        -L*) FBFLAGS+=( -p "${f#-L}" ) ;;
    esac
done < <(pkg-config --libs gtk+-3.0 | tr ' ' '\n')

# Caller-supplied extras.
if [ -n "${EXTRA_FBFLAGS:-}" ]; then
    # shellcheck disable=SC2206  # deliberate word splitting of user-supplied flags
    EXTRA=( ${EXTRA_FBFLAGS} )
    FBFLAGS+=( "${EXTRA[@]}" )
fi

#-----------------------------------------------------------------------------
# Build
#-----------------------------------------------------------------------------
printf '\nBuilding AZdecrypt (mode: %s, arch: %s)\n' "$MODE" "$ARCH"
printf '%s %s AZdecrypt.bas\n\n' "$FBC" "${FBFLAGS[*]}"

"$FBC" "${FBFLAGS[@]}" AZdecrypt.bas

[ -x ./AZdecrypt ] || die "compilation finished but ./AZdecrypt was not produced"

printf '\nBuild complete: ./AZdecrypt\n\n'
printf 'Runtime layout (created automatically on first run):\n'
printf '  ./Ciphers/   ./Output/   ./Misc/   ./N-grams/\n\n'
printf 'N-gram files are not bundled. Copy them from a Windows install into ./N-grams/\n'
printf 'They are plain .txt/.gz and platform-neutral.\n'
