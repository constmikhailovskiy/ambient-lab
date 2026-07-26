# macOS setup

Run `./bootstrap.sh` first (check mode), then `./bootstrap.sh --install`. Everything below is
the part no script can do for you, because it's all GUI toggles in Apple's and Ableton's
preference panes.

---

## 1. Audio: SuperCollider → Ableton Live

The goal: SuperCollider's 8 output channels arrive in Live as four independent stereo inputs, and
you monitor through Live so you only have one thing making sound at the speakers.

BlackHole is a loopback driver, so SC writes into it and Live reads out of it. The complication is
that Live needs *one* CoreAudio device for both input and output. You can point Live's input and
output at two different devices, but then two unsynchronised clocks are running and you will get
occasional clicks and slow drift — which is exactly the failure mode you'd notice on a 20-minute
drone take. So build an aggregate device instead.

### Create the aggregate device

1. Open **Audio MIDI Setup** (`/Applications/Utilities/`).
2. Bottom-left **+** → **Create Aggregate Device**. Rename it `Live+SC`.
3. Tick **BlackHole 16ch** and your audio interface (or Built-in Output).
4. **Drag BlackHole to the top of the list.** This matters: channel numbers are assigned in list
   order, so BlackHole-first means BlackHole's 16 channels are aggregate channels 1–16 and your
   interface starts at 17. Any other order and every channel number below is off by two, which is
   a genuinely annoying half-hour to debug.
5. Set **Clock Source** to your interface (not BlackHole — a loopback driver is a poor master).
6. Tick **Drift Correction** on BlackHole.
7. Set the sample rate to **48000 Hz**, matching `startup.scd`.

### Configure SuperCollider

Already in `sc/startup.scd` — uncomment this line:

```supercollider
s.options.outDevice = "BlackHole 16ch";
```

SC talks to BlackHole *directly*, not to the aggregate. BlackHole is multi-client, so SC writing
to it while Live reads it through the aggregate is fine.

Optional but recommended: set `s.options.numInputBusChannels = 0`. You aren't recording audio
into SC, and with inputs enabled macOS will throw a microphone-permission prompt at you; if you
miss or deny it, the server fails to boot with an error that doesn't mention permissions at all.

### Configure Live

**Preferences → Audio**

| Setting | Value |
|---|---|
| Audio Device Type | CoreAudio |
| Audio Input Device | `Live+SC` |
| Audio Output Device | `Live+SC` |
| Sample Rate | 48000 |
| Buffer Size | 512 (raise to 1024 if you get dropouts) |

Then **Input Config**: enable stereo input pairs **1/2, 3/4, 5/6, 7/8**.
And **Output Config**: enable only the pair that corresponds to your interface — with BlackHole
first in a 16-channel setup, that's outputs **17/18**. (If you can't find your speakers, this is
why.)

**Create four audio tracks:**

| Track | Audio From | Monitor | Receives |
|---|---|---|---|
| Mobile 1 | Ext. In → 1/2 | In | orbit 0 — catch-all / percussive |
| Mobile 2 | Ext. In → 3/4 | In | orbit 1 — pads & drones, `Ndef(\bed)` |
| Mobile 3 | Ext. In → 5/6 | In | orbit 2 — noise & washes, `Ndef(\air)` |
| Mobile 4 | Ext. In → 7/8 | In | orbit 3 — glass & arps, `Ndef(\gran)` |

Now every layer has its own fader, its own EQ, its own reverb, and can be recorded separately.
This is the whole reason for the 8-channel setup, and it's the difference between "I made a
texture" and "I have a stem I can mix."

---

## 2. MIDI: SuperCollider → Live, and → MicroFreak

Two different paths, and it's worth being clear about which is which:

- **To Live's instruments** → through the **IAC Driver** (a virtual MIDI cable inside macOS).
- **To the MicroFreak** → *directly* over USB. Do not route this through IAC. The MicroFreak is
  class-compliant and appears as its own MIDI destination.

### Enable the IAC Driver

1. **Audio MIDI Setup** → menu **Window → Show MIDI Studio**.
2. Double-click the **IAC Driver** icon.
3. Tick **Device is online**. Under Ports you should have **Bus 1**; add a second bus if you want
   separate channels per destination.

### Find your port names

In SuperCollider, evaluate just this and read the post window:

```supercollider
MIDIClient.init;
MIDIClient.destinations.do { |d, i| [i, d.device, d.name].postln };
```

You'll get something like `[0, IAC Driver, Bus 1]` and `[1, MicroFreak, MicroFreak]`. Use those
exact strings in the `MIDIOut.newByName(device, name)` calls in `sc/startup.scd`.

### In Live

**Preferences → Link/Tempo/MIDI**: find `IAC Driver Bus 1` in the input list and turn **Track**
on. Leave Remote off unless you want Tidal mapping Live's controls, which is a different and
more chaotic project.

Then on a MIDI track: **MIDI From** = `IAC Driver Bus 1`, channel **1**. Tidal counts channels
from zero, so `# midichan 0` in Tidal is channel 1 in Live.

---

## 3. Editor boot file

Point your editor at the repo's boot file so your ambient prelude loads on every boot and stays
in version control (rather than living in the cabal store where an upgrade will silently wipe it).

**VS Code** — `settings.json`:

```json
{
  "tidalcycles.bootTidalPath": "/Users/YOUR_USER/ambient-lab/tidal/BootTidal.hs",
  "tidalcycles.ghciPath": "/Users/YOUR_USER/.ghcup/bin/ghci",
  "tidalcycles.feedbackColor": "rgba(100,250,100,0.3)"
}
```

**Pulsar** — Settings → Packages → tidalcycles → *boot file path*.

`bootstrap.sh --install` builds `tidal/BootTidal.hs` for you by copying the stock one that shipped
with your Tidal install and appending `tidal/prelude.hs`. Re-run it after any `cabal v1-install
tidal` upgrade, since the stock file changes between versions.

If you want Ableton Link (Live as tempo master), uncomment the `streamEnableLink tidal` line in
that file — it's disabled by default in Tidal 1.10.

---

## 4. Session checklist

```
1. Live open, Live+SC selected, four tracks armed, monitor = In
2. SuperCollider: open sc/startup.scd, evaluate the ( ... ) block
   -> wait for "--- ambient-lab ready ---"
3. Optional: open sc/beds.scd, start Ndef(\bed).play(out: 2)
4. Editor: open tidal/sketches/01-drones.tidal, boot Tidal, evaluate `ambient`
5. Play. Record long. Arrange later.
```

Shutdown, in order: `hush` → `Ndef(\bed).clear(30)` → quit SC → quit Live. Killing SC while Live
is monitoring its inputs is harmless but produces a loud click, which is a bad way to end a
25-minute take.

---

## 5. Gotchas, in rough order of how likely they are to bite you

**BlackHole doesn't appear after install.** It's a kernel-adjacent driver. Restart, or
`sudo killall coreaudiod`.

**SuperCollider server fails to boot with a cryptic error.** Usually the microphone permission
prompt, or a sample-rate mismatch between the aggregate device and `s.options.sampleRate`. Set
`numInputBusChannels = 0` and confirm 48000 in both places.

**Tidal boots but there's silence.** Check the post window actually said `--- ambient-lab ready ---`
before you booted Tidal. Order matters: SuperDirt must be listening on port 57120 first. Also check
you didn't leave `orbit` pointing at a bus pair you haven't enabled in Live's Input Config.

**Some orbits are silent.** `~dirt.start(57120, [0, 2, 4, 6, 0, 0])` defines exactly six orbits.
`# orbit 6` addresses nothing. Add more entries to that array if you want more.

**Live shows input but the meters barely move.** SC's default output level is conservative and
these SynthDefs are deliberately quiet to leave headroom. Add gain in Tidal (`# gain 1.1`) rather
than turning Live's input trim up.

**Everything drifts out of sync over 10 minutes.** Drift Correction isn't enabled on BlackHole in
the aggregate device, or BlackHole is the clock source. Both are step 1.

**A Tidal pattern won't evaluate and GHCi complains about types.** Almost always operator
precedence: `$` is lowest, `#` binds tighter, and `|+|` family tighter still. When in doubt,
parenthesise aggressively. This is the single most common Tidal frustration and it is not you.
