# Installing AZdecrypt on Linux

## Quick start

```bash
tar xf azdecrypt-linux-cicada.tar.gz
cd azdecrypt-linux
./install.sh
```

That detects your distribution, installs dependencies, builds, and installs to
`~/.local`. Then run:

```bash
azdecrypt
```

If `azdecrypt` isn't found, add `~/.local/bin` to your `PATH` (the installer
tells you exactly what to paste).

---

## What the installer does

1. Detects your package manager (not just the distro name, so derivatives work).
2. Installs build tools, GTK3, zlib and jemalloc.
3. Installs FreeBASIC, or tells you how if your distro doesn't package it.
4. Verifies everything is present.
5. Builds.
6. Installs the binary, a launcher, and a desktop menu entry.

Nothing is written outside your chosen prefix.

### Options

| Flag | Effect |
|---|---|
| `--check` | Verify the environment; change nothing |
| `--deps-only` | Install dependencies, don't build |
| `--build-only` | Skip dependency install (they're already there) |
| `--no-install` | Build in place, don't install |
| `--system` | Install to `/usr/local` instead of `~/.local` |
| `--prefix=DIR` | Install somewhere specific |
| `--yes` | Don't prompt before installing packages |

---

## Supported distributions

Detected automatically via package manager:

| Family | Distributions | Package manager |
|---|---|---|
| Debian | Debian, Ubuntu, Mint, Pop!\_OS, elementary, Kali, Raspberry Pi OS, MX | `apt-get` |
| Fedora | Fedora, RHEL, CentOS, Rocky, Alma, Nobara | `dnf` / `yum` |
| Arch | Arch, Manjaro, EndeavourOS, Garuda, CachyOS | `pacman` |
| SUSE | openSUSE Leap, Tumbleweed, SLES | `zypper` |
| Alpine | Alpine | `apk` |
| Void | Void | `xbps-install` |
| Gentoo | Gentoo, Funtoo | `emerge` |
| Solus | Solus | `eopkg` |

Derivatives work without needing their own entry, because detection keys off the
package manager rather than the distro name.

**Unlisted distro?** The installer skips dependency installation and tells you
what to install by hand. Everything after that still works.

---

## The FreeBASIC catch

FreeBASIC is the one dependency most distros don't package.

| Distro | Availability |
|---|---|
| Arch | AUR — installer uses `yay`/`paru` if present |
| Void, Gentoo | In the official repositories |
| Debian, Ubuntu, Fedora, openSUSE | **Not packaged — manual install** |
| Alpine | Not packaged; musl needs a source build |

Manual install takes about a minute:

```bash
# from https://www.freebasic.net/get - pick the 64-bit Linux build
tar xf FreeBASIC-1.10.1-linux-x86_64.tar.gz
cd FreeBASIC-1.10.1-linux-x86_64
sudo ./install.sh -i
fbc -version          # verify

# then, back in the azdecrypt directory:
./install.sh --build-only
```

---

## Manual dependency install

If you'd rather not let the script touch your package manager:

```bash
# Debian / Ubuntu / Mint / Pop!_OS
sudo apt install build-essential pkg-config libgtk-3-dev zlib1g-dev \
                 libjemalloc-dev libncurses-dev libx11-dev libxext-dev \
                 libxrender-dev libxrandr-dev libxpm-dev

# Fedora / RHEL / Rocky / Alma
sudo dnf install gcc gcc-c++ make pkgconf-pkg-config gtk3-devel zlib-devel \
                 jemalloc-devel ncurses-devel libX11-devel libXext-devel \
                 libXrender-devel libXrandr-devel libXpm-devel

# Arch / Manjaro / EndeavourOS
sudo pacman -S base-devel pkgconf gtk3 zlib jemalloc ncurses libx11 \
               libxext libxrender libxrandr libxpm

# openSUSE
sudo zypper install gcc gcc-c++ make pkg-config gtk3-devel zlib-devel \
                    jemalloc-devel ncurses-devel libX11-devel libXext-devel \
                    libXrender-devel libXrandr-devel libXpm-devel

# Alpine
sudo apk add build-base pkgconf gtk+3.0-dev zlib-dev jemalloc-dev \
             ncurses-dev libx11-dev libxext-dev libxrender-dev \
             libxrandr-dev libxpm-dev

# Void
sudo xbps-install base-devel pkg-config gtk+3-devel zlib-devel \
                  jemalloc-devel ncurses-devel libX11-devel libXext-devel \
                  libXrender-devel libXrandr-devel libXpm-devel
```

Then `./build.sh`.

---

## Build modes

```bash
./build.sh              # optimised, tuned to this machine (-march=native)
./build.sh portable     # optimised, generic - use if sharing the binary
./build.sh debug        # bounds checking, slow, for diagnosing crashes
./build.sh nojemalloc   # skip jemalloc
```

Overrides:

```bash
FBC=/opt/fbc/bin/fbc ./build.sh        # specific compiler
EXTRA_FBFLAGS="-v" ./build.sh          # extra flags
```

`-march=native` is only used if your compiler accepts it, and it's skipped
automatically otherwise. Use `portable` if the binary will run on a different
machine than it was built on.

---

## N-gram files

**Not bundled** — they're large, and they're identical across platforms.

Copy them from a Windows AZdecrypt install into `~/.local/share/azdecrypt/N-grams/`.
Plain `.txt`/`.gz`; no conversion needed. The same goes for `Ciphers/` and `Misc/`.

---

## Running

```bash
azdecrypt                      # via launcher
./AZdecrypt                    # directly from the build directory
```

Or from your desktop's application menu.

Data lives in `~/.local/share/azdecrypt/` by default. Override with:

```bash
AZDECRYPT_HOME=/path/to/data azdecrypt
```

---

## Uninstalling

```bash
./uninstall.sh                 # remove program, keep your data
./uninstall.sh --purge         # remove everything
./uninstall.sh --system        # if installed with --system
```

---

## Troubleshooting

**`fbc: command not found`** — FreeBASIC isn't installed. See the section above.

**`GTK3 development files not found`** — you have GTK3's runtime but not its
headers. Install the `-dev` / `-devel` package.

**Compile errors** — expected on first build; this port has never been through a
compiler (see `README-LINUX.md`). Paste the errors and they're usually quick fixes.

**Program starts but the window is blank or controls overlap** — the port uses
absolute Win32 pixel coordinates, so font differences can misalign things. Cosmetic.

**Radio buttons behave as one group** — known risk, documented in
`README-LINUX.md`. GTK groups radio buttons explicitly where Win32 does it
implicitly.

**Out of memory on a 32-bit system** — AZdecrypt allocates large n-gram tables.
Use 64-bit.

**Check your environment without changing anything:**

```bash
./install.sh --check
```
