// Threshold-switching system, filtered variant.
// Same regime logic as subGlitchThreshold, with softer saturation on the
// click layer, band-limited noise bursts, and partial (split) saturation
// on the event bus instead of full-bus tanh.

(
SynthDef(\subGlitchHifi, {
    |out = 0, amp = 0.45, density = 0.75, clickAmt = 0.8,
     subLevel = 0.55, subFreq = 41, reverbMix = 0.45,
     roomSize = 0.92, damp = 0.25, distAmt = 0.35|

    var parameter, delta, previous, crossing;
    var regimeA, regimeB, transition;
    var glitchTrig, triggerStream, rateA, rateB;
    var sub, subMod, subEnv, subDuck, sub2;
    var sineCluster, sineFreqs;
    var clicks, clickEnv, clickNoise, clickDelay, clickSmooth;
    var noiseBurst, noiseEnv, padNoise, padEnv;
    var dryL, dryR, wet, signal, glitchBus, glitchClean;

    // --- Threshold and crossing ---
    // Slow LFO centered at 0.5; delta is the signed distance to threshold.
    parameter = SinOsc.kr(0.25).range(0.15, 0.85);
    delta = parameter - 0.5;
    previous = Delay1.kr(delta);
    // Bipolar sign-change detection between successive samples.
    crossing = ((delta >= 0) * (previous < 0)) + ((delta < 0) * (previous >= 0));

    // --- Regime flags ---
    // regimeA: delta < 0. regimeB: delta >= 0. transition: 50 ms gate on crossing.
    regimeA = (delta < 0);
    regimeB = (delta >= 0);
    transition = Trig1.kr(crossing, 0.05);

    // --- Trigger density per regime ---
    // TDuty only active in regime B. Dust rates scale with density.
    rateA = 3 + (density * 10);
    rateB = 40 + (density * 60);
    triggerStream = TDuty.ar(
        Drand([0.025, 0.05, 0.1, 0.2] * (1 - (density * 0.5)), inf),
        0,
        Drand([0.85, 0.95, 1.0], inf)
    ) * regimeB;
    glitchTrig = triggerStream
        + Dust.kr(rateA * regimeA)
        + Dust.kr(rateB * regimeB)
        + Trig1.kr(crossing, 0.008)
        + (transition * 80);

    // --- Sub oscillator ---
    // Fundamental + 1.5x and 0.5x partials, LPF swept by LFNoise1.
    // Gated by regimeA: present only in the stable regime.
    subMod = LFNoise1.kr(0.12).range(0.75, 1.0);
    sub = SinOsc.ar(subFreq, 0, 1.0);
    sub = sub + (SinOsc.ar(subFreq * 1.5, 0, 0.35));
    sub = sub + (SinOsc.ar(subFreq * 0.5, 0, 0.2));
    sub = LPF.ar(sub, 100 + (LFNoise1.kr(0.08).range(0, 50)));

    // Second sub at 0.75x, LPF at 60 Hz, amplitude jitter via LFNoise0.
    sub2 = SinOsc.ar(subFreq * 0.75, 0, 0.4);
    sub2 = LPF.ar(sub2, 60) * (1 + (LFNoise0.kr(0.5).range(-0.2, 0.2)));

    subEnv = LFNoise2.kr(0.08).range(0.65, 1.0);
    sub = (sub + sub2) * subEnv * subMod * subLevel * regimeA;

    // Amplitude ducking: Decay2 envelope on each trigger, max 35% reduction.
    subDuck = 1 - (Decay2.ar(K2A.ar(glitchTrig), 0.01, 0.18) * 0.35);
    sub = sub * subDuck;

    // --- Additive sine bank ---
    // Five partials, +/-1% frequency jitter (LFNoise0), decay time scaled by index.
    sineFreqs = [110, 220, 440, 880, 1760].collect { |f|
        f * LFNoise0.kr(6).range(0.99, 1.01)
    };
    sineCluster = Mix(
        sineFreqs.collect { |freq, i|
            var env = Decay2.ar(K2A.ar(glitchTrig), 0.001, 0.025 + (i * 0.012));
            SinOsc.ar(freq, 0, env * (0.12 / (i + 1)))
        }
    );

    // --- Click layer ---
    // PinkNoise through BPF at 12 kHz, Q = 0.6, gain 20; soft tanh saturation.
    // CombC adds a short feedback delay (45 ms, decay 0.6).
    clickEnv = Decay.ar(glitchTrig, 0.0004);
    clickNoise = PinkNoise.ar(clickEnv * 2.8);
    clickSmooth = BPF.ar(clickNoise, 12000, 0.6, 20);
    clickSmooth = (clickSmooth * 1.5).tanh;
    clickDelay = CombC.ar(clickSmooth, 0.08, 0.045, 0.6);
    clicks = clickSmooth + (clickDelay * 0.45);

    // --- Noise burst layer ---
    // WhiteNoise band-limited to 200..8000 Hz, gated by Decay2 envelope.
    noiseEnv = Decay2.ar(glitchTrig, 0.001, 0.06);
    noiseBurst = WhiteNoise.ar(1);
    noiseBurst = LPF.ar(noiseBurst, 8000);
    noiseBurst = HPF.ar(noiseBurst, 200);
    noiseBurst = noiseBurst * noiseEnv * 0.15;

    // --- Noise pad ---
    // PinkNoise through BPF; center 400..1000 Hz (LFNoise1), Q = 0.8,
    // then LPF at 4 kHz.
    padEnv = LFNoise2.kr(0.05).range(0.3, 1.0);
    padNoise = PinkNoise.ar(padEnv * 0.08);
    padNoise = BPF.ar(padNoise, 400 + (LFNoise1.kr(0.1).range(0, 600)), 0.8);
    padNoise = LPF.ar(padNoise, 4000);

    // --- Sum and split saturation ---
    // Bus is split into a clean portion and a saturated portion, both scaled
    // by regimeB * distAmt, then recombined.
    glitchBus = sineCluster + clicks + noiseBurst + padNoise;
    glitchClean = glitchBus * (1 - (regimeB * distAmt * 0.5));
    glitchBus = glitchBus * (regimeB * distAmt * 2);
    glitchBus = glitchBus.tanh;
    glitchBus = glitchClean + glitchBus;

    // --- Stereo ---
    // Right channel delayed by 3 ms (DelayC) for width.
    dryL = sub + glitchBus;
    dryR = sub + DelayC.ar(glitchBus, 0.006, 0.003);

    // --- Reverb ---
    // roomSize and damp offset by regimeB; FreeVerb2 fully wet, LPF at 6 kHz,
    // then manual dry/wet blend.
    wet = FreeVerb2.ar(
        dryL, dryR,
        1.0,
        roomSize + (regimeB * 0.06),
        damp - (regimeB * 0.1)
    );
    wet = LPF.ar(wet, 6000);

    signal = [
        (dryL * (1 - reverbMix)) + (wet[0] * reverbMix * 0.7),
        (dryR * (1 - reverbMix)) + (wet[1] * reverbMix * 0.7)
    ];

    // --- Output ---
    // DC block and peak limiting at 0.95 before amplitude scaling.
    signal = LeakDC.ar(signal);
    signal = Limiter.ar(signal, 0.95, 0.01);

    Out.ar(out, signal * amp);
}).add;
)

s.sync;

// Instance parameters
~subGlitch = Synth(\subGlitchHifi, [
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



