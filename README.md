# azdecrypt-linux

A Linux port of [AZdecrypt](http://www.zodiackillerciphers.com/wiki/index.php?title=AZdecrypt), Jarlve's homophonic substitution solver, with a set of additions for working on Cicada 3301 / Liber Primus material.

The solver itself is untouched. All the changes are in the platform layer (Win32 → GTK3) and in new code that sits alongside the original.

## Why

AZdecrypt is the best homophonic substitution solver anyone has published, and it's Windows-only. Wine works, badly — the UI is sluggish and threading behaves oddly. This is a native build instead.

The Cicada parts came later, because once you have a 29-symbol solver running natively it's annoying to keep transcribing runes by hand.

## Requirements

- FreeBASIC 1.08 or newer (1.10.x recommended)
- GTK 3, zlib
- jemalloc (optional but wanted — glibc's allocator is noticeably worse with many solver threads)

On Debian/Ubuntu:

```bash
sudo apt install libgtk-3-dev zlib1g-dev libjemalloc-dev
```

FreeBASIC isn't packaged by most distros. `INSTALL.md` walks through building it from source; it takes about ten minutes.

## Build

```bash
./build.sh              # optimised for this machine
./AZdecrypt
```

Other modes:

| Mode | What it does |
|---|---|
| `./build.sh portable` | No `-arch native`, so the binary runs on other CPUs |
| `./build.sh debug` | Bounds checking, no optimisation. Slow, but it tells you where things break |
| `./build.sh nojemalloc` | Skip jemalloc even if it's installed |
| `./build.sh menutest` | Diagnostic build — see below |

The build prints whether it linked jemalloc and whether native tuning applied. Worth glancing at.

`./install.sh` puts it in `~/.local/share` with a desktop entry. `./uninstall.sh` reverses that. Neither is required — running from the source directory is fine.

## What's different from upstream

### The port

Win32 calls go through a shim in `ui_specific.bi` that maps onto GTK 3. Windows-only bits (jemalloc's Windows headers, `shlobj.h`) are `#ifdef`'d out, path separators are handled per-platform, and CPU core detection uses `sysconf` rather than `cpuid`.

Worker threads can't touch GTK directly, so UI updates from the solver go through a queue that the main loop drains.

### Performance

The first working port was much slower than the Windows build. Four things caused it, all in the platform layer:

The codebase is full of `do : sleep 0.001 : loop until <flag>` busy-waits. On Windows FreeBASIC's `SLEEP` ends in `Sleep(0)`, which yields the timeslice. On Linux it ends in `select()` with a zero timeout, which returns immediately and yields nothing — so every waiter spun at 100% of a core while fighting the solver threads it was waiting on. Those now call `sched_yield()`.

Plain `sleep n` also takes FreeBASIC's global runtime lock on every call, so all solver threads serialised on one mutex. `sleep n, 1` skips it. Every sleep in the tree now has the second argument.

The main loop polled every 15 ms when idle; it now blocks in GTK properly. Idle CPU went from a steady poll to 0.4% of one core.

The UI queue appended entries that were whole-widget replacements, so worker threads outran the drain rate and updates got dropped silently. It coalesces now.

Also: `-gen gcc` is set explicitly, because fbc's `-O` and `-Wc` flags are honoured by no other backend — on 32-bit x86 the default is `-gen gas` and an "optimised" build is silently unoptimised.

### Cicada tooling

Three menus. **Cicada** converts (runes ↔ numbers ↔ Latin, letter-form toggles, Gematria Primus table, Liber Primus page download). **Cicada analysis** measures without modifying anything — rune frequency, bigrams and doublets, IOC, IOC by period, Kasiski, gematria by word with prime hunting, totient chains. **Cicada solve** searches for a key.

There are also Manipulation-window operations for atbash, shifts, Vigenère, running key, autokey, and prime/totient/Fibonacci keystreams.

`README-CICADA.md` has the details.

## The key stream solvers

The base hill-climber searches over a *substitution* — an unknown mapping from cipher symbol to plaintext symbol. That's the wrong shape for most Liber Primus hypotheses, where the mapping is known (shift by k mod 29) and the *key stream* is unknown. So these search the key instead.

They score through the same n-gram tables the main solver uses, so scores are comparable and better n-grams help both. They run on a background thread; the UI stays responsive and *Stop* works.

Modes: Vigenère key (scanned across lengths), autokey primer, free running key, and an exact enumeration of closed-form transforms (atbash × shift × keystream family).

**They need a runeglish n-gram set.** Two layouts work and the solver detects which it has: 29-symbol (one character per rune) or Latin (digraphs spelled out, which lands on 22 letters — the runes never spell with K, Q, V or Z). It refuses rather than guessing if some rune has no spelling the alphabet can represent.

`corpus_to_runeglish.py` converts an English corpus; `convert_ngrams.py` turns raw counts into the format AZdecrypt loads. Both have `--help`.

### One thing to be clear about

The running-key mode will *always* return fluent-looking plaintext. A free key stream has one unknown per rune, so any plaintext is reachable and the n-gram score can't distinguish a real decryption from a fitted one. The evidence is the key: a genuine running key is itself a passage of text. If the derived key reads as gibberish, you have a fit, not a solve. The solver prints both and says so.

The same caution applies more weakly everywhere else. A hill-climber returns its best candidate whether or not one exists. Compare against the other lengths.

## Testing

`./build.sh menutest` produces a build that, on launch, fires every menu item three times — forward, reverse, then shuffled, since several are toggles that behave differently the second time. Each item is logged to `/tmp/menufuzz.log` and flushed before dispatch, so if one crashes the last line names it.

Current state: 199 items × 3 passes, clean. The harness is compiled out entirely unless `-d AZ_MENUFUZZ` is passed.

The cipher math (atbash, shifts, Vigenère, autokey, running key, the keystream generators, both key-length finders) is cross-checked against an independent Python implementation. The solvers have been verified end to end by planting a known key and confirming recovery, on both alphabet layouts.

## Known issues

- Some systems print a warning to stderr on startup that I haven't tracked down. It doesn't appear to affect anything, but it's unexplained rather than understood.
- Solver throughput hasn't been benchmarked against the Windows build on identical hardware. The performance work above is sound in principle; the actual speedup is unmeasured.
- Thread count defaults to all logical cores. Windows uses 3/4. If throughput disappoints, that's the first knob — Options → Solver → CPU threads.
- The menu self-test covers menu items, not the controls inside the Manipulation, Transposition and Options windows.

## Credits

AZdecrypt is by Jarlve. The solver, the n-gram machinery, and essentially everything that makes this program good are his work. This repository is a port plus some additions, and carries whatever terms the original is distributed under — check with the author before redistributing.

The Gematria Primus and the Liber Primus are Cicada 3301's.
