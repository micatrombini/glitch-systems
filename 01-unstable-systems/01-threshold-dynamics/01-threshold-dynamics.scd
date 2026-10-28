// Sub drone + additive sine bank + stochastic event layer.
// Event clock: TDuty with Drand intervals, plus threshold-crossing triggers.
// Density modulated continuously by normalized distance to crossing.

(
SynthDef(\subGlitchTexture, {
    |out = 0, amp = 0.45, density = 0.75, clickAmt = 0.8,
     subLevel = 0.55, subFreq = 41, reverbMix = 0.45,
     roomSize = 0.92, damp = 0.25, distAmt = 0.35|

    var parameter, delta, previous, crossing, proximity;
    var glitchTrig, triggerStream;
    var sub, subMod, subEnv, subDuck, sub2;
    var sineCluster, sineFreqs;
    var clicks, clickEnv, clickNoise, clickDelay;
    var noiseBurst, noiseEnv, padNoise, padEnv;
    var dryL, dryR, wet, signal, glitchBus;

    // --- Event generation ---
    parameter = SinOsc.kr(0.25).range(0.15, 0.85);
    delta = parameter - 0.5;
    previous = Delay1.kr(delta);
    crossing = ((delta >= 0) * (previous < 0)) + ((delta < 0) * (previous >= 0));

    proximity = (1 - (delta.abs * 12)).clip(0, 1).pow(2);

    triggerStream = TDuty.ar(
        Drand([0.025, 0.05, 0.1, 0.2] * (1 - (density * 0.5)), inf),
        0,
        Drand([0.85, 0.95, 1.0], inf)
    );

    glitchTrig = triggerStream + Trig1.kr(crossing * proximity, 0.008);

    // --- Sub oscillator ---
    subMod = LFNoise1.kr(0.12).range(0.75, 1.0);
    sub = SinOsc.ar(subFreq, 0, 1.0);
    sub = sub + (SinOsc.ar(subFreq * 1.5, 0, 0.35));
    sub = sub + (SinOsc.ar(subFreq * 0.5, 0, 0.2));
    sub = LPF.ar(sub, 100 + (LFNoise1.kr(0.08).range(0, 50)));

    sub2 = SinOsc.ar(subFreq * 0.75, 0, 0.4);
    sub2 = LPF.ar(sub2, 60) * (1 + (LFNoise0.kr(0.5).range(-0.2, 0.2)));

    subEnv = LFNoise2.kr(0.08).range(0.65, 1.0);
    sub = (sub + sub2) * subEnv * subMod * subLevel;

    subDuck = 1 - (Decay2.ar(K2A.ar(glitchTrig), 0.01, 0.18) * 0.35);
    sub = sub * subDuck;

    // --- Additive sine bank ---
    sineFreqs = [110, 220, 440, 880, 1760].collect { |f|
        f * LFNoise0.kr(6).range(0.97, 1.03)
    };
    sineCluster = Mix(
        sineFreqs.collect { |freq, i|
            var env = Decay2.ar(K2A.ar(glitchTrig), 0.001, 0.025 + (i * 0.012));
            SinOsc.ar(freq, 0, env * (0.12 / (i + 1)))
        }
    );

    // --- Click layer ---
    clickEnv = Decay.ar(glitchTrig, 0.0004);
    clickNoise = PinkNoise.ar(clickEnv * 2.8);
    clicks = BPF.ar(clickNoise, 12000, 0.85, 28).fold(-1, 1);
    clickDelay = CombC.ar(clicks, 0.08, 0.045, 0.6);
    clicks = clicks + (clickDelay * 0.45);

    // --- Noise burst layer ---
    noiseEnv = Decay2.ar(glitchTrig, 0.001, 0.06);
    noiseBurst = WhiteNoise.ar(noiseEnv * 0.18);

    // --- Noise pad ---
    padEnv = LFNoise2.kr(0.05).range(0.3, 1.0);
    padNoise = PinkNoise.ar(padEnv * 0.08);
    padNoise = BPF.ar(padNoise, 400 + (LFNoise1.kr(0.1).range(0, 600)), 0.6);

    // --- Sum and saturation ---
    glitchBus = sineCluster + clicks + noiseBurst + padNoise;
    glitchBus = (glitchBus * (1 + (distAmt * 3))).tanh / (1 + distAmt);

    // --- Stereo ---
    dryL = sub + glitchBus;
    dryR = sub
        + DelayC.ar(glitchBus, 0.006, 0.003);

    // --- Reverb ---
    wet = FreeVerb2.ar(
        dryL, dryR,
        1.0,
        roomSize,
        damp
    );
    wet = LPF.ar(wet, 7000);

    signal = [
        (dryL * (1 - reverbMix)) + (wet[0] * reverbMix * 0.7),
        (dryR * (1 - reverbMix)) + (wet[1] * reverbMix * 0.7)
    ];

    // --- Output ---
    signal = LeakDC.ar(signal);
    signal = Limiter.ar(signal, 0.95, 0.01);

    Out.ar(out, signal * amp);
}).add;
)

s.sync;

// Instance parameters
~subGlitch = Synth(\subGlitchTexture, [
    \amp, 0.45,
    \density, 0.95,
    \clickAmt, 0.5,
    \subLevel, 0.85,
    \subFreq, 71,
    \reverbMix, 0.25,
    \roomSize, 0.12,
    \damp, 0.45,
    \distAmt, 0.55
]);