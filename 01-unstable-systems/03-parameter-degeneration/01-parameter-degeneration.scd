// ============================================================
// parameterDegeneration_Granular.scd
//
// 01-unstable-systems / 03-Parameter-Degeneration
//
// CONCEPT
// -------
// The grain loses independence. In regimeIndependent, each grain
// has its own pitch, duration and pan. In regimeDegenerated, all
// grains are identical -> the granular cloud collapses into a
// periodic pulse. Degeneration = loss of grain variability.
//
// Signal flow:
//   [source: saw + noise] -> [grain engine: Dust + Latch]
//   -> [grain filter: BPF] -> [regime blend] -> [mix]
//   -> [parallel saturation] -> [stereo pan] -> [reverb] -> [out]
//
// LEVEL NOTES
// -----------
// - amp 0.65 and a +0.3 pre-saturation gain keep the patch
//   loud without hitting the limiter hard.
// - Grains are compensated (+1.6 after BPF) so short durations
//   do not disappear in the mix.
// - Limiter threshold is left at 0.95 so it works as a safety
//   net, not as a compressor.
// ============================================================

(
SynthDef(\parameterDegeneration_Granular, {
    |out = 0, amp = 0.65,
     switchRate = 0.28, degeneration = 0.0,
     // grain engine
     grainRate = 40, grainDur = 0.06,
     grainPitchSpread = 0.5, grainPanSpread = 0.8,
     // source
     sourceFreq = 180, sourceNoise = 0.15,
     // filter
     grainFilterFreq = 1800, grainFilterQ = 1.2,
     // sub
     subFreq = 42, subLevel = 0.32,
     // fx
     distAmt = 1.0, reverbMix = 0.42, roomSize = 0.92, damp = 0.25,
     rotateRate = 0.05, bufnum = 0|

    // --- threshold detection ---
    var parameter, delta, previous, crossing;
    var regimeIndependent, regimeDegenerated, transition, lagTime;

    // --- source banks ---
    var srcGrainRate, srcGrainDur, srcPitch, srcPan, srcFilter;
    var degGrainRate, degGrainDur, degPitch, degPan, degFilter;
    var paramGrainRate, paramGrainDur, paramPitch, paramPan, paramFilter;

    // --- grain engine ---
    var source, grainTrig, grainEnv, grainPitch, grainPan, grainSig;

    // --- sub + mix ---
    var sub, subEnv, mixedSignal, clean, clipped;

    // --- stereo + fx ---
    var panPos, panned, panL, panR, wet, signal;

    // ========================================================
    // 1. THRESHOLD DETECTION
    // ========================================================
    parameter = SinOsc.kr(switchRate).range(0.2, 0.8)
              + LFNoise1.kr(0.06).range(-0.1, 0.1);

    delta    = parameter - 0.5;
    previous = Delay1.kr(delta);
    crossing = ((delta >= 0) * (previous < 0))
             + ((delta < 0) * (previous >= 0));

    regimeIndependent = (delta < 0);
    regimeDegenerated = (delta >= 0);
    transition = Trig1.kr(crossing, 0.08);
    lagTime = 0.08 + (regimeDegenerated * 0.3);

    regimeIndependent = regimeIndependent * (1 - degeneration);
    regimeDegenerated = regimeDegenerated + (regimeIndependent * degeneration);
    regimeIndependent = regimeIndependent * (1 - degeneration);
    regimeDegenerated = Lag.kr(regimeDegenerated, lagTime);
    regimeIndependent = 1 - regimeDegenerated;

    // ========================================================
    // 2. SOURCE BANKS
    // src* : each grain parameter is free (independent)
    // deg* : all grain parameters follow `parameter` (degenerated)
    // ========================================================
    srcGrainRate = LFNoise1.kr(0.12).range(0.3, 2.5);
    srcGrainDur  = LFNoise2.kr(0.08).range(0.3, 2.5);
    srcPitch     = LFNoise1.kr(0.15).range(0.2, 2.0);
    srcPan       = LFNoise2.kr(0.10).range(0.2, 2.0);
    srcFilter    = LFNoise1.kr(0.05).range(0.5, 2.0);

    degGrainRate = parameter.range(0.4, 2.2);
    degGrainDur  = parameter.range(0.5, 2.0);
    degPitch     = parameter.range(0.6, 1.4);
    degPan       = parameter.range(0.5, 1.5);
    degFilter    = parameter.range(0.6, 1.6);

    paramGrainRate = (srcGrainRate * regimeIndependent) + (degGrainRate * regimeDegenerated);
    paramGrainDur  = (srcGrainDur  * regimeIndependent) + (degGrainDur  * regimeDegenerated);
    paramPitch     = (srcPitch     * regimeIndependent) + (degPitch     * regimeDegenerated);
    paramPan       = (srcPan       * regimeIndependent) + (degPan       * regimeDegenerated);
    paramFilter    = (srcFilter    * regimeIndependent) + (degFilter    * regimeDegenerated);

    // ========================================================
    // 3. GRAIN ENGINE
    // Dust triggers a granulator: each trigger opens a short
    // envelope with its own pitch and pan. As the system
    // degenerates, all grains converge to the same pitch/pan.
    // ========================================================
    source = Saw.ar(sourceFreq, 0.4) + (PinkNoise.ar(1) * sourceNoise);

    grainTrig = Dust.kr(
        (grainRate * paramGrainRate.range(0.3, 2.5)).clip(0.5, 80)
    );

    // Grain envelope with variable duration
    grainEnv = Decay2.kr(
        grainTrig,
        0.001,
        (grainDur * paramGrainDur.range(0.3, 2.5)).clip(0.008, 0.25)
    );

    // Grain pitch: per-grain random offset, collapses to zero
    grainPitch = (1 + (
        Latch.kr(WhiteNoise.kr(1), grainTrig)
        * grainPitchSpread
        * paramPitch.range(0.2, 2.0)
        * regimeIndependent
    ));

    // Grain pan: per-grain random position, collapses to center
    grainPan = Latch.kr(WhiteNoise.kr(1), grainTrig)
             * grainPanSpread
             * paramPan.range(0.2, 1.5)
             * regimeIndependent;

    grainSig = source * grainEnv;
    grainSig = BPF.ar(
        grainSig,
        (grainFilterFreq * paramFilter.range(0.4, 2.5)).clip(80, 9000),
        grainFilterQ.reciprocal
    );

    // Level compensation: BPF attenuates, AM also attenuates.
    grainSig = grainSig * 1.6;

    // Apply per-grain pitch (resample approximation: AM)
    grainSig = grainSig * SinOsc.ar(sourceFreq * grainPitch, 0, 0.9);

    // ========================================================
    // 4. SUB BASS
    // ========================================================
    sub = SinOsc.ar(subFreq * (1 + (regimeDegenerated * 0.5)), 0, 1.0);
    sub = LPF.ar(sub, 80 + (regimeDegenerated * 60));
    subEnv = LFNoise2.kr(0.06).range(0.5, 1.0);
    sub = sub * subEnv * subLevel * regimeIndependent;

    // ========================================================
    // 5. PARALLEL SATURATION
    // +0.3 pre-gain, clip to -0.85/0.85 so the limiter breathes.
    // ========================================================
    mixedSignal = (grainSig + sub) * 1.3;
    clean   = mixedSignal * (1 - (regimeDegenerated * distAmt * 0.3));
    clipped = (mixedSignal * (1 + (regimeDegenerated * distAmt * 3))).clip(-0.85, 0.85);
    mixedSignal = clean + clipped;

    // ========================================================
    // 6. STEREO + REVERB
    // grainPan is scaled to 0.6 so it stays focused.
    // ========================================================
    panPos = SinOsc.kr(rotateRate).range(-1, 1);
    panned = Pan2.ar(mixedSignal, (panPos + (grainPan * 0.6)).clip(-1, 1));
    panL = panned[0];
    panR = Pan2.ar(mixedSignal, (panPos.neg + (grainPan * 0.6)).clip(-1, 1))[1];

    wet = FreeVerb2.ar(panL, panR, 1.0,
        roomSize + (regimeDegenerated * 0.04),
        damp - (regimeDegenerated * 0.06));
    wet = LPF.ar(wet, 7500);

    signal = [
        (panL * (1 - reverbMix)) + (wet[0] * reverbMix * 0.85),
        (panR * (1 - reverbMix)) + (wet[1] * reverbMix * 0.85)
    ];

    signal = LeakDC.ar(signal);
    signal = Limiter.ar(signal, 0.95, 0.01);

    Out.ar(out, signal * amp);
    ScopeOut2.ar(signal, bufnum);

}).add;
)

s.sync;

(
~scopeBuf = Buffer.alloc(s, 2048, 2);

~parameterDegeneration_Granular = Synth(\parameterDegeneration_Granular, [
    \amp, 0.65,
    \switchRate, 0.28,
    \degeneration, 0.0,
    \grainRate, 40,
    \grainDur, 0.06,
    \grainPitchSpread, 0.5,
    \grainPanSpread, 0.8,
    \sourceFreq, 180,
    \sourceNoise, 0.15,
    \grainFilterFreq, 1800,
    \grainFilterQ, 1.2,
    \subFreq, 42,
    \subLevel, 0.32,
    \distAmt, 1.0,
    \reverbMix, 0.42,
    \roomSize, 0.92,
    \damp, 0.25,
    \rotateRate, 0.05,
    \bufnum, ~scopeBuf.bufnum
]);
)

// --- Degeneration states ---
~parameterDegeneration_Granular.set(\degeneration, 0.0);
~parameterDegeneration_Granular.set(\degeneration, 0.4);
~parameterDegeneration_Granular.set(\degeneration, 0.8);
~parameterDegeneration_Granular.set(\degeneration, 1.0);

// --- Grain density ---
~parameterDegeneration_Granular.set(\grainRate, 100, \grainDur, 0.02);
~parameterDegeneration_Granular.set(\grainRate, 12, \grainDur, 0.15);

// --- Wide grains (more independent material to collapse) ---
~parameterDegeneration_Granular.set(\grainPitchSpread, 0.9, \grainPanSpread, 1.0);
~parameterDegeneration_Granular.set(\grainPitchSpread, 0.1, \grainPanSpread, 0.2);

// --- Spectral grain focus ---
~parameterDegeneration_Granular.set(\grainFilterFreq, 800, \grainFilterQ, 3.0);
~parameterDegeneration_Granular.set(\grainFilterFreq, 4000, \grainFilterQ, 0.8);

// --- Extra loudness gestures ---
~parameterDegeneration_Granular.set(\amp, 0.75);
~parameterDegeneration_Granular.set(\subLevel, 0.4, \subFreq, 36);