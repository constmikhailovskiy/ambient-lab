// ============================================================
// ambient-lab :: SynthDefs
// Loaded by startup.scd. Re-evaluate any single block to hot-swap it
// while everything is running — that's the whole point.
//
// Conventions:
//   freq     set by Tidal's  n / note
//   sustain  length in SECONDS, set by Tidal's  # sustain 12
//   pos      stereo position -1..1  (custom; use  # pF "pos" 0.5 )
//   everything else is a custom param: # pF "detune" 0.3
// ============================================================

(
// ---------- ambPad ------------------------------------------
// Detuned saw stack under a wandering lowpass. Your workhorse chord/drone voice.
SynthDef(\ambPad, { |out = 0, freq = 110, sustain = 4, pos = 0, amp = 0.5,
	detune = 0.15, cutoff = 1200, res = 0.3, spread = 0.8,
	lfo = 0.08, sub = 0.4, atk = 0.35, rel = 0.4|

	var voices = 7, env, freqs, sig, cf, stereo;

	env = EnvGen.ar(
		Env([0, 1, 1, 0], [atk, (1 - atk - rel).max(0.02), rel], \sin),
		timeScale: sustain, doneAction: 2);

	freqs = Array.fill(voices, { |i|
		var offset = (i - ((voices - 1) / 2)) / voices;
		freq * (1 + (detune * offset * LFNoise2.kr(0.03 + 0.06.rand).range(0.7, 1.3)))
	});

	sig = VarSaw.ar(freqs, Array.rand(voices, 0.0, 1.0),
		LFNoise2.kr(0.05).range(0.2, 0.8));
	sig = Mix(sig) / voices;
	sig = sig + (sub * SinOsc.ar(freq * 0.5));

	cf = (cutoff * LFNoise2.kr(lfo).exprange(0.5, 2.5)).clip(60, 16000);
	sig = RLPF.ar(sig, cf, (1 - res).clip(0.05, 1.0));
	sig = LeakDC.ar(sig);

	stereo = Splay.ar([sig, DelayC.ar(sig, 0.06, 0.023)], spread);
	stereo = Balance2.ar(stereo[0], stereo[1], pos.clip(-1, 1));

	OffsetOut.ar(out, stereo * env * amp);
}).add;


// ---------- ambDroneFM --------------------------------------
// Two-operator FM with slowly drifting index. Good for deep, breathing low drones.
// Try: ratio 1.5 / 2.01 / 3.14 (inharmonic gets metallic fast)
SynthDef(\ambDroneFM, { |out = 0, freq = 55, sustain = 8, pos = 0, amp = 0.45,
	ratio = 1.5, index = 3, drift = 0.1, tone = 4000, atk = 0.4, rel = 0.4|

	var env, mod, sig, stereo;

	env = EnvGen.ar(
		Env([0, 1, 1, 0], [atk, (1 - atk - rel).max(0.02), rel], \sin),
		timeScale: sustain, doneAction: 2);

	mod = SinOsc.ar(
		freq * ratio * LFNoise2.kr(drift).range(0.994, 1.006), 0,
		freq * index * LFNoise2.kr(0.05).range(0.15, 1.0));

	sig = SinOsc.ar(freq + mod) + (0.5 * SinOsc.ar((freq * 2) + (mod * 0.3)));
	sig = LPF.ar(sig, tone.clip(200, 16000));

	stereo = [sig, DelayC.ar(sig, 0.05, LFNoise2.kr(0.03).range(0.004, 0.04))];
	stereo = Balance2.ar(stereo[0], stereo[1], pos.clip(-1, 1));

	OffsetOut.ar(out, stereo * env * amp);
}).add;


// ---------- ambNoise ----------------------------------------
// A bank of narrow bandpass filters on pink/brown noise, each wandering
// independently. Noise as harmony rather than noise as texture.
// bw near 0 => almost pitched. bw near 1 => a wash.
SynthDef(\ambNoise, { |out = 0, freq = 300, sustain = 6, pos = 0, amp = 0.4,
	bw = 0.4, motion = 0.05, spread = 0.9, atk = 0.4, rel = 0.4|

	var env, src, bands, stereo;

	env = EnvGen.ar(
		Env([0, 1, 1, 0], [atk, (1 - atk - rel).max(0.02), rel], \sin),
		timeScale: sustain, doneAction: 2);

	src = PinkNoise.ar(1) + (0.3 * BrownNoise.ar(1));

	bands = Array.fill(6, { |i|
		var f = freq * (i + 1)
			* LFNoise2.kr(motion * (0.4 + (i * 0.3))).range(1 - bw, 1 + bw);
		BPF.ar(src, f.clip(30, 16000), 0.02 + (bw * 0.15), 4)
	});

	stereo = Splay.ar(bands, spread) / 3;
	stereo = stereo * LFNoise2.kr(motion).range(0.3, 1.0);
	stereo = Balance2.ar(stereo[0], stereo[1], pos.clip(-1, 1));

	OffsetOut.ar(out, stereo * env * amp);
}).add;


// ---------- ambGlass ----------------------------------------
// Bank of resonators struck once by a noise burst. Bell/glass/prepared-piano.
// Use for the melodic layer above the drone.
SynthDef(\ambGlass, { |out = 0, freq = 440, sustain = 6, pos = 0, amp = 0.4,
	decay = 4, blur = 0.02, spread = 0.7|

	var ratios = [1, 2.01, 3.02, 4.13, 5.4, 6.83];
	var amps   = ratios.collect { |r| 1 / (r * r) };
	var env, decs, exciter, sig, stereo;

	env = EnvGen.ar(Env([0, 1, 1, 0], [0.001, 0.9, 0.099], \sin),
		timeScale: sustain, doneAction: 2);

	decs = ratios.collect { |r| decay / r.sqrt };
	exciter = Decay2.ar(Impulse.ar(0), 0.002, blur.clip(0.001, 0.5))
		* PinkNoise.ar(1);

	sig = DynKlank.ar(`[ratios * freq, amps, decs], exciter) * 0.3;
	sig = LeakDC.ar(sig);

	stereo = Splay.ar([sig, DelayC.ar(sig, 0.04, 0.017)], spread);
	stereo = Balance2.ar(stereo[0], stereo[1], pos.clip(-1, 1));

	OffsetOut.ar(out, stereo * env * amp);
}).add;

"ambient-lab synths: ambPad, ambDroneFM, ambNoise, ambGlass".postln;
)
