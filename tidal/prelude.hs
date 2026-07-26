-- ============================================================
-- ambient-lab :: Tidal prelude
--
-- APPEND this to the END of your BootTidal.hs (it must come after the
-- `tidal <- startTidal ...` line and the d1..d16 definitions).
--
-- Find your BootTidal.hs:
--   macOS/Linux:  ~/.cabal/store/**/tidal-*/BootTidal.hs   (or your editor's copy)
--   Pulsar/VS Code: the extension setting "boot file path" points at it
--   or just:  ghc-pkg field tidal data-dir
--
-- While you're in there: uncomment `streamEnableLink tidal` if you want
-- Ableton Link sync (it is DISABLED by default in Tidal 1.10).
-- ============================================================

:{
let
    -- ---- tempo ------------------------------------------------
    -- 0.15 cps = one cycle every ~6.7 seconds. Ambient lives between 0.05 and 0.3.
    ambient = setcps 0.15
    glacial = setcps 0.05

    -- ---- voices (each pinned to its orbit / Ableton track) ----
    pad p   = p # s "ambPad"     # orbit 1
    drone p = p # s "ambDroneFM" # orbit 1
    wash p  = p # s "ambNoise"   # orbit 2
    glass p = p # s "ambGlass"   # orbit 3

    -- ---- shaping ---------------------------------------------
    -- note length in SECONDS (not cycles). This is the drone knob.
    hold n p  = p # sustain n # legato 1

    -- stereo position wandering over n cycles
    drift n p = p # pF "pos" (range (-0.9) 0.9 (slow n sine))

    -- amplitude breathing over n cycles
    swell n p = p # gain (range 0.7 1.05 (slow n sine))

    -- filter slowly opening and closing over n cycles
    open n p  = p # pF "cutoff" (range 250 5000 (slow n sine))

    -- detuning that grows and shrinks
    widen n p = p # pF "detune" (range 0.05 0.6 (slow n perlin))

    -- big reverb send
    haze p    = p # room 0.9 # size 0.95 # dry 0.2
    cathedral p = p # room 1.0 # size 0.99 # dry 0.05 # orbit 2

    -- ---- thickening ------------------------------------------
    -- an octave below, half a cycle later, quieter
    under p = superimpose ((|- note 12) . (0.5 ~>) . (# gain 0.8)) p
    -- a twelfth above, offset, quieter still
    over p  = superimpose ((|+ note 19) . (0.25 ~>) . (# gain 0.65)) p
    -- same note, more detuned, slightly later — the classic pad trick
    shimmer p = superimpose ((# pF "detune" 0.5) . (0.33 ~>) . (# gain 0.7)) p

    -- ---- erosion ---------------------------------------------
    -- drop events at random; ambient loves holes
    thin amt p = degradeBy amt p
:}

-- Common combination, so you don't retype it:
--   d1 $ slow 4 $ haze $ drift 17 $ open 23 $ hold 20 $ pad $ note "<c2 as1>"
