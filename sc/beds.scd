// ============================================================
// ambient-lab :: BEDS  (continuous drones, JITLib)
//
// This is the layer Tidal is bad at: one voice that never retriggers and
// that you slowly deform by hand. Edit a function body, re-evaluate it,
// and it CROSSFADES into the new version over `fadeTime` seconds.
//
// NOTE: use Ndef, not `ProxySpace.push(s)`. Pushing a ProxySpace replaces the
// current environment, which breaks the `~dirt` reference SuperDirt needs.
// Ndef gives you the same live-rewiring without hijacking anything.
//
// Reverb lives in Ableton (or add an Ndef effect proxy later). Keep these dry.
// ============================================================

// ---------- 1. harmonic bed ---------------------------------
// Nine partials of a low fundamental, each beating against the others.
// Change `f`, the partial count, or the amplitude curve, then re-evaluate.
(
Ndef(\bed).fadeTime = 20;
Ndef(\bed, {
	var f = 55;                     // fundamental — try 41.2 (E1), 48.99 (G1), 55 (A1)
	var partials = 9;
	var sig = Mix.fill(partials, { |i|
		var drift = LFNoise2.kr(rrand(0.01, 0.06)).range(0.996, 1.004);
		var amp = LFNoise2.kr(rrand(0.02, 0.09)).range(0.0, 1.0) / (i + 2);
		SinOsc.ar(f * (i + 1) * drift, 0, amp)
	});
	sig = LPF.ar(sig, LFNoise2.kr(0.03).exprange(300, 3000));
	sig = sig.tanh * 0.4;
	Splay.ar([sig, DelayC.ar(sig, 0.05, 0.031)], 0.9)
});
)
Ndef(\bed).play(out: 2);       // -> bus 2/3, "Mobile 2" in Ableton
// Ndef(\bed).stop(30);        // fade out over 30s
// Ndef(\bed).clear(30);


// ---------- 2. air / noise bed ------------------------------
// Resonant noise. Push `q` up for something almost pitched.
(
Ndef(\air).fadeTime = 25;
Ndef(\air, {
	var src = PinkNoise.ar(0.6);
	var q = 0.04;
	var freqs = [110, 165, 220, 277, 330, 440, 660];
	var sig = Mix.fill(freqs.size, { |i|
		BPF.ar(src,
			freqs[i] * LFNoise2.kr(rrand(0.01, 0.05)).range(0.97, 1.03),
			q, 3) * LFNoise2.kr(rrand(0.01, 0.04)).range(0.0, 1.0)
	});
	sig = HPF.ar(sig, 60);
	Splay.ar([sig, DelayC.ar(sig, 0.08, 0.043)], 1.0) * 0.5
});
)
Ndef(\air).play(out: 4);       // -> bus 4/5, "Mobile 3"


// ---------- 3. granular bed --------------------------------
// Point this at any long file: a field recording, a bowed cello note,
// a bounce of your own MicroFreak patch. This is where the good stuff is.
// ~grainBuf = Buffer.read(s, "~/samples/long-thing.wav".standardizePath);
(
Ndef(\gran).fadeTime = 20;
Ndef(\gran, {
	var buf = ~grainBuf;
	var trig = Dust.ar(LFNoise2.kr(0.05).range(4, 25));
	var pos = (LFNoise2.kr(0.015).range(0.05, 0.95)
		+ TRand.ar(-0.01, 0.01, trig)) * BufDur.kr(buf);
	var sig = TGrains.ar(2, trig, buf,
		LFNoise2.kr(0.03).exprange(0.5, 2.0),     // playback rate
		pos,
		LFNoise2.kr(0.04).range(0.15, 0.8),       // grain duration
		TRand.ar(-1, 1, trig),                    // pan per grain
		0.6);
	LPF.ar(sig, 6000) * 0.8
});
)
// Ndef(\gran).play(out: 6);   // -> bus 6/7, "Mobile 4"


// ---------- working with these ------------------------------
// Ndef(\bed).fadeTime = 45;              // slower crossfades = more "ambient"
// Ndef(\bed).set(\foo, 0.5);             // if you add |foo = 0| args to the function
// Ndef.all.postln;
// Ndef(\bed).clear(20); Ndef(\air).clear(20); Ndef(\gran).clear(20);
