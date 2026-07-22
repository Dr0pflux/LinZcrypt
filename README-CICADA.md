# Cicada 3301 / Liber Primus tooling

Runic cryptanalysis support built on top of the Linux port. It adds a **Cicada**
menu and a set of runic cipher operations, working on the 29-rune Gematria Primus
alphabet.

## Why nothing in the solver changed

AZdecrypt stores a cipher as `info()`, an array of integers (not bytes), and its
parser already accepts space-separated numbers. The hill-climbing solver is
general over integer symbol alphabets.

So runes need no engine changes — only transcoding at the boundary:

```
  runic text  ──►  integers 1..29  ──►  existing AZdecrypt solver
   (UTF-8)          (rune index+1)       (unmodified)
```

Symbol `0` is reserved for word separators (`-` and `.` in Liber Primus). Every
Cicada operation passes `0` through untouched, because word boundaries are what
make cribs work.

## Workflow

1. Paste runic text into the input window.
2. **Cicada → Runes to numbers** (or *keep separators* to preserve word breaks).
3. Apply Cicada operations, or run the normal solver — it now sees a 29-symbol cipher.
4. **Cicada → Numbers to latin** to read a candidate plaintext.

## Cicada menu

| Item | Purpose |
|---|---|
| Runes to numbers | Transcode runes → `1..29`, discard punctuation |
| Runes to numbers (keep separators) | As above, but word breaks become `0` |
| Numbers to runes | Inverse |
| Numbers to latin | Read out as Latin transliteration |
| Runes to latin (direct) | Transliterate without numeric round-trip; preserves layout |
| Latin to runes | Encode Latin → futhorc (greedy digraph matching) |
| Gematria sum | Sum of rune primes; reports primality and totient |
| Runic index of coincidence | IOC against the 29-rune alphabet, with interpretation |
| Gematria Primus table | Reference table |

## Cicada operations (Manipulation window)

Selectable in the Manipulation list. **A1** carries the argument.

| Operation | A1 | Notes |
|---|---|---|
| `Cicada: atbash` | — | `i → 28-i`, self-inverse |
| `Cicada: shift` | shift amount | Caesar over 29 runes |
| `Cicada: vigenere (decrypt/encrypt)` | key, e.g. `DIVINITY` | Key advances on runes only, not separators |
| `Cicada: prime shift (decrypt/encrypt)` | — | Position *i* shifted by *i*-th prime mod 29 |
| `Cicada: totient shift (decrypt/encrypt)` | — | Shifted by `(prime−1) mod 29` |

The key-advance rule matters: on the solved Liber Primus pages, separators do not
consume key material, and that's the behaviour here.

## Cipher math verification

The operations were cross-checked against an independent Python implementation:

```
Atbash self-inverse:                OK
Shift round-trip:                   OK
Vigenere round-trip:                OK
Atbash known-plaintext round-trip:  OK    (AWARNING → RNGRAMEW → AWARNING)
Digraph greedy match:               OK    (THE → [TH, E], 2 runes not 3)
IOC discriminates:                  OK    (random 0.0345, english-ish 0.0656)
```

The IOC figures match theory: `1/29 = 0.0345` for random runic text, higher for
English transliterated into futhorc — the discriminator between a monoalphabetic
and a polyalphabetic candidate.

The Gematria Primus table was validated against Python's `unicodedata`: all 29
codepoints distinct, in the Runic block, with correct Unicode names.

## The Gematria Primus table

The rune → Latin → prime mapping follows the commonly published Cicada table. If
your source orders or transliterates differently, it's one contiguous block at the
top of `cicada_gematria.bi`, laid out to be edited in place.

## Notes

- **Digraph ambiguity when encoding.** Greedy longest-match means `THE` encodes as
  `TH,E`. If a passage genuinely intends `T,H,E`, this mis-encodes. Unavoidable
  without word context; only affects Latin → runes.

- **IOC on short texts.** Liber Primus pages are short. Below ~200 runes the IOC
  estimate is noisy — treat the interpretation banding as a hint, not a verdict.

- **`prime_nth` uses trial division.** Fine for key lengths and rune positions. If
  prime-shift solving ever becomes a hot loop, precompute a sieve.

## Not yet wired to the UI

`cicada_ciphers.bi` also contains a running-key Vigenère (`cic_runningkey` — the
leading hypothesis for the unsolved pages) and several key-stream generators
(`cic_key_primes`, `cic_key_totient`, `cic_key_totient_primes`,
`cic_key_fibonacci`). They're implemented and callable; they just don't have menu
entries yet. That's the obvious next addition.

## Files

| File | Contents |
|---|---|
| `cicada_gematria.bi` | Gematria Primus table, UTF-8 rune handling, transcoding, number theory |
| `cicada_ciphers.bi` | Atbash, shifts, Vigenère, running key, key generators, gematria sum, runic IOC |
