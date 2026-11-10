// ============================================================
// parameterDegeneration_Feedback.scd
//
// 01-unstable-systems / 03-Parameter-Degeneration
//
// CONCEPT
// -------
// The feedback loses independence. In regimeIndependent, each
// delay line has its own time and feedback amount. In
// regimeDegenerated, all delays synchronize to the same time
// -> the system collapses into a single loop. Degeneration =
// loss of temporal diversity.
//
// WARNING: this patch uses LocalIn/LocalOut (shared feedback
// bus, 2 channels). The feedback path is tamed with tanh and
// LeakDC on every delay output, and the effective feedback
// coefficient is capped below 1.0.
//
// Signal flow:
//   [source: FM + noise] -> [feedback bus: LocalIn]
//   -> [2 DelayC lines with independent times]
//   -> [regime blend] -> [tanh] -> [LocalOut]
//   -> [mix] -> [parallel saturation] -> [stereo] -> [out]
//
// LEVEL NOTES
// -----------
// - amp 0.65 and +1.3 pre-saturation gain keep the patch loud.
// - Feedback coefficient is capped at 0.95 effective.
// - tanh + LeakDC on every delay keeps the feedback stable
//   even at degeneration = 1.0.
// - Limiter at 0.95 is a safety net, not a compressor.
// ============================================================

(
SynthDef(\parameterDegeneration_Feedback, {
    |out = 0, amp = 0.65,
     switchRate = 0.28, degeneration = 0.0,
     // source
     fmCarrier = 110, fmRatio = 1.4142, fmIndex = 1.5,
     noiseAmt = 0.3,
     // delay lines
     delay1Time = 0.18, delay2Time = 0.27,
     delay1Fb = 0.5, delay2Fb = 0.42,
     // sub
     subFreq = 42, subLevel = 0.32,
     // fx
     distAmt = 1.0, reverbMix = 0.42, roomSize = 0.92, damp = 0.25,
     rotateRate = 0.05, bufnum = 0|

    // --- threshold detection ---
    var parameter, delta, previous, crossing;
    var regimeIndependent, regimeDegenerated, transition, lagTime;

    // --- source banks ---
    var srcTime1, srcTime2, srcFb1, srcFb2;
    var degTime1, degTime2, degFb1, degFb2;
    var paramTime1, paramTime2, paramFb1, paramFb2;

    // --- source ---
    var fmMod, fm, noise, source;

    // --- feedback bus (shared, 2 channels) ---
    var fbBus, delay1, delay2, feedbackSig;

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
    // src* : each delay line has its own time/feedback (independent)
    // deg* : all delay lines share `parameter` (degenerated)
    // ========================================================
    srcTime1 = LFNoise1.kr(0.08).range(0.5, 2.0);
    srcTime2 = LFNoise2.kr(0.06).range(0.5, 2.0);
    srcFb1 = LFNoise1.kr(0.05).range(0.4, 1.2);
    srcFb2 = LFNoise2.kr(0.07).range(0.4, 1.2);

    // Degenerated times and feedbacks converge to one value.
    // Feedback target stays below 1.0 to avoid runaway.
    degTime1 = parameter.range(0.7, 1.4);
    degTime2 = parameter.range(0.7, 1.4);
    degFb1 = parameter.range(0.7, 1.1);
    degFb2 = parameter.range(0.7, 1.1);

    paramTime1 = (srcTime1 * regimeIndependent) + (degTime1 * regimeDegenerated);
    paramTime2 = (srcTime2 * regimeIndependent) + (degTime2 * regimeDegenerated);
    paramFb1 = (srcFb1 * regimeIndependent) + (degFb1 * regimeDegenerated);
    paramFb2 = (srcFb2 * regimeIndependent) + (degFb2 * regimeDegenerated);

    // ========================================================
    // 3. SOURCE
    // ========================================================
    fmMod = SinOsc.ar(fmCarrier * fmRatio, 0, fmIndex);
    fm = SinOsc.ar(fmCarrier + (fmMod * fmCarrier * 0.5), 0, 1.0);
    noise = PinkNoise.ar(1) * noiseAmt;
    source = (fm * 0.6) + noise;

    // ========================================================
    // 4. FEEDBACK BUS (2 channels, shared by LocalIn/LocalOut)
    // Feedback is tamed: effective coefficient capped at 0.95,
    // tanh + LeakDC on every delay output.
    // ========================================================
    fbBus = LocalIn.ar(2);
    delay1 = DelayC.ar(
        source + (fbBus[0] * delay1Fb * paramFb1.range(0.4, 0.95)),
        0.6,
        (delay1Time * paramTime1.range(0.5, 2.0)).clip(0.01, 0.55)
    );
    delay2 = DelayC.ar(
        source + (fbBus[1] * delay2Fb * paramFb2.range(0.4, 0.95)),
        0.6,
        (delay2Time * paramTime2.range(0.5, 2.0)).clip(0.01, 0.55)
    );

    delay1 = (delay1 * 1.2).tanh;
    delay2 = (delay2 * 1.2).tanh;
    delay1 = LeakDC.ar(delay1);
    delay2 = LeakDC.ar(delay2);

    feedbackSig = (delay1 + delay2) * 0.7;
    LocalOut.ar([feedbackSig, delay1]);

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
    mixedSignal = (feedbackSig + sub) * 1.3;
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

~parameterDegeneration_Feedback = Synth(\parameterDegeneration_Feedback, [
    \amp, 0.65,
    \switchRate, 0.28,
    \degeneration, 0.0,
    \fmCarrier, 110,
    \fmRatio, 1.4142,
    \fmIndex, 1.5,
    \noiseAmt, 0.3,
    \delay1Time, 0.18,
    \delay2Time, 0.27,
    \delay1Fb, 0.5,
    \delay2Fb, 0.42,
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
~parameterDegeneration_Feedback.set(\degeneration, 0.0);
~parameterDegeneration_Feedback.set(\degeneration, 0.4);
~parameterDegeneration_Feedback.set(\degeneration, 0.8);
~parameterDegeneration_Feedback.set(\degeneration, 1.0);

// --- Delay times: shorter = rhythmic, longer = spatial ---
~parameterDegeneration_Feedback.set(\delay1Time, 0.09, \delay2Time, 0.14);
~parameterDegeneration_Feedback.set(\delay1Time, 0.35, \delay2Time, 0.52);

// --- Feedback amount ---
~parameterDegeneration_Feedback.set(\delay1Fb, 0.65, \delay2Fb, 0.58);
~parameterDegeneration_Feedback.set(\delay1Fb, 0.3,  \delay2Fb, 0.25);

// --- Source character ---
~parameterDegeneration_Feedback.set(\noiseAmt, 0.6, \fmIndex, 0.5);
~parameterDegeneration_Feedback.set(\noiseAmt, 0.1, \fmIndex, 3.0);

// --- Slow switching ---
~parameterDegeneration_Feedback.set(\switchRate, 0.08);

// --- Extra loudness gestures ---
~parameterDegeneration_Feedback.set(\amp, 0.75);
~parameterDegeneration_Feedback.set(\subLevel, 0.4, \subFreq, 36);