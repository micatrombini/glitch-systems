```supercollider
// ============================================================
// subFilterSwitchDeep
// Low-Frequency / Feedback Accumulation System
//
// Architecture:
// - Threshold-based A/B state switching.
// - Pink and white noise source.
// - Two parallel band-pass filter stages.
// - Independent sine-wave sub-bass oscillator with frequency glide.
// - Regime-dependent stereo feedback delay.
// - Independent stereo feedback paths.
// - Internal feedback saturation.
// - Parallel clean and clipped signal processing.
// - Stereo mixing, reverberation and low-pass filtering.
// - Output DC removal and limiting.
// ============================================================

(
SynthDef(\subFilterSwitchDeep, {
    |out = 0, amp = 0.5, density = 0.5,
     subLevel = 0.65, subFreq = 36, reverbMix = 0.38,
     roomSize = 0.9, damp = 0.55, distAmt = 0.3,
     switchRate = 0.16, fbAmt = 0.6, delayTime = 0.22,
     noiseAmt = 0.85, bufnum = 0|

    var parameter, delta, previous, crossing;
    var regimeA, regimeB, transition, lagTime;

    var noiseSrc, bpfA, bpfB;
    var switched, switchedLag;

    var sub, subGlide, subEnv, subDuck;

    var delayLine, fb, delaySig, delayMix;

    var glitchL, glitchR;
    var cleanL, cleanR;
    var clippedL, clippedR;

    var dryL, dryR, wet, signal;
    var saturation, reverbAmount;

    // --------------------------------------------------------
    // 01. THRESHOLD DETECTION
    // --------------------------------------------------------

    parameter = SinOsc.kr(switchRate).range(0.2, 0.8)
        + LFNoise1.kr(0.045).range(-0.14, 0.14);

    delta = parameter - 0.5;
    previous = Delay1.kr(delta);

    crossing = (
        (delta >= 0) * (previous < 0)
    ) + (
        (delta < 0) * (previous >= 0)
    );

    regimeA = Lag.kr(delta < 0, 0.12);
    regimeB = 1 - regimeA;

    transition = Trig1.kr(crossing, 0.15);

    lagTime = 0.18 + (regimeB * 0.35);

    // --------------------------------------------------------
    // 02. NOISE SOURCE
    // --------------------------------------------------------

    noiseSrc = PinkNoise.ar(0.85)
        + WhiteNoise.ar(0.15);

    // --------------------------------------------------------
    // 03. PARALLEL BAND-PASS FILTERS
    // --------------------------------------------------------

    bpfA = BPF.ar(
        noiseSrc,
        240,
        0.22
    );

    bpfB = BPF.ar(
        noiseSrc,
        780,
        0.38
    );

    // --------------------------------------------------------
    // 04. SPECTRAL STATE SWITCHING
    // --------------------------------------------------------

    switchedLag = Lag.kr(regimeA, lagTime);

    switched = (
        bpfA * switchedLag
    ) + (
        bpfB * (1 - switchedLag)
    );

    switched = switched * 2.0;

    switched = switched *
        LFNoise2.kr(
            0.055 + (density.clip(0, 1) * 0.12)
        ).range(0.5, 1.0) *
        noiseAmt.clip(0, 1.5);

    // --------------------------------------------------------
    // 05. SUB-BASS OSCILLATOR
    // --------------------------------------------------------

    subGlide = Lag.kr(
        subFreq.clip(20, 80) * (1 + (regimeB * 0.25)),
        0.4
    );

    sub = SinOsc.ar(subGlide);

    sub = LPF.ar(
        sub,
        55 + (regimeB * 25)
    );

    subEnv = LFNoise2.kr(0.035).range(0.7, 1.0);

    sub = sub * subEnv * subLevel.clip(0, 1);

    sub = sub * regimeA;

    // --------------------------------------------------------
    // 06. TRANSITION-TRIGGERED DUCKING
    // --------------------------------------------------------

    subDuck = 1 - (
        Decay2.kr(transition, 0.02, 0.35) * 0.3
    );

    sub = sub * subDuck;

    // --------------------------------------------------------
    // 07. STEREO FEEDBACK DELAY
    // --------------------------------------------------------

    delayLine = DelayC.ar(
        switched,
        0.5,
        Lag.kr(
            delayTime.clip(0.005, 0.27) *
            (1 + (regimeB * 0.8)),
            0.3
        )
    );

    fb = Lag.kr(
        fbAmt.clip(0, 0.75) *
        (0.65 + (regimeB * 0.3)),
        0.4
    ).clip(0, 0.8);

    delaySig = LocalIn.ar(2);

    delaySig = [
        delayLine + (delaySig[0] * fb),

        DelayC.ar(
            delayLine,
            0.04,
            0.018
        ) + (delaySig[1] * fb)
    ];

    delaySig = delaySig.tanh;

    LocalOut.ar(delaySig);

    delayMix = delaySig * (
        0.35 + (regimeB * 0.3)
    );

    // --------------------------------------------------------
    // 08. STEREO SIGNAL SUMMING
    // --------------------------------------------------------

    glitchL = switched + delayMix[0];
    glitchR = switched + delayMix[1];

    // --------------------------------------------------------
    // 09. PARALLEL SATURATION
    // --------------------------------------------------------

    saturation = distAmt.clip(0, 1);

    cleanL = glitchL * (
        1 - (regimeB * saturation * 0.35)
    );

    cleanR = glitchR * (
        1 - (regimeB * saturation * 0.35)
    );

    clippedL = (
        glitchL * (1 + (regimeB * saturation * 2.5))
    ).clip(-0.9, 0.9);

    clippedR = (
        glitchR * (1 + (regimeB * saturation * 2.5))
    ).clip(-0.9, 0.9);

    // --------------------------------------------------------
    // 10. STEREO MIXING
    // --------------------------------------------------------

    dryL = sub + cleanL + (clippedL * 0.7);

    dryR = sub + cleanR + (clippedR * 0.7);

    // --------------------------------------------------------
    // 11. REVERBERATION
    // --------------------------------------------------------

    wet = FreeVerb2.ar(
        dryL,
        dryR,
        1.0,
        roomSize.clip(0, 1),
        damp.clip(0, 1)
    );

    wet = LPF.ar(wet, 3800);

    reverbAmount = reverbMix.clip(0, 0.55);

    signal = [
        (dryL * (1 - reverbAmount)) +
            (wet[0] * reverbAmount * 0.8),

        (dryR * (1 - reverbAmount)) +
            (wet[1] * reverbAmount * 0.8)
    ];

    // --------------------------------------------------------
    // 12. OUTPUT PROCESSING
    // --------------------------------------------------------

    signal = LeakDC.ar(signal);

    signal = Limiter.ar(
        signal,
        0.95,
        0.01
    );

    Out.ar(out, signal * amp.clip(0, 1));

    ScopeOut2.ar(signal, bufnum);

}).add;
)

s.sync;


// ============================================================
// INITIALIZATION
// ============================================================

(
~scopeBuf5 = Buffer.alloc(s, 2048, 2);
)

s.sync;

(
~subFilterSwitchDeep = Synth(\subFilterSwitchDeep, [
    \amp, 0.6,
    \density, 0.5,
    \subLevel, 0.65,
    \subFreq, 36,
    \reverbMix, 0.38,
    \roomSize, 0.9,
    \damp, 0.55,
    \distAmt, 0.3,
    \switchRate, 0.16,
    \fbAmt, 0.6,
    \delayTime, 0.22,
    \noiseAmt, 0.85,
    \bufnum, ~scopeBuf5.bufnum
]);
)


// ============================================================
// PARAMETER PRESETS
// ============================================================

// 01. Slow Feedback Accumulation

(
~subFilterSwitchDeep.set(
    \switchRate, 0.07,
    \fbAmt, 0.7,
    \reverbMix, 0.42
);
)

// 02. Increased Spectral Switching Rate

(
~subFilterSwitchDeep.set(
    \switchRate, 0.35,
    \fbAmt, 0.5,
    \density, 0.7
);
)

// 03. Short Delay / Increased Saturation

(
~subFilterSwitchDeep.set(
    \delayTime, 0.08,
    \distAmt, 0.5
);
)

// 04. Sub-Bass Frequency Variation

(
~subFilterSwitchDeep.set(
    \subFreq, 28,
    \subLevel, 0.8
);
)

// 05. Increased Spectral Density

(
~subFilterSwitchDeep.set(
    \noiseAmt, 1.0,
    \density, 0.8
);
)

// 06. Expanded Reverberation Field

(
~subFilterSwitchDeep.set(
    \reverbMix, 0.5,
    \roomSize, 0.98,
    \damp, 0.65
);
)


// 07. Increased High-Frequency Damping

(
~subFilterSwitchDeep.set(
    \reverbMix, 0.35,
    \damp, 0.8
);
)
```