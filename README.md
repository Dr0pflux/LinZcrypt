# LinZcrypt

A native Linux rewrite of [AZdecrypt](http://www.zodiackillerciphers.com/wiki/index.php?title=AZdecrypt), Jarlve's homophonic substitution solver, in Rust, with the Cicada 3301 / Liber Primus tooling from the FreeBASIC port carried over.

This replaces the earlier FreeBASIC/GTK port. Same solvers, same statistics, same n-gram files, same output format — new code underneath.

## Install

Unzip `LinZcrypt-<version>-Linux.zip`, open the folder, double-click **LinZcrypt Setup**.

The wizard looks at the machine (distro, CPU, glibc, package manager, admin rights, whether the window libraries are there), then asks two things: install for just you (`~/.local`, no password) or for everyone (`/opt/linzcrypt`, asks for the admin password), and where the data folder goes (default `~/LinZcrypt`). It adds a menu entry, optionally a desktop icon, puts `linzcrypt` on your PATH, and offers to install any missing window libraries through your package manager.

Run it again to update or uninstall. Your data folder is never touched by either.

If double-clicking opens a text editor or does nothing, the file lost its executable bit somewhere along the way: right-click → Properties → Permissions → *Allow executing file as program*, or run `./"LinZcrypt Setup"` from a terminal.

Other ways in:

| Command | What it does |
|---|---|
| `sh install.sh` | Same install, in the terminal. Use this on ARM / Raspberry Pi: it builds from the bundled source and offers to install Rust if it's missing |
| `./"LinZcrypt Setup" --yes` | No questions, recommended choices |
| `./"LinZcrypt Setup" --uninstall` | Remove it |
| `./"LinZcrypt Setup" --text` | Terminal wizard even on a desktop |

The ready-made binary is x86_64 and needs glibc 2.17 or newer, which is any distro from the last decade.

## Why

The FreeBASIC port worked, but not well. Features were half-wired, a fair number of menu items did nothing or the wrong thing, and every fix meant fighting a GTK shim pretending to be Win32. Rather than keep patching it, everything was ported again — solver by solver, statistic by statistic, against the original source — into a language with real threads and a real type system.

## Build from source

```bash
cd source
cargo build --release            # target/release/linzcrypt
packaging/build-bundle.sh dist   # rebuild the installer zip (needs cargo-zigbuild)
```

Rust 1.85 or newer. No system libraries are needed at build time; at run time the window needs OpenGL, libxkbcommon and X11 or Wayland, which every desktop already has.

## What's in it

### Solvers

Substitution, plus every variant in the original list: columnar rearrangement, columnar transposition, crib grid, crib list, monoalphabetic groups, nulls and skips, polyphones (user / extra letters / Hafer), row bound, row bound fragments, sequential homophones, simple transposition, sparse polyalphabetism, units, verbose, Vigenère, Vigenère word list.

Non-substitution: columnar transposition and rearrangement, row and grid rearrangement, double columnar, periodic transposition (fixed, auto, inverted auto), nulls and skips, simple transposition, multiple Caesar shifts, manual polyalphabetic.

Also bigram substitution, higher-order homophonic, merge sequential homophones, find words, batch ciphers / n-grams / settings, and the benchmark.

### Statistics

All of them: unigrams, n-grams, patterns, contacts, chi², observations, encoding, alphabets, Hafer shifts, keyword length, transposition matrix, find rearrangement, omnidirectional, periodic, encoding randomization, cycle patterns / types / perfect cycles, all 40 plaintext-and-encoding-direction measures, the compare tools (equality, key mapping, Kasiski, subset chi²), and the output graphs (BMP, same as the original).

### Combine

The full Combine window: all 38 operations, arguments A1–A6, transposed / untransposed, additive / multiplicative stacks, every measurement including *Solve substitution*, normalised scores, sigma, length and raw IOC ranges, and the list / heatmap / hypergraph outputs.

### N-grams

The default letter n-gram system (2–7, text or binary, gzipped or not), plus the systems the FreeBASIC port never loaded: beijinghouse 6/8/10/12-grams with their `_table` files, the memory limit and 8-gram caching; neural-network 4-grams; and word 1-gram lists. If an n-gram file has no `.ini`, one is inferred and written next to it.

Solver output is split into words when the AZdecrypt spacing files are present (`N-grams/Spaces/<language>/…`), with a word-list fallback when they aren't. The normalization text in `N-grams/N-gram normalization/` is scored on load, same as upstream.

### Cicada tooling

Three menus, same as before. **Cicada** converts (runes ↔ numbers ↔ Latin, letter-form toggles, Gematria Primus table, Liber Primus page download). **Cicada analysis** measures without modifying anything. **Cicada solve** searches for a key: Vigenère (scanned across lengths), autokey primer, free running key, and an exact enumeration of closed-form transforms. `README-CICADA.md` has the details.

They need a runeglish n-gram set — File → N-gram tools → *Compile runeglish n-grams* builds one from an English corpus.

## Command line

```bash
linzcrypt                                                   # the window
linzcrypt -n NGRAMS -c CIPHER -s "Substitution" -t 60       # solve for 60 s
          [--threads N] [--iterations N] [--set key=value]
          [--config FILE] [--list FILE] [--cribs FILE]
linzcrypt -c CIPHER --stats ID [-n NGRAMS] [--other FILE]   # e.g. dir:1, periodic:13, encrnd:2:2
linzcrypt --compile CORPUS.txt --size 5 --out 5-grams.txt
linzcrypt --cicada vig|auto|run|scan -n NGRAMS -c PAGE.txt
```

`--set` takes any key from `~/.config/linzcrypt/settings.ini`.

## Fixed along the way

Porting against the original source turned up bugs in AZdecrypt itself. Where the intent was clear they're fixed rather than copied:

- Row bound fragments' *fine tune* computed a new break position and never applied it.
- Nulls and skips with period 1 hung as soon as the shift step kicked in.
- Combine's *Encode: caesar shift* could never succeed (it always saw symbol numbers, not letters), the *171–340* homophonic encoder was mis-spelled in the dispatcher, and *Remove column* updated the length with the wrong dimension.
- Several Combine operations and measurements read past the end of the cipher on non-rectangular grids.

## Left out

Things that only existed because of FreeBASIC or Win32: the *thread wait* setting (workers don't poll), *screen size checks*, and development-only restart limits. Three options that the original hides from its own settings window are also not ported: the nulls-and-skips search depth, the bigram heatmap / auto-crib, and the bigram 6/8/10-gram factors.

## Testing

38 unit tests, plus end-to-end runs of the solvers on planted ciphers in `Ciphers/` (sample n-grams in `N-grams/`). The installer was tested by driving the wizard window on a virtual display through install, launch and uninstall, and through the terminal wizard in both scopes.

## Known issues

- The beijinghouse and neural-network loaders follow the original file layout exactly but haven't been run against real files — none were available.
- Word spacing was checked with spacing tables generated for testing, not the real AZdecrypt ones.
- The everyone-install's password prompt (pkexec / sudo) and the ARM build-from-source path haven't been exercised on real hardware.
- A hill-climber returns its best candidate whether or not one exists. Compare against other key lengths and settings before believing a result.

## Credits

AZdecrypt is by Jarlve. The solvers, the n-gram machinery, and essentially everything that makes this program good are his design. This is a port, and it carries whatever terms the original is distributed under — check with the author before redistributing.

The Gematria Primus and the Liber Primus are Cicada 3301's.
