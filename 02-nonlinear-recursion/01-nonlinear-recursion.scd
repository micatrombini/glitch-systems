```supercollider
// ============================================================
// subFilterSwitch
// Spectral switching system
//
// Architecture:
// - Threshold-based state switching between two filter bands.
// - Pink and white noise as the primary sound source.
// - Feedback delay network for transient generation.
// - Single sine oscillator with frequency glide for sub-bass.
// - Parallel clean and clipped signal paths.
// - Stereo processing, reverberation and output limiting.
// ============================================================

(
SynthDef(\subFilterSwitch, {
    |out = 0, amp = 0.5, density = 0.6,
     subLevel = 0.5, subFreq = 48, reverbMix = 0.35,
     roomSize = 0.85, damp = 0.3, distAmt = 0.4,
     switchRate = 0.35, fbAmt = 0.55, delayTime = 0.12,
     noiseAmt = 0.7, bufnum = 0|

    var parameter, delta, previous, crossing;
    var regimeA, regimeB, transition, lagTime;
    var noiseSrc, bpfA, bpfB, switched, switchedLag;
    var sub, subGlide, subEnv, subDuck;
    var delayLine, fb, delaySig, delayMix;
    var glitchBus, clipped, clean;
    var dryL, dryR, wet, signal, scopeL, scopeR;

    // --- Threshold Detection ---
    parameter = SinOsc.kr(switchRate).range(0.2, 0.8)
              + LFNoise1.kr(0.07).range(-0.12, 0.12);

    delta = parameter - 0.5;
    previous = Delay1.kr(delta);

    crossing = ((delta >= 0) * (previous < 0))
             + ((delta < 0) * (previous >= 0));

    regimeA = (delta < 0);
    regimeB = (delta >= 0);
    transition = Trig1.kr(crossing, 0.08);

    lagTime = 0.08 + (regimeB * 0.25);

    // --- Noise Source ---
    noiseSrc = PinkNoise.ar(1) + WhiteNoise.ar(0.3);

    // --- Parallel Band-Pass Filters ---
    bpfA = BPF.ar(noiseSrc, 700, 0.25);
    bpfB = BPF.ar(noiseSrc, 3200, 0.9);

    // --- Spectral State Switching ---
    switched = (bpfA * regimeA) + (bpfB * regimeB);

    switchedLag = Lag.kr(regimeA, lagTime);
    switched = (bpfA * switchedLag)
             + (bpfB * (1 - switchedLag));

    // --- Amplitude Modulation ---
    switched = switched
             * LFNoise2.kr(0.15).range(0.4, 1.0)
             * noiseAmt;

    // --- Sub-Bass Oscillator ---
    subGlide = Lag.kr(subFreq * (1 + (regimeB * 0.5)), 0.15);

    sub = SinOsc.ar(subGlide, 0, 1.0);
    sub = LPF.ar(sub, 80 + (regimeB * 60));

    subEnv = LFNoise2.kr(0.06).range(0.5, 1.0);
    sub = sub * subEnv * subLevel * regimeA;

    // --- Transition-Triggered Ducking ---
    subDuck = 1 - (
        Decay2.ar(K2A.ar(transition), 0.01, 0.25) * 0.45
    );

    sub = sub * subDuck;

    // --- Feedback Delay Network ---
    delayLine = DelayC.ar(
        switched,
        0.5,
        Lag.kr(delayTime * (1 + (regimeB * 0.6)), 0.2)
    );

    fb = Lag.kr(fbAmt * (0.6 + (regimeB * 0.5)), 0.3);

    delaySig = LocalIn.ar(2);
    delaySig = delayLine + (delaySig * fb);
    delaySig = delaySig.tanh;

    LocalOut.ar(delaySig);

    delayMix = delaySig * (0.4 + (regimeB * 0.4));

    // --- Signal Summation ---
    glitchBus = switched + delayMix;

    // --- Parallel Saturation ---
    clean = glitchBus * (1 - (regimeB * distAmt * 0.4));

    clipped = (
        glitchBus * (1 + (regimeB * distAmt * 4))
    ).clip(-0.9, 0.9);

    glitchBus = clean + clipped;

    // --- Stereo Processing ---
    dryL = sub + glitchBus;
    dryR = sub + DelayC.ar(glitchBus, 0.02, 0.011);

    scopeL = dryL;
    scopeR = (dryR * 1.6).fold(-1, 1);

    // --- Reverberation ---
    wet = FreeVerb2.ar(
        scopeL,
        scopeR,
        1.0,
        roomSize + (regimeB * 0.05),
        damp - (regimeB * 0.08)
    );

    wet = LPF.ar(wet, 7000);

    signal = [
        (scopeL * (1 - reverbMix)) + (wet[0] * reverbMix * 0.7),
        (scopeR * (1 - reverbMix)) + (wet[1] * reverbMix * 0.7)
    ];

    // --- Output Processing ---
    signal = LeakDC.ar(signal);
    signal = Limiter.ar(signal, 0.95, 0.01);

    Out.ar(out, signal * amp);
    ScopeOut2.ar(signal, bufnum);

}).add;
)

s.sync;

(
~scopeBuf = Buffer.alloc(s, 2048, 2);

~subFilterSwitch = Synth(\subFilterSwitch, [
    \amp, 0.85,
    \density, 0.6,
    \subLevel, 0.5,
    \subFreq, 48,
    \reverbMix, 0.35,
    \roomSize, 0.85,
    \damp, 0.3,
    \distAmt, 0.4,
    \switchRate, 0.35,
    \fbAmt, 0.55,
    \delayTime, 0.12,
    \noiseAmt, 0.7,
    \bufnum, ~scopeBuf.bufnum
]);
)

// --- Parameter Presets ---

~subFilterSwitch.set(\switchRate, 0.12, \fbAmt, 0.75);
~subFilterSwitch.set(\switchRate, 0.9, \fbAmt, 0.35);
~subFilterSwitch.set(\delayTime, 0.045, \distAmt, 0.7);
~subFilterSwitch.set(\delayTime, 0.28, \distAmt, 0.2);
~subFilterSwitch.set(\subFreq, 36, \subLevel, 0.7);
~subFilterSwitch.set(\noiseAmt, 1.0, \density, 0.3);
```