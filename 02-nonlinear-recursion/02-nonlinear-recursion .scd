```supercollider
// ============================================================
// subFilterSwitchCrystal
// Spectral Switching / Resonant Glitch System
//
// Architecture:
// - Threshold-based A/B state switching.
// - Pink and white noise source.
// - Two parallel band-pass filter stages.
// - Independent sine-wave sub-bass oscillator with frequency glide.
// - Regime-dependent feedback delay.
// - Independent stereo feedback paths.
// - Parallel clean and clipped signal processing.
// - Stereo mixing, reverberation and output limiting.
// ============================================================

(
SynthDef(\subFilterSwitchCrystal, {
    |out = 0, amp = 0.5, density = 0.65,
     subLevel = 0.45, subFreq = 52, reverbMix = 0.25,
     roomSize = 0.8, damp = 0.3, distAmt = 0.3,
     switchRate = 0.42, fbAmt = 0.4, delayTime = 0.055,
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
        + LFNoise1.kr(0.09).range(-0.1, 0.1);

    delta = parameter - 0.5;
    previous = Delay1.kr(delta);

    crossing = (
        (delta >= 0) * (previous < 0)
    ) + (
        (delta < 0) * (previous >= 0)
    );

    regimeA = Lag.kr(delta < 0, 0.045);
    regimeB = 1 - regimeA;

    transition = Trig1.kr(crossing, 0.06);

    lagTime = 0.045 + (regimeB * 0.16);

    // --------------------------------------------------------
    // 02. NOISE SOURCE
    // --------------------------------------------------------

    noiseSrc = PinkNoise.ar(0.75)
        + WhiteNoise.ar(0.25);

    // --------------------------------------------------------
    // 03. PARALLEL BAND-PASS FILTERS
    // --------------------------------------------------------

    bpfA = BPF.ar(
        noiseSrc,
        1100,
        0.16
    );

    bpfB = BPF.ar(
        noiseSrc,
        3600,
        0.24
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

    switched = switched * 1.8;

    switched = switched *
        LFNoise2.kr(
            0.25 + (density.clip(0, 1) * 0.3)
        ).range(0.45, 1.0) *
        noiseAmt.clip(0, 1.5);

    // --------------------------------------------------------
    // 05. SUB-BASS OSCILLATOR
    // --------------------------------------------------------

    subGlide = Lag.kr(
        subFreq * (1 + (regimeB * 0.22)),
        0.12
    );

    sub = SinOsc.ar(subGlide);

    sub = LPF.ar(
        sub,
        105 + (regimeB * 45)
    );

    subEnv = LFNoise2.kr(0.08).range(0.65, 1.0);

    sub = sub * subEnv * subLevel.clip(0, 1);

    sub = sub * regimeA;

    // --------------------------------------------------------
    // 06. TRANSITION-TRIGGERED DUCKING
    // --------------------------------------------------------

    subDuck = 1 - (
        Decay2.kr(transition, 0.005, 0.18) * 0.35
    );

    sub = sub * subDuck;

    // --------------------------------------------------------
    // 07. STEREO FEEDBACK DELAY
    // --------------------------------------------------------

    delayLine = DelayC.ar(
        switched,
        0.25,
        Lag.kr(
            delayTime.clip(0.005, 0.16) *
            (1 + (regimeB * 0.35)),
            0.12
        )
    );

    fb = Lag.kr(
        fbAmt.clip(0, 0.75) *
        (0.55 + (regimeB * 0.35)),
        0.2
    );

    delaySig = LocalIn.ar(2);

    delaySig = [
        delayLine + (delaySig[0] * fb),

        DelayC.ar(
            delayLine,
            0.02,
            0.008
        ) + (delaySig[1] * fb)
    ];

    delaySig = delaySig.tanh;

    LocalOut.ar(delaySig);

    delayMix = delaySig * (
        0.3 + (regimeB * 0.3)
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
        1 - (regimeB * saturation * 0.3)
    );

    cleanR = glitchR * (
        1 - (regimeB * saturation * 0.3)
    );

    clippedL = (
        glitchL * (1 + (regimeB * saturation * 2.5))
    ).clip(-0.85, 0.85);

    clippedR = (
        glitchR * (1 + (regimeB * saturation * 2.5))
    ).clip(-0.85, 0.85);

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

    wet = LPF.ar(wet, 8500);

    reverbAmount = reverbMix.clip(0, 0.65);

    signal = [
        (dryL * (1 - reverbAmount)) +
            (wet[0] * reverbAmount * 0.7),

        (dryR * (1 - reverbAmount)) +
            (wet[1] * reverbAmount * 0.7)
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
~scopeBuf4 = Buffer.alloc(s, 2048, 2);
)

s.sync;

(
~subFilterSwitchCrystal = Synth(\subFilterSwitchCrystal, [
    \amp, 0.65,
    \density, 0.65,
    \subLevel, 0.5,
    \subFreq, 52,
    \reverbMix, 0.25,
    \roomSize, 0.8,
    \damp, 0.3,
    \distAmt, 0.3,
    \switchRate, 0.42,
    \fbAmt, 0.4,
    \delayTime, 0.055,
    \noiseAmt, 0.85,
    \bufnum, ~scopeBuf4.bufnum
]);
)


// ============================================================
// PARAMETER PRESETS
// ============================================================

// 01. Slow Spectral Switching

(
~subFilterSwitchCrystal.set(
    \switchRate, 0.12,
    \fbAmt, 0.55,
    \reverbMix, 0.3
);
)

// 02. Fast Spectral Switching

(
~subFilterSwitchCrystal.set(
    \switchRate, 0.8,
    \fbAmt, 0.3,
    \density, 0.8
);
)

// 03. Short Delay / Increased Saturation

(
~subFilterSwitchCrystal.set(
    \delayTime, 0.035,
    \distAmt, 0.5
);
)

// 04. Expanded Stereo Space

(
~subFilterSwitchCrystal.set(
    \delayTime, 0.11,
    \reverbMix, 0.4,
    \roomSize, 0.9
);
)

// 05. Sub-Bass Frequency Variation

(
~subFilterSwitchCrystal.set(
    \subFreq, 44,
    \subLevel, 0.65
);
)

// 06. Increased Spectral Activity

(
~subFilterSwitchCrystal.set(
    \noiseAmt, 1.0,
    \density, 0.9
);
)
```