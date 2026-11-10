// ============================================================
// parameterDegeneration_Holographic.scd
//
// 01-unstable-systems / 03-Parameter-Degeneration
//
// CONCEPT
// -------
// A system with multiple variables progressively loses independence
// between its parameters. Internal relations contract, synchronize
// or collapse.
//
// This patch makes the collapse *audible* through a holographic
// projection: the sound has no fixed point of origin. Phase
// dispersion, rotating bodies, mid/side image motion and a
// pre-delayed reverb space place the source "behind" the listener.
//
// TWO REGIMES
// -----------
// - regimeIndependent : each parameter follows its own noise source.
//                       The system is alive, unpredictable.
// - regimeDegenerated : each parameter follows the master parameter.
//                       The system is deterministic, mechanical.
//
// The threshold detector decides WHEN the system crosses from
// independent to degenerated. The `degeneration` argument decides
// IF the crossing sticks (0 = always independent, 1 = once
// degenerated it stays degenerated).
//
// SIGNAL ARCHITECTURE
// -------------------
// 1. Threshold detection (Sine + LFNoise1 -> delta -> crossing)
// 2. Two independent source banks (src* and deg*)
// 3. Regime blend -> effective parameters (param*)
// 4. FM pair with irrational ratio (inharmonic spectrum)
// 5. Dust + Latch glitch engine (buffer-stall artifacts)
// 6. CombC resonant layer + 3-stage AllpassC dispersion chain
// 7. Detuned saws with opposite FreqShift on sine layers (rotating body)
// 8. Synthetic voice: Formlet bank (ghostly formants)
// 9. Noise layer (pink + white, band-passed)
// 10. Sub-bass sine with regime-dependent glide
// 11. Parallel clean/clipped saturation
// 12. Pan2 + Mid/Side rotation (holographic image)
// 13. Pre-delay before FreeVerb2 (space behind source)
// 14. LeakDC + Limiter + ScopeOut2
//
// HOW TO RUN
// ----------
// 1. Boot the server: s.boot
// 2. Execute the SynthDef block
// 3. Execute the instantiation block (allocates ~scopeBuf)
// 4. Use the presets to explore degeneration states
// ============================================================

(
SynthDef(\parameterDegeneration_Holographic, {
    |out = 0, amp = 0.42,
     // --- threshold detection ---
     switchRate = 0.28, degeneration = 0.0,
     // --- FM source ---
     fmCarrier = 110, fmRatio = 1.4142, fmIndex = 1.4,
     // --- glitch engine ---
     dustRate = 14, latchDepth = 0.85, gateRate = 18,
     // --- noise layer ---
     noiseAmt = 0.28,
     // --- comb + allpass (holographic dispersion) ---
     combFreq = 220, combDecay = 3.0, combMix = 0.5,
     allpassFreq = 1200, allpassDecay = 0.8,
     // --- Arca drone ---
     droneFreq = 55, droneLevel = 0.35, droneDetune = 0.012,
     freqShiftL = 0.7, freqShiftR = 1.3,
     // --- synthetic voice ---
     voiceFreq = 330, voiceLevel = 0.22, voiceFormletDecay = 0.22,
     // --- sub bass ---
     subFreq = 40, subLevel = 0.22,
     // --- saturation + space ---
     distAmt = 1.2, preDelay = 0.07,
     reverbMix = 0.55, roomSize = 0.96, damp = 0.22,
     // --- stereo motion ---
     rotateRate = 0.04, msRotateRate = 0.015, msDepth = 0.85,
     // --- scope ---
     bufnum = 0|

    // --- threshold detection ---
    var parameter, delta, previous, crossing;
    var regimeIndependent, regimeDegenerated, transition, lagTime;

    // --- source banks (independent vs degenerated) ---
    var srcDust, srcRatio, srcIndex, srcGate, srcComb, srcVoice, srcCombDecay;
    var degDust, degRatio, degIndex, degGate, degComb, degVoice, degCombDecay;
    var paramDust, paramRatio, paramIndex, paramGate;
    var paramComb, paramVoice, paramCombDecay;

    // --- FM source ---
    var fmMod, fm;

    // --- glitch engine ---
    var glitchTrig, glitchEnv, glitchSig, gate;

    // --- comb + allpass ---
    var comb, combMod, combSig;
    var ap1, ap2, ap3, allpassChain;

    // --- drone ---
    var droneSawL, droneSawR, droneSinL, droneSinR;
    var shiftL, shiftR, drone, droneEnv;

    // --- voice ---
    var voiceSrc, voiceF1, voiceF2, voiceF3, voiceSig, voiceEnv;

    // --- noise + sub ---
    var noiseSrc, noiseFilt;
    var sub, subEnv, subDuck;

    // --- saturation + stereo ---
    var glitchBus, clean, clipped;
    var panPos, panned, panL, panR;
    var mid, side, midSideRotation, midRot, sideRot;
    var dryL, dryR, preL, preR, scopeL, scopeR, wet, signal;

    // ========================================================
    // 1. THRESHOLD DETECTION
    // A slow Sine + small LFNoise1 define a wandering parameter.
    // Crossing 0.5 flips the system between two regimes.
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

    // degeneration gate: 0 = always independent, 1 = crossing sticks
    regimeIndependent = regimeIndependent * (1 - degeneration);
    regimeDegenerated = regimeDegenerated + (regimeIndependent * degeneration);
    regimeIndependent = regimeIndependent * (1 - degeneration);

    regimeDegenerated = Lag.kr(regimeDegenerated, lagTime);
    regimeIndependent = 1 - regimeDegenerated;

    // ========================================================
    // 2. SOURCE BANKS
    // src* : each parameter has its own noise clock (independent)
    // deg* : all parameters follow `parameter` (degenerated)
    // ========================================================
    srcDust      = LFNoise1.kr(0.11).range(0.2, 2.5);
    srcRatio     = LFNoise1.kr(0.05).range(1.0, 3.0);
    srcIndex     = LFNoise2.kr(0.09).range(0.2, 3.0);
    srcGate      = LFNoise1.kr(0.13).range(0.5, 3.0);
    srcComb      = LFNoise2.kr(0.04).range(0.5, 2.0);
    srcVoice     = LFNoise1.kr(0.07).range(0.4, 2.2);
    srcCombDecay = LFNoise2.kr(0.03).range(0.6, 1.6);

    degDust      = parameter.range(0.3, 2.0);
    degRatio     = parameter.range(1.2, 3.0);
    degIndex     = parameter.range(0.4, 3.0);
    degGate      = parameter.range(0.6, 2.0);
    degComb      = parameter.range(0.6, 1.8);
    degVoice     = parameter.range(0.5, 2.0);
    degCombDecay = parameter.range(0.7, 1.4);

    // ========================================================
    // 3. REGIME BLEND -> effective parameters
    // ========================================================
    paramDust      = (srcDust      * regimeIndependent) + (degDust      * regimeDegenerated);
    paramRatio     = (srcRatio     * regimeIndependent) + (degRatio     * regimeDegenerated);
    paramIndex     = (srcIndex     * regimeIndependent) + (degIndex     * regimeDegenerated);
    paramGate      = (srcGate      * regimeIndependent) + (degGate      * regimeDegenerated);
    paramComb      = (srcComb      * regimeIndependent) + (degComb      * regimeDegenerated);
    paramVoice     = (srcVoice     * regimeIndependent) + (degVoice     * regimeDegenerated);
    paramCombDecay = (srcCombDecay * regimeIndependent) + (degCombDecay * regimeDegenerated);

    // ========================================================
    // 4. FM SOURCE
    // Irrational ratio -> inharmonic, digital, unstable spectrum.
    // ========================================================
    fmMod = SinOsc.ar(
        fmCarrier * paramRatio.range(1.0, 4.0),
        0,
        fmIndex * paramIndex.range(0.2, 4.0)
    );
    fm = SinOsc.ar(fmCarrier + (fmMod * fmCarrier * 0.5), 0, 1.0);

    // ========================================================
    // 5. GLITCH ENGINE
    // Dust triggers a Latch on the FM signal: buffer-stall
    // artifacts, stutter, digital freeze.
    // ========================================================
    glitchTrig = Dust.kr((dustRate * paramDust.range(0.2, 3.0)).clip(0.5, 60));
    glitchEnv  = Decay2.kr(glitchTrig, 0.001, 0.05);
    glitchSig  = (fm * (1 - (glitchEnv * latchDepth)))
               + (Latch.kr(fm, glitchTrig) * glitchEnv * latchDepth);

    gate = LFPulse.kr(
        (gateRate * paramGate.range(0.5, 3.0)).clip(0.5, 60), 0, 0.5
    ).range(0.1, 1.0);
    glitchSig = glitchSig * gate;

    // ========================================================
    // 6. COMB + ALLPASS CHAIN (holographic dispersion)
    // CombC gives metallic resonance; three AllpassC stages
    // smear the phase so the source has no fixed origin.
    // ========================================================
    combMod = LFNoise2.kr(0.08).range(0.5, 1.6) * paramCombDecay;
    comb = CombC.ar(
        glitchSig,
        0.2,
        (1 / (combFreq * paramComb.range(0.5, 2.0))).clip(0.002, 0.05),
        combDecay * combMod
    );
    combSig = (glitchSig * (1 - combMix)) + (comb * combMix);

    ap1 = AllpassC.ar(combSig, 0.1, 1 / allpassFreq, allpassDecay);
    ap2 = AllpassC.ar(ap1, 0.1, 1 / (allpassFreq * 1.7), allpassDecay);
    ap3 = AllpassC.ar(ap2, 0.1, 1 / (allpassFreq * 2.9), allpassDecay);
    allpassChain = (ap1 * 0.4) + (ap2 * 0.35) + (ap3 * 0.25);

    // ========================================================
    // 7. ARCA DRONE
    // Detuned saws + FreqShift on sine layers. Different shifts
    // L/R make the body rotate inside the stereo field.
    // ========================================================
    droneSawL = Saw.ar(droneFreq * (1 + droneDetune), 0.3);
    droneSawR = Saw.ar(droneFreq * (1 - droneDetune), 0.3);
    droneSinL = SinOsc.ar(droneFreq * 2, 0, 0.3);
    droneSinR = SinOsc.ar(droneFreq * 2.01, 0, 0.3);
    shiftL = FreqShift.ar(droneSinL, freqShiftL);
    shiftR = FreqShift.ar(droneSinR, freqShiftR);
    drone = [droneSawL + shiftL, droneSawR + shiftR];
    drone = CombC.ar(drone, 0.5, 1 / droneFreq, 4.0);
    droneEnv = LFNoise2.kr(0.03).range(0.4, 1.0);
    drone = drone * droneEnv * droneLevel;

    // ========================================================
    // 8. SYNTHETIC VOICE
    // Formlet bank (ghostly formants). Shorter decay than a
    // drone, longer than a percussive hit.
    // ========================================================
    voiceSrc = Saw.ar(voiceFreq * paramVoice.range(0.5, 2.0), 0.4);
    voiceSrc = voiceSrc + (PinkNoise.ar(0.05));
    voiceF1 = Formlet.ar(voiceSrc, 700  * paramVoice.range(0.7, 1.3), 0.003, voiceFormletDecay);
    voiceF2 = Formlet.ar(voiceSrc, 1200 * paramVoice.range(0.7, 1.3), 0.003, voiceFormletDecay);
    voiceF3 = Formlet.ar(voiceSrc, 2600 * paramVoice.range(0.7, 1.3), 0.003, voiceFormletDecay);
    voiceSig = (voiceF1 + voiceF2 + voiceF3) * 0.4;
    voiceEnv = LFNoise2.kr(0.05).range(0.2, 1.0);
    voiceSig = voiceSig * voiceEnv * voiceLevel;

    // ========================================================
    // 9. NOISE LAYER
    // ========================================================
    noiseSrc = PinkNoise.ar(1) + (WhiteNoise.ar(0.3));
    noiseFilt = BPF.ar(noiseSrc, 2400, 0.6) * noiseAmt;

    // ========================================================
    // 10. SUB BASS
    // Glides up in regimeDegenerated; ducked on transitions
    // (same gesture as subFilterSwitch).
    // ========================================================
    sub = SinOsc.ar(subFreq * (1 + (regimeDegenerated * 0.5)), 0, 1.0);
    sub = LPF.ar(sub, 80 + (regimeDegenerated * 60));
    subEnv = LFNoise2.kr(0.06).range(0.5, 1.0);
    sub = sub * subEnv * subLevel * regimeIndependent;
    subDuck = 1 - (Decay2.ar(K2A.ar(transition), 0.01, 0.25) * 0.45);
    sub = sub * subDuck;

    // ========================================================
    // 11. PARALLEL SATURATION
    // Clean path + clipped path, mixed by regime.
    // ========================================================
    glitchBus = allpassChain + voiceSig + noiseFilt + sub;
    clean   = glitchBus * (1 - (regimeDegenerated * distAmt * 0.3));
    clipped = (glitchBus * (1 + (regimeDegenerated * distAmt * 3))).clip(-0.9, 0.9);
    glitchBus = clean + clipped;

    // ========================================================
    // 12. STEREO: PAN + MID/SIDE ROTATION
    // Pan moves the source. Mid/Side rotation opens and closes
    // the image without moving the source: holographic effect.
    // ========================================================
    panPos = SinOsc.kr(rotateRate).range(-1, 1);
    panned = Pan2.ar(glitchBus, panPos);
    panL = panned[0];
    panR = Pan2.ar(glitchBus, panPos.neg)[1];

    mid  = (panL + panR) * 0.5;
    side = (panL - panR) * 0.5;
    midSideRotation = SinOsc.kr(msRotateRate).range(-1, 1) * msDepth;
    midRot  = mid  * (1 - midSideRotation);
    sideRot = side * (1 + midSideRotation);
    panL = midRot + sideRot;
    panR = midRot - sideRot;

    dryL = panL + drone[0];
    dryR = panR + drone[1];
    dryR = dryR + DelayC.ar(dryR, 0.02, 0.011);

    // ========================================================
    // 13. PRE-DELAY + REVERB
    // Pre-delay places the space *behind* the source. Reverb
    // opens with regimeDegenerated.
    // ========================================================
    preL = DelayC.ar(dryL, 0.2, preDelay);
    preR = DelayC.ar(dryR, 0.2, preDelay);

    scopeL = dryL;
    scopeR = (dryR * 1.6).fold(-1, 1);

    wet = FreeVerb2.ar(preL, preR, 1.0,
        roomSize + (regimeDegenerated * 0.04),
        damp - (regimeDegenerated * 0.06));
    wet = LPF.ar(wet, 7500);

    signal = [
        (scopeL * (1 - reverbMix)) + (wet[0] * reverbMix * 0.85),
        (scopeR * (1 - reverbMix)) + (wet[1] * reverbMix * 0.85)
    ];

    // ========================================================
    // 14. OUTPUT
    // ========================================================
    signal = LeakDC.ar(signal);
    signal = Limiter.ar(signal, 0.95, 0.01);

    Out.ar(out, signal * amp);
    ScopeOut2.ar(signal, bufnum);

}).add;
)

// Allocate the scope buffer and wait for the SynthDef to compile.
s.sync;

(
~scopeBuf = Buffer.alloc(s, 2048, 2);

~parameterDegeneration_Holographic = Synth(\parameterDegeneration_Holographic, [
    \amp, 0.42,
    \switchRate, 0.28,
    \degeneration, 0.0,
    \fmCarrier, 110,
    \fmRatio, 1.4142,
    \fmIndex, 1.4,
    \dustRate, 14,
    \latchDepth, 0.85,
    \gateRate, 18,
    \noiseAmt, 0.28,
    \combFreq, 220,
    \combDecay, 3.0,
    \combMix, 0.5,
    \allpassFreq, 1200,
    \allpassDecay, 0.8,
    \droneFreq, 55,
    \droneLevel, 0.35,
    \droneDetune, 0.012,
    \freqShiftL, 0.7,
    \freqShiftR, 1.3,
    \voiceFreq, 330,
    \voiceLevel, 0.22,
    \voiceFormletDecay, 0.22,
    \subFreq, 40,
    \subLevel, 0.22,
    \distAmt, 1.2,
    \preDelay, 0.07,
    \reverbMix, 0.55,
    \roomSize, 0.96,
    \damp, 0.22,
    \rotateRate, 0.04,
    \msRotateRate, 0.015,
    \msDepth, 0.85,
    \bufnum, ~scopeBuf.bufnum
]);
)

// ============================================================
// DEGENERATION STATES
// ============================================================

// fully independent: the system only switches by threshold
~parameterDegeneration_Holographic.set(\degeneration, 0.0);

// partial: crossings start to stick in regimeDegenerated
~parameterDegeneration_Holographic.set(\degeneration, 0.4);

// strong: most crossings remain in regimeDegenerated
~parameterDegeneration_Holographic.set(\degeneration, 0.8);

// fully degenerated: once degenerated, it stays
~parameterDegeneration_Holographic.set(\degeneration, 1.0);

// ============================================================
// TEMPORAL SCALES
// ============================================================

~parameterDegeneration_Holographic.set(\switchRate, 0.9);
~parameterDegeneration_Holographic.set(\switchRate, 0.08);

// ============================================================
// GLITCH DENSITY
// ============================================================

~parameterDegeneration_Holographic.set(\dustRate, 40, \gateRate, 30, \latchDepth, 1.0);
~parameterDegeneration_Holographic.set(\dustRate, 4, \gateRate, 6, \latchDepth, 0.5);

// ============================================================
// HOLOGRAPHIC PROJECTION
// Wider allpass dispersion, longer pre-delay, stronger comb.
// ============================================================

~parameterDegeneration_Holographic.set(\allpassFreq, 700, \allpassDecay, 1.2, \preDelay, 0.12);
~parameterDegeneration_Holographic.set(\combFreq, 440, \combDecay, 6.0, \combMix, 0.7);

// ============================================================
// DRONE ROTATION
// Different freqShift L/R makes the body rotate.
// ============================================================

~parameterDegeneration_Holographic.set(\droneLevel, 0.55, \freqShiftL, 1.8, \freqShiftR, 0.4);
~parameterDegeneration_Holographic.set(\droneLevel, 0.3, \droneFreq, 66, \freqShiftL, 0.3, \freqShiftR, 2.1);

// ============================================================
// IMAGE MOTION
// ============================================================

~parameterDegeneration_Holographic.set(\msRotateRate, 0.09, \msDepth, 1.0);
~parameterDegeneration_Holographic.set(\msRotateRate, 0.004, \msDepth, 0.6);

// ============================================================
// GHOSTLY VOICE
// ============================================================

~parameterDegeneration_Holographic.set(\voiceLevel, 0.4, \voiceFreq, 220, \voiceFormletDecay, 0.35);

// ============================================================
// DIGITAL CHAOS
// Irrational ratio (sqrt 5 ~ 2.236) and high FM index.
// ============================================================

~parameterDegeneration_Holographic.set(\fmCarrier, 70, \fmRatio, 2.236, \fmIndex, 2.5, \distAmt, 2.0);