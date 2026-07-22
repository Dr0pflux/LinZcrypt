# AZdecrypt for Linux

A Linux/GTK3 port of Jarlve's [AZdecrypt](https://www.zodiackillerciphers.com/wiki/index.php?title=AZdecrypt),
a fast cryptanalysis tool for substitution and transposition ciphers, with added
tooling for Cicada 3301 / Liber Primus runic ciphers.

The full GUI is preserved. The solver and all of AZdecrypt's original
functionality are unchanged.

- **Installing:** see [INSTALL.md](INSTALL.md) — per-distribution instructions.
- **Cicada / Liber Primus features:** see [README-CICADA.md](README-CICADA.md).

## Quick build

```bash
./build.sh portable
./AZdecrypt
```

You need FreeBASIC (≥ 1.10, 64-bit), GTK3, and zlib. INSTALL.md covers getting
these on every major distribution.

## Runtime layout

AZdecrypt works from a directory containing `Ciphers/`, `Output/`, `Misc/`, and
`N-grams/`, created automatically on first launch.

**N-gram files are not bundled** — they're large and identical across platforms.
Copy them from a Windows AZdecrypt install into `N-grams/`. They're plain
`.txt`/`.gz` and need no conversion. The same applies to `Ciphers/` and `Misc/`.

Without n-grams the solver reports `Error: file not found`; the rest of the
program still works.

## How the port works

AZdecrypt never calls Win32 directly — every GUI operation goes through a `ui_*`
wrapper. The port implements those wrappers against GTK3 in three new files, and
leaves the ~63,000 lines of application and solver code untouched.

| File | Purpose |
|---|---|
| `gtk_backend.bi` | Event-loop bridge, window registry, signal handlers, global styling |
| `gtk_widgets.bi` | GTK implementations of the widget primitives |
| `ui_specific.bi` | The `ui_*` layer: Windows branches call Win32, Linux branches call GTK |

The one non-trivial piece is the event loop. AZdecrypt pulls messages
(`getmessage` in a loop); GTK pushes them (signals/callbacks). The bridge inverts
this: GTK signal handlers enqueue synthetic message records onto a mutex-guarded
ring buffer, and the Linux `getmessage` drains that queue. The application's
dispatch logic runs unchanged on both platforms.

Changes to `AZdecrypt.bas` are all platform-conditional: the main loop feeds from
the GTK bridge on Linux, CPU-core detection uses `sysconf` instead of x86 `cpuid`,
the Windows-only jemalloc/shlobj includes are guarded, and path separators use a
`PSEP` constant.

## Build modes

```bash
./build.sh              # optimised, tuned to this machine (-march=native)
./build.sh portable     # optimised, generic — use if sharing the binary
./build.sh debug        # bounds checking, for diagnosing crashes
./build.sh nojemalloc   # skip jemalloc
```

`portable` compiles faster and avoids CPU-specific vectorization warnings; it's
the recommended default unless you're squeezing out solver speed on one machine.

## Notes and limitations

- **Fixed layout.** AZdecrypt positions every control at absolute pixel
  coordinates — it doesn't reflow, on Windows or here. Maximizing the window shows
  empty space because there's nothing to stretch. This is the application's design.

- **Radio-button grouping.** GTK groups radio buttons explicitly where Win32 does
  it implicitly. Grouping is reconstructed from creation order; if a window's radio
  sets ever behave as one group, that's the place to look.

- **Menu check marks** render as a `*` prefix on the label, since `GtkMenuItem`
  has no native check state.

- **"Open output folder"** is not wired up on Linux (it was a Win32 shell call).

## Credit

Original AZdecrypt by Jarlve. This port and the Cicada tooling are independent
additions.
