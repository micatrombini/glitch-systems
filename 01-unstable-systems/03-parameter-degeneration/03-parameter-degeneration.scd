// ============================================================
// parameterDegeneration_Resonant.scd
//
// 01-unstable-systems / 03-Parameter-Degeneration
//
// CONCEPT
// -------
// The resonance loses independence. In regimeIndependent, each
// resonator has its own frequency and decay. In regimeDegenerated,
// all resonators tune to the same frequency -> the system
// collapses into a single resonant body. Degeneration = loss of
// resonant diversity.
//
// Signal flow:
//   [exciter: noise + FM] -> [3 CombC resonators]
//   -> [regime blend] -> [mix] -> [parallel saturation]
//   -> [stereo] -> [reverb] -> [out]
//
// LEVEL NOTES
// -----------
// - amp 0.65 and +1.3 pre-saturation gain keep the patch loud.
// - CombC resonators attenuate; compensated by x1.4 on the sum.
// - Limiter at 0.95 works as a safety net, not a compressor.
// - Reverb at 0.45 keeps the resonances defined.
// ============================================================

(
SynthDef(\parameterDegeneration_Resonant, {
    |out = 0, amp = 0.65,
     switchRate = 0.28, degeneration = 0.0,
     // exciters
     noiseAmt = 0.5, fmCarrier = 220, fmRatio = 1.4142, fmIndex = 1.2,
     // resonators
     res1Freq = 220, res2Freq = 330, res3Freq = 440,
     resDecay = 2.0,
     // sub
     subFreq = 42, subLevel = 0.32,
     // fx
     distAmt = 1.0, reverbMix = 0.45, roomSize = 0.94, damp = 0.22,
     rotateRate = 0.05, bufnum = 0|

    // --- threshold detection ---
    var parameter, delta, previous, crossing;
    var regimeIndependent, regimeDegenerated, transition, lagTime;

    // --- source banks ---
    var srcRes1, srcRes2, srcRes3, srcDecay;
    var degRes1, degRes2, degRes3, degDecay;
    var paramRes1, paramRes2, paramRes3, paramDecay;

    // --- exciters ---
    var fmMod, fm, noise, exciter;

    // --- resonators ---
    var res1, res2, res3, resonantSignal;

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
    // src* : each resonator has its own tuning (independent)
    // deg* : all resonators tune to `parameter` (degenerated)
    // ========================================================
    srcRes1 = LFNoise1.kr(0.07).range(0.5, 2.0);
    srcRes2 = LFNoise2.kr(0.05).range(0.5, 2.0);
    srcRes3 = LFNoise1.kr(0.09).range(0.5, 2.0);
    srcDecay = LFNoise2.kr(0.04).range(0.5, 2.0);

    degRes1 = parameter.range(0.6, 1.6);
    degRes2 = parameter.range(0.6, 1.6);
    degRes3 = parameter.range(0.6, 1.6);
    degDecay = parameter.range(0.7, 1.4);

    paramRes1 = (srcRes1 * regimeIndependent) + (degRes1 * regimeDegenerated);
    paramRes2 = (srcRes2 * regimeIndependent) + (degRes2 * regimeDegenerated);
    paramRes3 = (srcRes3 * regimeIndependent) + (degRes3 * regimeDegenerated);
    paramDecay = (srcDecay * regimeIndependent) + (degDecay * regimeDegenerated);

    // ========================================================
    // 3. EXCITERS
    // ========================================================
    fmMod = SinOsc.ar(fmCarrier * fmRatio, 0, fmIndex);
    fm = SinOsc.ar(fmCarrier + (fmMod * fmCarrier * 0.5), 0, 1.0);
    noise = PinkNoise.ar(1) * noiseAmt;
    exciter = (fm * 0.5) + noise;

    // ========================================================
    // 4. THREE COMB RESONATORS
    // In regimeDegenerated, all three tune to the same master
    // frequency -> they fuse into a single resonant body.
    // Level compensated by x1.4 on the sum.
    // ========================================================
    res1 = CombC.ar(exciter, 0.1,
        (1 / (res1Freq * paramRes1.range(0.5, 2.0))).clip(0.002, 0.05),
        resDecay * paramDecay);
    res2 = CombC.ar(exciter, 0.1,
        (1 / (res2Freq * paramRes2.range(0.5, 2.0))).clip(0.002, 0.05),
        resDecay * paramDecay);
    res3 = CombC.ar(exciter, 0.1,
        (1 / (res3Freq * paramRes3.range(0.5, 2.0))).clip(0.002, 0.05),
        resDecay * paramDecay);

    resonantSignal = (res1 + res2 + res3) * 0.33 * 1.4;

    // ========================================================
    // 5. SUB BASS
    // ========================================================
    sub = SinOsc.ar(subFreq * (1 + (regimeDegenerated * 0.5)), 0, 1.0);
    sub = LPF.ar(sub, 80 + (regimeDegenerated * 60));
    subEnv = LFNoise2.kr(0.06).range(0.5, 1.0);
    sub = sub * subEnv * subLevel * regimeIndependent;

    // ========================================================
    // 6. PARALLEL SATURATION
    // +1.3 pre-gain, clip to -0.85/0.85 so the limiter breathes.
    // ========================================================
    mixedSignal = (resonantSignal + sub) * 1.3;
    clean   = mixedSignal * (1 - (regimeDegenerated * distAmt * 0.3));
    clipped = (mixedSignal * (1 + (regimeDegenerated * distAmt * 3))).clip(-0.85, 0.85);
    mixedSignal = clean + clipped;

    // ========================================================
    // 7. STEREO + REVERB
    // ========================================================
    panPos = SinOsc.kr(rotateRate).range(-1, 1);
    panned = Pan2.ar(mixedSignal, panPos);
    panL = panned[0];
    panR = Pan2.ar(mixedSignal, panPos.neg)[1];

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

~parameterDegeneration_Resonant = Synth(\parameterDegeneration_Resonant, [
    \amp, 0.65,
    \switchRate, 0.28,
    \degeneration, 0.0,
    \noiseAmt, 0.5,
    \fmCarrier, 220,
    \fmRatio, 1.4142,
    \fmIndex, 1.2,
    \res1Freq, 220,
    \res2Freq, 330,
    \res3Freq, 440,
    \resDecay, 2.0,
    \subFreq, 42,
    \subLevel, 0.32,
    \distAmt, 1.0,
    \reverbMix, 0.45,
    \roomSize, 0.94,
    \damp, 0.22,
    \rotateRate, 0.05,
    \bufnum, ~scopeBuf.bufnum
]);
)

// --- Degeneration states ---
~parameterDegeneration_Resonant.set(\degeneration, 0.0);
~parameterDegeneration_Resonant.set(\degeneration, 0.4);
~parameterDegeneration_Resonant.set(\degeneration, 0.8);
~parameterDegeneration_Resonant.set(\degeneration, 1.0);

// --- Resonator tuning (harmonic, then inharmonic) ---
~parameterDegeneration_Resonant.set(\res1Freq, 220, \res2Freq, 440, \res3Freq, 660);
~parameterDegeneration_Resonant.set(\res1Freq, 220, \res2Freq, 311, \res3Freq, 487);

// --- Long decay (metallic) vs short (dry) ---
~parameterDegeneration_Resonant.set(\resDecay, 4.0, \reverbMix, 0.55);
~parameterDegeneration_Resonant.set(\resDecay, 0.4, \reverbMix, 0.3);

// --- More exciter noise vs more FM ---
~parameterDegeneration_Resonant.set(\noiseAmt, 0.8, \fmIndex, 0.3);
~parameterDegeneration_Resonant.set(\noiseAmt, 0.1, \fmIndex, 3.0);

// --- Slow switching (long stable regimes) ---
~parameterDegeneration_Resonant.set(\switchRate, 0.08);

// --- Extra loudness gestures ---
~parameterDegeneration_Resonant.set(\amp, 0.75);
~parameterDegeneration_Resonant.set(\subLevel, 0.4, \subFreq, 36);