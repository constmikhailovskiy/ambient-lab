# CLAUDE.md

Ambient/drone live-coding rig: SuperCollider + SuperDirt + TidalCycles, feeding Ableton Live on
macOS. Read `README.md` for the rationale and `MACOS-SETUP.md` for the host configuration.

## Architectural invariants — do not "simplify" these

**Two layers, deliberately separate.** `Ndef` proxies in `sc/beds.scd` are continuous drones that
never retrigger and crossfade on re-evaluation. Tidal handles only things with onsets: chord
changes, noise gestures, arpeggios. If a change would turn a bed into a Tidal pattern, or a Tidal
pattern into a bed, stop and ask. This split is the point of the design, not an accident.

**Use `Ndef`, never `ProxySpace.push(s)`.** Pushing a ProxySpace replaces the current environment
and breaks the `~dirt` reference SuperDirt depends on.

**Orbit → bus map is a contract with the Ableton set.** Changing it silently breaks four armed
tracks:

| Orbit | Bus | Layer |
|---|---|---|
| 0 | 0/1 | catch-all / percussive |
| 1 | 2/3 | pads & drones, `Ndef(\bed)` |
| 2 | 4/5 | noise & washes, `Ndef(\air)` |
| 3 | 6/7 | glass & arps, `Ndef(\gran)` |

`~dirt.start(57120, [0, 2, 4, 6, 0, 0])` defines exactly six orbits. `# orbit 6` addresses nothing.

**No sc3-plugins dependency.** Every SynthDef uses core UGens only (`VarSaw`, `RLPF`, `DynKlank`,
`TGrains`, `Splay`, `Balance2`, `Decay2`, `LFNoise2`, `BPF`, `LeakDC`). Keep it that way — it
avoids a CMake source build for no benefit.

**SynthDef param conventions.** `freq` comes from Tidal's `note`. `sustain` is in **seconds**, not
cycles. Stereo position is a custom `pos` param in −1..1 (not SuperDirt's `pan`, whose semantics
differ) — Tidal reaches it via `# pF "pos" 0.5`.

**`prelude.hs` is the source of truth for helpers.** `bootstrap.sh --install` regenerates
`tidal/BootTidal.hs` as *stock boot file + prelude.hs*. Edit `prelude.hs`, never `BootTidal.hs`
directly — it is a build artifact and gets overwritten.

## Verification

Compile-check SynthDefs (catches most edits):

```bash
printf '"%s".load; "SC-OK".postln; 0.exit;\n' "$PWD/sc/drones.scd" > /tmp/c.scd
/Applications/SuperCollider.app/Contents/MacOS/sclang -D /tmp/c.scd
```

Typecheck the Tidal boot file — patterns are not evaluated, so this only proves it loads:

```bash
ghci -ghci-script tidal/BootTidal.hs -e ':quit'
```

Signal test (proves audio exists; proves nothing about whether it sounds good): boot the stack,
fire one event, `s.record` a couple of seconds, confirm the WAV's RMS is non-zero.

Prefer running these over asserting a change is correct. Haskell operator precedence around `$`,
`#` and the `|+|` family is the most common source of breakage here.

## Constraints

- **Never run `sudo`.** The shell is non-interactive; the password prompt hangs. Surface the exact
  command and let the human run it. This applies to `brew install --cask blackhole-16ch`.
- **Never touch Audio MIDI Setup, CoreAudio aggregate devices, or Ableton preferences.** GUI-only
  by design; UI-scripting them via `osascript` is fragile and out of scope.
- `bootstrap.sh` defaults to check mode and must stay idempotent. Any new step checks before acting.
- Long operations (GHC install, the ~1GB Dirt-Samples clone, `cabal v1-install tidal`) should be
  backgrounded rather than run to a tool timeout.
- Audio in `takes/` is gitignored; the `.tidal` and `.scd` source that produced it is not. Preserve
  that asymmetry.

## Aesthetic defaults

Prime-numbered, non-coinciding periods (`slow 6`, `open 23`, `drift 37`) so nothing loops audibly.
Long crossfades. `sustain` longer than the retrigger interval so voices overlap. When adding
parameters, prefer slow continuous modulation over stepped values.
