# SYNTAX.md

Reference for the two languages in this rig. Organised around the ideas that make the syntax make
sense, not as a feature list — for exhaustive coverage see the SuperCollider help browser (Cmd+D on
any class name) and <https://tidalcycles.org/docs/>.

---

# Part 1 — sclang (SuperCollider)

## The one big idea

**Code inside a `SynthDef` runs once, in sclang, to build a graph.** That graph is sent to
`scsynth`, which runs it. Your code is a factory that produces an instrument; it is not the
instrument.

```supercollider
SynthDef(\demo, { |freq = 440|
    var a = rrand(0.1, 0.9);        // build time. ONE value, baked in forever.
    var b = LFNoise2.kr(0.1);       // runtime. A node in the graph, changing continuously.
    var c = 5.collect { |i| i * 2 };// build time. A plain sclang array: [0,2,4,6,8].
    Out.ar(0, SinOsc.ar(freq) * b * a);
}).add;
```

Every "why isn't my randomness changing?" question is this distinction. Build-time randomness
varies between *different synths you define*, not between *notes you play*.

Corollary: after editing a SynthDef you must re-evaluate it (`.add` again). Voices already
sounding keep the old graph; new voices get the new one.

## Objects and messages

Smalltalk-derived. Everything is an object; you send it messages with `.`

```supercollider
440.midicps            // no-op here, 440 is already Hz
69.midicps             // 440.0
0.5.rand               // random 0..0.5
[1,2,3].sum            // 6
sig.tanh               // soft clip — works on UGens too
(1..8).collect { |i| i * i }
```

Method calls are interchangeable with function-call syntax: `440.midicps` == `midicps(440)`, and
`SinOsc.ar(440)` is a message `ar` sent to the class `SinOsc`.

## Rates

| Suffix | Rate | Use for |
|---|---|---|
| `.ar` | audio — one value per sample | anything you hear |
| `.kr` | control — one per ~64 samples | modulation, envelopes, anything slow |
| `.ir` | initialisation — once at synth start | fixed-at-birth values |

In ambient almost all modulation is `.kr`. It's ~64× cheaper and you cannot hear the difference on
a filter sweep that takes 30 seconds.

## Multichannel expansion

Pass an array where a UGen expects a number, and the entire UGen replicates. This is the most
elegant thing in the language.

```supercollider
SinOsc.ar(440)                              // 1 channel
SinOsc.ar([440, 441])                       // 2 channels, 1 Hz beating
SinOsc.ar([440, 441]) * [0.5, 0.2]          // expansion applies elementwise
Mix(SinOsc.ar(Array.fill(7, {...}))) / 7    // 7 voices summed to mono — ambPad
Splay.ar(sigArray, 0.8)                     // N channels spread across stereo
```

`Mix` sums to mono. `Splay` spreads across stereo. `Balance2` places a stereo pair.

## Variables and scope

```supercollider
var x = 1;          // function-local. Must be declared at the TOP of the block.
~x = 1;             // environment variable. Survives between evaluations. Your session state.
x = 1;              // single letters a-z are pre-declared globals. Fine for scratch, not for code.
\name               // a Symbol. Cheap, interned. SynthDef names and params use these.
"name"              // a String.
{ |a, b = 2| ... }  // Function with arguments; as a SynthDef these become settable controls.
```

`~dirt`, `~lab`, `~midiOut` in this repo are environment variables — which is exactly why
`ProxySpace.push` is banned in `CLAUDE.md`: it replaces the environment and `~dirt` vanishes.

## Envelopes and freeing

```supercollider
var env = EnvGen.ar(
    Env([0, 1, 1, 0], [atk, hold, rel], \sin),   // levels, times, curve
    timeScale: sustain,                          // scale all times by this
    doneAction: 2);                              // 2 = free the synth when finished
```

`doneAction: 2` matters. Without it every note you play stays resident forever and the server
eventually chokes. `timeScale` is why `atk`/`rel` in this repo are *fractions* — they scale with
whatever `sustain` Tidal sends.

## Evaluation in the IDE

- **Cmd+Enter** — evaluate current line, or the whole `( ... )` block if the cursor is inside one
- **Cmd+.** — free all nodes. Panic.
- **Cmd+Shift+L** — recompile the class library. Wipes all `~variables`.
- **Cmd+D** — help for the class under the cursor. This is the real documentation.
- `.postln` — print a value and return it. Debugging is mostly this.
- `s.meter`, `s.plotTree`, `s.scope` — see levels, see live nodes, see waveforms

---

# Part 2 — TidalCycles

## The one big idea

**A pattern is a function from a time span to events.** Not a list, not a buffer. `"c2 e2 g2"` is
a function that, asked about cycle 7, replies "c2 at 7.0, e2 at 7.33, g2 at 7.67."

Consequences worth internalising:

- `slow 8` costs nothing — it rescales the query, it doesn't expand any data
- transformations compose without limit, because you're composing functions
- `sine` works as a parameter because it's a continuous function of time, sampled wherever your
  events happen to land
- patterns are infinite; there is no "end"

## Two languages per line

Outside quotes: **Haskell**. Inside quotes: **mini-notation**, a separate parser.

```haskell
d1 $ slow 4 $ note "<c2 [e2 g2]>" # room 0.9
--   └─────── Haskell ───────┘ └ mini ┘ └ Haskell ┘
```

## The three operators that matter

**`$` — application, lowest precedence.** Grabs everything to its right. `f $ g $ x` is
`f (g x)`. It exists to avoid nested parentheses.

```haskell
d1 $ slow 4 $ pad $ note "c2" # orbit 0
-- parses as: d1 (slow 4 (pad (note "c2" # orbit 0)))
-- the orbit lands INSIDE pad's argument, so pad's own orbit wins. Bug.
d1 $ (slow 4 $ pad $ note "c2") # orbit 0
-- parenthesise when you need something applied last.
```

**`#` — merge controls. Structure from the left, values from the right.** For a parameter present
on both sides, the right wins. This is why appending `# gain 0.8` overrides an earlier gain.

**`.` — function composition.** `(f . g) x` is `f (g x)`. Needed wherever a function is an
*argument*:

```haskell
superimpose ((# speed 2) . (0.25 ~>)) p
```

`(# speed 2)` is a *section* — an operator with one side missing, which is a function awaiting a
pattern. Partial application is everywhere in Tidal; `slow 4` alone is a function.

## The `|` operator family

The arrow points at where **values** come from. The bars mark where **structure** comes from.

| Operator | Structure | Values |
|---|---|---|
| `|>` (aka `#`) | left | right |
| `<|` | right | left |
| `|>|` | both | right |
| `|+` | left | sum |
| `+|` | right | sum |
| `|+|` | both | sum |

Same for `-`, `*`, `/`, `%`. Ninety percent of the time you want `#`.

## Mini-notation

| Syntax | Meaning |
|---|---|
| `a b c` | sequence, dividing the cycle evenly |
| `~` | rest |
| `[a b]` | subgroup — fits into one step |
| `<a b>` | alternate, one per cycle. **The ambient workhorse.** |
| `a*2` | twice as fast |
| `a/2` | half speed — plays every other cycle |
| `a!3` | repeat three times |
| `a@3` | elongate — take 3 steps' worth of space |
| `[a, b]` | layer simultaneously |
| `a?` | 50% chance of playing |
| `a?0.8` | 80% chance |
| `a:3` | sample number 3 in folder `a` |
| `a(3,8)` | euclidean — 3 hits spread over 8 steps |
| `c e g` | note names, `c5` = middle. `s`=sharp, `f`=flat: `as3`, `ef4` |
| `c'maj7'5` | chord: root, name, number of notes |

At `ambient` tempo (0.15 cps, 6.7 s/cycle) `<a b c d>` is a chord change every ~7 seconds. That's
the right scale for this music, and it's why `<>` appears in almost every line of the sketches.

## Structure vs. continuous

Some patterns are **discrete** (events with start and end): mini-notation strings.
Some are **continuous** (a value at every instant): `sine`, `saw`, `tri`, `square`, `perlin`,
`rand`.

Continuous patterns have no structure of their own. As a parameter they're sampled at your events'
onsets. To *make* structure from one, use `segment`:

```haskell
# pF "cutoff" (range 250 5000 (slow 23 sine))   -- sampled, no structure needed
note (segment 4 $ irand 12)                     -- 4 discrete events per cycle
```

Forgetting `segment` on a continuous pattern used as structure is a common silent failure.

## Transformations worth knowing

```haskell
slow n / fast n                 rescale time
rev                             reverse each cycle
every n f                       apply f every nth cycle
whenmod a b f                   apply f when cycle mod a >= b
off t f                         superimpose a copy shifted by t
superimpose f                   superimpose a copy, unshifted
jux f                           original left, f-modified right
t ~> / t <~                     shift later / earlier
degradeBy n                     drop events at random  (aliased to `thin` here)
segment n                       sample a continuous pattern n times per cycle
range lo hi                     rescale a 0..1 pattern
chunk n f                       apply f to a different 1/n of the cycle each cycle
stack [a, b, c]                 layer patterns
cat / fastcat                   concatenate by cycle / within a cycle
arp "up"                        unroll chords into sequences
rolled                          stagger chord notes slightly
scale "aeolian"                 map integers onto a mode
```

## Evaluation in VS Code

- **Shift+Enter** — evaluate the current line
- **Ctrl+Enter** — evaluate the current block (blank-line delimited)
- **Ctrl+Opt+H** — hush
- `d1 silence` — stop one channel, letting reverb tails ring out
- `hush` — stop everything at once
- `panic` — stop everything and clear the server

Blank lines are structural: they define block boundaries. Don't let a formatter collapse them.

---

# Part 3 — where the two meet

Tidal sends OSC named parameters. SuperDirt looks up the `s` value, finds the SynthDef, and passes
through any parameter whose name the SynthDef declares. Anything undeclared is silently dropped.

```haskell
note "c3"           -->  freq        (SuperDirt converts note number to Hz)
sustain 12          -->  sustain     (SECONDS, not cycles)
gain 0.8            -->  amp
pF "cutoff" 1200    -->  cutoff      (any custom control, by name)
```

`pF` is the general escape hatch: `pF "name" value` sends an arbitrary float. `pI` for integers,
`pS` for strings. That's how the whole custom-synth layer in `sc/drones.scd` is reachable.

**Silent-failure checklist**, in the order these actually happen:

1. Parameter name typo — `pF "cutof"` is dropped without complaint
2. Orbit points at a bus your hardware doesn't have
3. `atk` is a long fraction of a long `sustain`, so it's fading in and you got impatient
4. SynthDefs were added to a server that has since been replaced
5. `$` precedence put a modifier somewhere you didn't intend
