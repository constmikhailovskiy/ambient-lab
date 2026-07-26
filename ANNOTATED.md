# ANNOTATED.md

A walkthrough of every file. Depth is uneven on purpose: the SynthDefs and the Tidal prelude get
signal-by-signal treatment because that's where understanding actually pays off. Config files and
the shell script get structural summaries, because a line-by-line reading of `"editor.wordWrap":
"on"` teaches nothing.

Read `SYNTAX.md` first if the language basics aren't settled — this document assumes them.

---

# `sc/startup.scd`

Runs once per session. Boots the server, starts SuperDirt, loads your synths.

### Line 8 — the path anchor

```supercollider
~lab = "~/ambient-lab/sc".standardizePath;
```

`~lab` is an *environment variable* — it persists between evaluations and across files, which is
why `drones.scd` can be loaded relative to it later. `standardizePath` expands the `~` into
`/Users/konstie`, because sclang's file methods don't do shell expansion themselves.

This line sits **outside** the parenthesised block deliberately. It's the one thing you edit if the
repo moves, and keeping it separate means you can re-evaluate it alone. Note that
`Language > Recompile Class Library` wipes all `~variables`, so after Cmd+Shift+L this line must
run again before the block.

### Lines 12–15 — server memory allocation

```supercollider
s.options.numBuffers = 1024 * 256;
s.options.memSize = 8192 * 32;
s.options.numWireBufs = 256;
s.options.maxNodes = 1024 * 32;
```

`s` is the default Server — a *client-side proxy object* representing `scsynth`, not the process
itself. Setting `.options` before boot configures the process that will be launched.

- `numBuffers` — how many sample buffers can exist. Dirt-Samples alone is a few thousand files, so
  the default (1024) overflows immediately. This is a hard limit; exceeding it fails at load time.
- `memSize` — real-time memory in kilobytes, used by delay lines, reverbs, and FFT. SuperDirt's
  global reverbs are hungry. Too low gives "alloc failed" errors mid-performance.
- `numWireBufs` — buffers for passing signals *between* UGens inside one SynthDef. Complex graphs
  (your 7-voice pad with per-voice modulation) need more than the default 64. The error if you run
  out is "exception in GraphDef_Recv: exceeded number of interconnect buffers."
- `maxNodes` — ceiling on simultaneous synths. With 40-second sustains and overlapping voices you
  accumulate more nodes than you'd think.

All four are "raise them and forget" values. None costs anything meaningful on a modern Mac.

### Line 18 — output channel count

```supercollider
s.options.numOutputBusChannels = 8;
```

The single most consequential line in the file. It declares eight hardware output channels, which
is what makes four independent stereo stems possible. It also means channels 3–8 go nowhere until
BlackHole exists — which is the Tier 0 silence problem, and why the temporary fix is
`~dirt.start(57120, 0 ! 6)`.

### Line 22 — input channels

```supercollider
s.options.numInputBusChannels = 0;
```

Zero, not two. You aren't recording audio into SC, and requesting inputs triggers macOS's
microphone permission prompt. If that prompt is dismissed or denied, the server fails to boot with
an error that never mentions permissions — an expensive twenty minutes.

### Lines 24–31 — clock and latency

```supercollider
s.options.sampleRate = 48000;
s.options.hardwareBufferSize = 512;
s.latency = 0.3;
```

`sampleRate` must match the aggregate device exactly. A mismatch produces either a boot failure or
audio at the wrong pitch.

`hardwareBufferSize` is the driver block size — the classic latency/stability tradeoff. 512 samples
at 48 kHz is ~10.7 ms.

`s.latency` is a different thing and often confused with it: it's how far in the *future* sclang
schedules messages, giving the OS time to deliver them before they're needed. 0.3 s is very
generous. For ambient this is free — nobody perceives a third of a second on a drone — and it
eliminates late-message warnings entirely.

### Line 33 — the async boundary

```supercollider
s.waitForBoot { ... };
```

Booting is asynchronous. Everything that touches the running server must live inside this closure,
or it executes against a server that doesn't exist yet. This is the structural reason the file is
shaped the way it is.

### Lines 35–37 — SuperDirt

```supercollider
~dirt = SuperDirt(2, s);
~dirt.loadSoundFiles;
```

`SuperDirt(2, s)` constructs the dispatcher with **2 channels per orbit** on server `s`. That 2 is
the width of each orbit, not the total output count — orbits are stereo, and there are eight
hardware channels because there are four of them.

`loadSoundFiles` with no argument walks the Dirt-Samples quark and loads every WAV into a buffer,
keyed by folder name. This is the slow part of boot. The commented line beneath takes a glob, and
pointing it at your own field recordings is the highest-leverage single change you can make to
this rig — your own material is what stops it sounding like everyone else's Tidal setup.

### Line 40 — loading the synths

```supercollider
(~lab +/+ "drones.scd").load;
```

`+/+` is sclang's path-join operator. `.load` reads and evaluates the file in the current
interpreter, so the SynthDefs inside get `.add`ed. Because this runs inside `waitForBoot`, the
server exists and `.add` can actually transmit the graph definitions.

### Line 42 — the barrier

```supercollider
s.sync;
```

Blocks until the server has finished processing everything queued so far. Without it, `~dirt.start`
can race ahead of the SynthDef transmission. This is the line whose absence produces intermittent
"SynthDef not found" on some boots and not others — the worst class of bug.

### Line 50 — orbits to buses

```supercollider
~dirt.start(57120, 0 ! 6);
```

Two arguments: the OSC port to listen on, and an array of *output bus offsets*, one per orbit.

The array length defines how many orbits exist — six either way. The values are starting bus
indices, and because each orbit is 2 channels wide, an offset of 2 means buses 2–3.

**The line above is the temporary form.** `0 ! 6` is sclang for `[0, 0, 0, 0, 0, 0]` — all six
orbits folded onto the main output pair. That's deliberate: until BlackHole is installed, buses
2–7 are declared but connect to nothing, so any orbit routed there is silent (the Tier 0 problem
described under Line 18). Folding everything to 0/1 keeps the rig audible on plain built-in output.

The target — the mapping the four armed Ableton tracks expect, and the one written in the comment
block directly above this line — is:

```supercollider
~dirt.start(57120, [0, 2, 4, 6, 0, 0]);
```

Orbit 0 to buses 0–1, orbit 1 to 2–3, orbit 2 to 4–5, orbit 3 to 6–7; orbits 4 and 5 both point at
bus 0, sharing the main output. Switch to this once BlackHole exists — the stem separation is the
entire reason for eight output channels.

`# orbit 6` in Tidal addresses nothing and is silent. If you want more, lengthen the array.

Port 57120 is SuperDirt's convention and matches Tidal's default target. Change it here and you
must change it in `BootTidal.hs` too.

### Line 53 — delete this

```supercollider
~dirt.orbits.do { |x| x.set(\dryBus, x.dryBus) };
```

**This is dead code and my mistake.** It sets each orbit's `dryBus` to the value it already has —
a no-op. The comment above it claims it configures reverb tails, which it does not. Remove it.

If you *do* want different default reverb behaviour per orbit, the real mechanism is setting
`room`/`size` on the orbit's global effects, or simply supplying them from Tidal, which is what
`haze` and `cathedral` in the prelude already do.

### Lines 61–75 — MIDI, commented

```supercollider
~midiLive = MIDIOut.newByName("IAC Driver", "Bus 1");
~midiLive.latency = 0.02;
~dirt.soundLibrary.addMIDI(\live, ~midiLive);
```

`MIDIOut.newByName(device, port)` takes two strings that must match what CoreMIDI reports exactly —
hence the instruction to print `MIDIClient.destinations` first rather than guess.

`.latency = 0.02` is separate from `s.latency`. Audio goes through the server's scheduling; MIDI
goes straight out of sclang. Without a small MIDI latency, MIDI events arrive *before* the
corresponding audio, and your MicroFreak plays ahead of your pads.

`addMIDI(\live, ~midiLive)` registers the name `live` in SuperDirt's sound library, which is what
makes `# s "live"` work in Tidal. Two separate registrations means two destinations addressable by
name from the same pattern language.

---

# `sc/drones.scd`

Four SynthDefs. Each follows the same skeleton, so learning one gives you all four.

## The shared skeleton

```supercollider
SynthDef(\name, { |out = 0, freq = 110, sustain = 4, pos = 0, amp = 0.5, ...|
    var env, sig, stereo;
    env = EnvGen.ar(Env(...), timeScale: sustain, doneAction: 2);
    sig = <make sound>;
    stereo = Splay.ar([sig, DelayC.ar(sig, ...)], spread);
    stereo = Balance2.ar(stereo[0], stereo[1], pos.clip(-1, 1));
    OffsetOut.ar(out, stereo * env * amp);
}).add;
```

The argument list *is* the interface Tidal sees. SuperDirt inspects the SynthDef's control names and
passes through any matching parameter, silently dropping the rest. `out`, `freq`, `sustain`, `amp`
are filled by SuperDirt automatically; everything else needs `pF "name"`.

`OffsetOut` rather than `Out`: it applies a sub-block sample offset so notes land at their exact
scheduled time rather than being quantised to the 64-sample control block. On percussion this is
audible; here it's just correctness.

`Balance2.ar(L, R, pos)` places an existing stereo pair, with `pos` from −1 to +1. We use a custom
`pos` rather than SuperDirt's `pan` because `pan` has different semantics in SuperDirt's own
`DirtPan` (0..1 across a channel ring), and mixing conventions invites confusion.

## `ambPad` — detuned saw stack

```supercollider
env = EnvGen.ar(
    Env([0, 1, 1, 0], [atk, (1 - atk - rel).max(0.02), rel], \sin),
    timeScale: sustain, doneAction: 2);
```

Four levels, three segment durations. Because `timeScale: sustain` multiplies all three, `atk` and
`rel` are **fractions of the note**, not seconds. Defaults are 0.35 and 0.4, so a 20-second note
fades in over 7 seconds — that's the "is it broken?" pause you hit on the first evaluation.

`(1 - atk - rel).max(0.02)` guards against `atk + rel > 1`, which would give a negative sustain
segment and a silent or misbehaving envelope. `.max` on a control produces a `BinaryOpUGen`, so the
guard is evaluated in the graph, not at build time.

`\sin` gives S-curved segments rather than linear ones — much more natural for slow fades.

```supercollider
freqs = Array.fill(voices, { |i|
    var offset = (i - ((voices - 1) / 2)) / voices;
    freq * (1 + (detune * offset * LFNoise2.kr(0.03 + 0.06.rand).range(0.7, 1.3)))
});
```

Seven detune offsets spread symmetrically around zero: for `voices = 7`, `offset` runs −0.43 to
+0.43, so voice 3 sits exactly at `freq` and the rest fan out.

The critical detail is that `0.06.rand` is **build-time** — each voice gets a *fixed* modulation
rate between 0.03 and 0.09 Hz, chosen once when the SynthDef is defined. `LFNoise2.kr(...)` is
**runtime** — the actual wandering. So all seven voices drift at different, permanently-assigned
speeds. That's what makes the chorus feel organic rather than synchronised.

```supercollider
sig = VarSaw.ar(freqs, Array.rand(voices, 0.0, 1.0), LFNoise2.kr(0.05).range(0.2, 0.8));
sig = Mix(sig) / voices;
```

`VarSaw` is a variable-width sawtooth: width 0.5 is a triangle, approaching 0 or 1 gives a ramp.
Modulating width sweeps the harmonic content without a filter.

Passing an *array* of frequencies is multichannel expansion — one line becomes seven oscillators.
The random initial phases stop all seven starting in lockstep. `Mix` sums them, `/ voices`
normalises so the level doesn't depend on how many voices you chose.

```supercollider
sig = sig + (sub * SinOsc.ar(freq * 0.5));
```

A sine an octave down. Saw stacks lose fundamental weight when heavily detuned; this puts it back.

```supercollider
cf = (cutoff * LFNoise2.kr(lfo).exprange(0.5, 2.5)).clip(60, 16000);
sig = RLPF.ar(sig, cf, (1 - res).clip(0.05, 1.0));
```

`exprange` maps the noise exponentially rather than linearly, which matches how pitch and filter
cutoff are perceived — a linear sweep sounds like it rushes through the top octave. The `.clip`
prevents the filter blowing up at extremes.

`RLPF`'s third argument is **rq**, the *reciprocal* of Q. Small rq means high resonance. So
`(1 - res)` inverts the intuitive direction: higher `res` gives lower rq gives more resonance.

```supercollider
sig = LeakDC.ar(sig);
```

High-pass at a very low frequency to remove DC offset. Asymmetric waveforms and nonlinearities
accumulate DC, which eats headroom and can thump when the envelope opens.

```supercollider
stereo = Splay.ar([sig, DelayC.ar(sig, 0.06, 0.023)], spread);
```

The Haas trick: a copy delayed 23 ms reads as *width* rather than as an echo, because the ear fuses
onsets under ~40 ms. `DelayC` interpolates, so a modulated delay time wouldn't click. `Splay`
spreads the two channels across the stereo field by `spread`.

## `ambDroneFM` — two-operator FM

```supercollider
mod = SinOsc.ar(
    freq * ratio * LFNoise2.kr(drift).range(0.994, 1.006), 0,
    freq * index * LFNoise2.kr(0.05).range(0.15, 1.0));
sig = SinOsc.ar(freq + mod) + (0.5 * SinOsc.ar((freq * 2) + (mod * 0.3)));
```

Classic FM: the modulator's *output* is added to the carrier's frequency. The modulator's amplitude
(third argument) is scaled by `freq * index`, which keeps the timbre consistent across pitch — a
fixed deviation in Hz sounds brighter on low notes than high ones.

`ratio` sets the harmonic relationship. Integer and simple ratios (1.5, 2) stay harmonic; irrational
ones (3.14) go metallic and bell-like fast.

The `range(0.994, 1.006)` on the modulator frequency is ±0.6% drift — barely a tuning error, but it
keeps the spectrum from freezing into something static.

The second carrier an octave up with a third of the modulation adds brightness without doubling the
FM chaos.

## `ambNoise` — filtered noise as harmony

```supercollider
src = PinkNoise.ar(1) + (0.3 * BrownNoise.ar(1));

bands = Array.fill(6, { |i|
    var f = freq * (i + 1)
        * LFNoise2.kr(motion * (0.4 + (i * 0.3))).range(1 - bw, 1 + bw);
    BPF.ar(src, f.clip(30, 16000), 0.02 + (bw * 0.15), 4)
});
```

Pink noise falls at 3 dB/octave, brown at 6 — the mix weights the low end. Six bandpass filters at
the **harmonic series** of `freq` (×1, ×2, ×3…), so this is noise arranged into a pitch even though
no oscillator exists.

`bw` does double duty and this is the design: it widens each band's random frequency wander *and*
widens the filter's own bandwidth (`0.02 + bw * 0.15` is the rq). At `bw = 0.05` you hear a note; at
`bw = 0.9` you hear weather. One parameter, the whole continuum.

Each band's motion rate is scaled by its index, so higher partials wander faster — they never
phase-lock into a static chord.

```supercollider
stereo = Splay.ar(bands, spread) / 3;
```

Splaying the six bands individually (rather than mixing then widening) places each partial at a
different stereo position. That's what makes it feel like a space rather than a sound.

## `ambGlass` — struck resonators

```supercollider
var ratios = [1, 2.01, 3.02, 4.13, 5.4, 6.83];
var amps   = ratios.collect { |r| 1 / (r * r) };
decs = ratios.collect { |r| decay / r.sqrt };
```

Deliberately *in*harmonic ratios — slightly off the integers. Perfectly harmonic resonators sound
like a synth pad; these small deviations are what read as struck metal or glass.

Amplitudes fall as 1/r², matching how real resonant bodies distribute energy. Decay times fall as
1/√r, because high partials always die first.

```supercollider
exciter = Decay2.ar(Impulse.ar(0), 0.002, blur.clip(0.001, 0.5)) * PinkNoise.ar(1);
sig = DynKlank.ar(`[ratios * freq, amps, decs], exciter) * 0.3;
```

`Impulse.ar(0)` at frequency zero fires exactly once, at synth start. `Decay2` turns that into a
short percussive envelope with attack and decay, shaping a burst of pink noise into a "strike."

`DynKlank` is a bank of resonant filters that ring when excited. The backtick makes a `Ref` — the
spec has to be passed by reference so it isn't multichannel-expanded into nonsense.

The physical model here: hit a resonant body with a short noise burst, and the resonances ring on
after the strike is gone. That's the whole synthesis method, and it's about six lines.

---

# `sc/beds.scd`

Different paradigm from everything above. These are **continuous** voices you deform by hand.

```supercollider
Ndef(\bed).fadeTime = 20;
Ndef(\bed, { ... });
Ndef(\bed).play(out: 2);
```

`Ndef` is a named node proxy. Re-evaluate the function and the new version **crossfades** in over
`fadeTime` — the old one is still running, both are audible, and 20 seconds later only the new one
remains. That is the mechanism that makes live editing of a drone bed sound intentional rather than
like a mistake.

`play(out: 2)` writes to hardware bus 2 directly, bypassing SuperDirt entirely. These aren't Tidal
events; they don't need orbits, envelopes, or `doneAction`. Nothing frees them because they never
end.

The file explicitly warns against `ProxySpace.push(s)`, which offers the same functionality with
nicer syntax (`~bed = {...}` instead of `Ndef(\bed, {...})`) at the cost of replacing the current
environment — taking `~dirt` with it and breaking SuperDirt.

```supercollider
var sig = Mix.fill(partials, { |i|
    var drift = LFNoise2.kr(rrand(0.01, 0.06)).range(0.996, 1.004);
    var amp = LFNoise2.kr(rrand(0.02, 0.09)).range(0.0, 1.0) / (i + 2);
    SinOsc.ar(f * (i + 1) * drift, 0, amp)
});
sig = sig.tanh * 0.4;
```

Nine partials of a fundamental, each with independently drifting pitch and amplitude. Because each
partial's amplitude wanders to zero and back on its own slow cycle, the timbre never repeats — the
spectrum is continuously recomposing itself.

`.tanh` is soft saturation: it limits peaks smoothly rather than clipping, which matters when nine
sines occasionally align in phase.

The granular bed (`Ndef(\gran)`) is the one to prioritise. `TGrains.ar(2, trig, buf, rate, pos,
dur, pan, amp)` scatters short grains from a buffer, and pointed at your own recordings it produces
material nothing else in this rig can.

---

# `tidal/prelude.hs`

Appended to `BootTidal.hs` by `bootstrap.sh`. Every definition is ordinary Haskell.

```haskell
ambient = setcps 0.15
```

`IO ()`, not a pattern. 0.15 cycles per second is ~6.7 seconds per cycle.

```haskell
pad p = p # s "ambPad" # orbit 1
```

`ControlPattern -> ControlPattern`. Appends two controls. Because `#` takes values from the right,
a later `# orbit 0` in your own pattern would override this — but only if it lands *outside* the
call, which is exactly the parenthesisation trap.

```haskell
hold n p = p # sustain n # legato 1
```

`sustain` is seconds. `legato 1` tells SuperDirt not to shorten the note relative to the event
duration. Together: "this note lasts exactly n seconds regardless of the pattern's timing."

```haskell
drift n p = p # pF "pos" (range (-0.9) 0.9 (slow n sine))
```

`sine` is a continuous pattern in 0..1. `range` rescales it to −0.9..0.9. `slow n` stretches it
across n cycles. `pF` sends it as a named float, reaching the custom `pos` control.

No `segment` needed because this is a *parameter*, not structure — it's sampled wherever the
pattern's events already are.

```haskell
widen n p = p # pF "detune" (range 0.05 0.6 (slow n perlin))
```

`perlin` instead of `sine` — smooth but irregular, so the detuning never settles into an audible
period.

```haskell
under p = superimpose ((|- note 12) . (0.5 ~>) . (# gain 0.8)) p
```

The densest line in the file. `superimpose f p` layers `f p` on top of `p`. The function is a
composition, and **composition applies right to left**:

1. `(# gain 0.8)` — quieten the copy
2. `(0.5 ~>)` — shift it half a cycle later
3. `(|- note 12)` — subtract 12 semitones

`~>` shifts a pattern *later* in time. `|-` takes structure from the left and subtracts the right,
so `p |- note 12` lowers p's notes by an octave. `(|- note 12)` with the left operand missing is a
*section* — a function waiting for a pattern.

```haskell
thin amt p = degradeBy amt p
```

A rename, nothing more. `degradeBy 0.5` drops each event with 50% probability. On an arpeggiated
chord this is disproportionately effective: the harmony stays fixed while every pass reveals a
different subset of the voicing.

---

# The sketches

`01-drones`, `02-noise`, `03-chords` are already densely commented; re-reading them here would be
duplication. What matters is the pedagogical shape:

**01** builds a drone in seven steps, each adding exactly one idea. The pivot is block 3, where
`sustain` becomes longer than the retrigger interval and discrete events start overlapping into
something continuous. That single realisation is most of ambient technique.

**02** explores `bw` as the pitched↔noise continuum, then moves to sample-based texture via
`striate`, then delay-as-instrument.

**03** covers chord syntax, `arp`, scale-constrained generative melody, `rolled`, and MIDI out.

`_template.tidal` is the scaffold for new pieces. Its two structural decisions — fixed channel
roles, and root/mode declared once at the top — are the parts worth keeping even if you rewrite
everything else.

---

# `bootstrap.sh`

Structural, since it's ordinary shell.

Runs in **check mode by default** and only acts with `--install`. The `run()` wrapper is the
mechanism: in check mode it prints "would run: …" instead of executing, so a single code path
serves both modes.

Sections in order: platform detection and Homebrew, SuperCollider and quarks, Haskell and Tidal,
editor, BlackHole and Ableton, repo layout. Each check appends to a `MISSING` array; the summary
reports what's left.

Two parts worth knowing:

- The quark installer writes a temp `.scd` ending in `0.exit` and runs `sclang -D` against it, which
  is how you drive SuperCollider non-interactively.
- The `BootTidal.hs` step locates the stock file via `ghc-pkg field tidal data-dir`, copies it into
  the repo, and appends `prelude.hs`. Re-run after any Tidal upgrade, since the stock file changes
  between versions.

It never runs `sudo` — non-interactive shells hang on the password prompt, so those commands are
surfaced for you to run yourself.

---

# Config files

**`.vscode/settings.json`** — the load-bearing entries are `files.associations` mapping `*.tidal` to
Haskell (the Tidal extension ships no grammar of its own), the two boot paths, and the two
`codehelp` levels set to `FULL`. `editor.wordBasedSuggestions: "allDocuments"` is the crude
fallback that completes any word appearing in your open sketches.

**`codehelp/ambient-lab.yaml`** — 17 entries documenting the prelude in the extension's own schema
(`cmd`, `help`, `params`, `examples`). Edit and run "Tidal Codehelp Reload"; no restart needed.

**`CLAUDE.md`** — repo invariants for Claude Code sessions: the orbit map, `Ndef` over
`ProxySpace`, no sc3-plugins, no sudo, verification commands. Its purpose is to stop a future
session helpfully "fixing" your routing.

**`.gitignore`** — ignores audio under `takes/` but not the `.tidal` and `.scd` sources beside it.
That asymmetry is deliberate: the recording is reproducible from the source, and the source is what
you'll actually want back.

---

# Reading order, if you're starting cold

1. `SYNTAX.md` parts 1 and 2 — the two mental models
2. `sc/drones.scd`, `ambPad` only — read it top to bottom as a signal path
3. `tidal/prelude.hs` — it's short, and it's the vocabulary you'll type most
4. `sc/startup.scd` — skim; you'll rarely edit it
5. Everything else on demand

The fastest way to understand a SynthDef is to break it. Change `voices` from 7 to 2,
re-evaluate, listen. Set `detune` to 0. Delete the `sub` line. Five minutes of that beats an hour
of reading.
