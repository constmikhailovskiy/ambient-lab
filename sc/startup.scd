// ============================================================
// ambient-lab :: SuperCollider startup
// Put the cursor inside the big ( ... ) block and press Ctrl/Cmd+Enter.
// Wait for "--- ambient-lab ready ---" before booting Tidal.
// ============================================================

// EDIT THIS ONCE: absolute path to the repo's sc/ folder
~lab = "/Users/konstie/ambient-lab/sc";

(
// ---- server config -----------------------------------------
s.options.numBuffers = 1024 * 256;
s.options.memSize = 8192 * 32;
s.options.numWireBufs = 256;
s.options.maxNodes = 1024 * 32;

// 8 output channels => 4 stereo pairs => 4 tracks in Ableton (see README Tier 1)
s.options.numOutputBusChannels = 8;

// 0 avoids the macOS microphone-permission prompt, which if missed makes the
// server fail to boot with an error that never mentions permissions.
s.options.numInputBusChannels = 0;

s.options.sampleRate = 48000;         // must match your aggregate device in Audio MIDI Setup
s.options.hardwareBufferSize = 512;   // raise to 1024 if you get glitches; latency is fine for ambient

// Uncomment once BlackHole is installed (see MACOS-SETUP.md step 1).
// SC writes straight into BlackHole; Live reads it via the aggregate device.
// s.options.outDevice = "BlackHole 16ch";

s.latency = 0.3;   // generous scheduling headroom

s.waitForBoot {

	~dirt = SuperDirt(2, s);
	~dirt.loadSoundFiles;                      // the Dirt-Samples library
	// ~dirt.loadSoundFiles("~/my-samples/*");  // your own field recordings, drones, etc.

	// custom SynthDefs
	(~lab +/+ "drones.scd").load;

	s.sync;

	// ---- orbits -> output buses --------------------------------
	~dirt.start(57120, 0 ! 6);

	// nicer default reverb tails for ambient work
	~dirt.orbits.do { |x| x.set(\dryBus, x.dryBus) };

	// ---- MIDI out (Ableton + MicroFreak) — Tier 3 --------------
	// Enable the IAC Driver in Audio MIDI Setup first (MACOS-SETUP.md step 2).
	// Get your exact port names by evaluating this on its own:
	//   MIDIClient.init;
	//   MIDIClient.destinations.do { |d, i| [i, d.device, d.name].postln };
	// Then uncomment and fix the strings below.
	/*
	MIDIClient.init;

	// -> Ableton Live instruments, via the virtual IAC cable
	~midiLive = MIDIOut.newByName("IAC Driver", "Bus 1");
	~midiLive.latency = 0.02;
	~dirt.soundLibrary.addMIDI(\live, ~midiLive);

	// -> MicroFreak, directly over USB (NOT through IAC)
	~midiFreak = MIDIOut.newByName("MicroFreak", "MicroFreak");
	~midiFreak.latency = 0.02;
	~dirt.soundLibrary.addMIDI(\freak, ~midiFreak);

	// In Tidal:  # s "live"   or   # s "freak"   plus  # midichan 0
	*/

	"--- ambient-lab ready ---".postln;
};
)

// ---- handy one-liners (evaluate individually) ----------------
// s.meter;                      // level meters
// s.plotTree;                   // see what's running
// s.record(numChannels: 8);     // start recording all 8 buses to a WAV
// s.stopRecording;
// ~dirt.orbits[1].globalEffects.postln;
// Cmd+. / Ctrl+.                // panic: kill all sound

// Synth(\ambPad, [\freq, 110, \sustain, 10, \amp, 0,5]);

s.serverRunning;
