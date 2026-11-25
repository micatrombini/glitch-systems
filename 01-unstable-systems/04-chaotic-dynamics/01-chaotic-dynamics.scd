// Sonification of the logistic map x[n+1] = r * x[n] * (1 - x[n])
// using a server-side feedback implementation (LocalIn/LocalOut +
// Latch) and a resonant band-pass synthesis engine.
//
// The bifurcation parameter r determines the qualitative regime:
//
//   r < 3.0            stable fixed point
//   3.0 < r < 3.5699   period-doubling cascade (period 2, 4, 8, ...)
//   r > 3.5699         deterministic chaos
//   r ~ 3.8284         periodic window embedded in the chaotic regime
//   r -> 4.0           fully developed chaos (Ulam map)
//
// The map state x[n] is mapped to:
//   - the center frequency of a resonant band-pass filter,
//   - the amplitude of a sub-bass layer,
//   - the amount of feedback in the nonlinear distortion loop.
//
// SIGNAL CHAIN
// ------------
// source (noise + detuned fifth + saw)
//   -> resonant band-pass
//   -> feedback loop with three-stage nonlinear distortion
//   -> parallel saturation (clean + tanh + fold)
//   -> explosive envelope (chaos-triggered)
//   -> extended string layer (comb + reverb + long ASR)
//   -> ghost-monster vocal layer (3 detuned sines + formant)
//   -> holographic spectral field (FFT -> PV_MagFreeze / PV_BinScramble / PV_MagSmear)
//   -> post-industrial machine pulse (filtered impulse)
//   -> stereo panning + rotation
//   -> two-stage reverb (intimate plate + large dark hall)
//   -> multiband glue compression + soft limiter
//   -> scope visuals (soft peak shaping + breath-modulated amplitude)
//
// PARAMETERS
// ----------
//   r                  bifurcation parameter of the logistic map
//   x0                 initial condition of the logistic map
//   mapRate            iteration rate of the map (Hz)
//   baseFreq           base frequency of sonification (Hz)
//   freqRange          frequency range mapped from x[n] (Hz)
//   subFreq            fundamental of the sub-bass layer (Hz)
//   subLevel           amplitude of the sub-bass layer
//   bodySubLevel       amplitude of the body-sub layer (28 Hz)
//   infrasubLevel      amplitude of the infrasonic layer (24 Hz)
//   tuningLFORate      rate of the slow tuning-instability LFO (Hz)
//   tuningLFOAmt       depth of the tuning-instability LFO
//   detuneAmt          chaos-driven detune amount
//   sourceNoise        amount of pink noise in the source
//   rq                 reciprocal Q of the resonant band-pass
//   sourceLPF          pre-filter cutoff of the source (Hz)
//   fbAmt              feedback amount in the distortion loop
//   drive              pre-gain of the nonlinear distortion
//   distAmt            amount of parallel saturation
//   chaosThresh        r threshold above which chaos is detected
//   explAttack         attack time of the explosive envelope (s)
//   explDecay          decay time of the explosive envelope (s)
//   explRate           rate of explosive triggers (Hz)
//   explGain           gain of the explosive envelope
//   presenceLevel      level of the lurking noise presence
//   presenceRate       rate of the presence breathing (Hz)
//   toneLPF            final tone low-pass cutoff (Hz)
//   toneLFORate        rate of the tone LFO (Hz)
//   toneLFOAmt         depth of the tone LFO (Hz)
//   subLFORate         rate of the sub breathing LFO (Hz)
//   subLFOAmt          depth of the sub breathing LFO
//   combFreq           comb-filter frequency of the extended string
//   combDecay          comb-filter decay time (s)
//   combMix            mix of the comb-filter layer
//   guitarRevMix       reverb mix of the extended string
//   guitarRevSize      reverb size of the extended string
//   guitarRevDamp      reverb damping of the extended string
//   guitarLPF          low-pass cutoff of the extended string (Hz)
//   ghostFreq          fundamental of the ghost-monster voices (Hz)
//   ghostDetune        detune amount of the ghost-monster voices
//   ghostLevel         level of the ghost-monster voices
//   ghostFormant       formant center of the ghost-monster voices (Hz)
//   ghostEnvRate       rate of the ghost-monster envelopes (Hz)
//   ghostLPF           low-pass cutoff of the ghost-monster voices (Hz)
//   ghostVibratoRate   rate of the ghost-monster vibrato (Hz)
//   ghostVibratoDepth  depth of the ghost-monster vibrato
//   fftSize            FFT window size of the holographic field
//   holoFreeze         amount of spectral freeze in the hologram
//   holoScramble       amount of spectral scrambling in the hologram
//   holoMix            mix of the holographic field
//   holoLPF            low-pass cutoff of the holographic field (Hz)
//   machinePulseLevel  level of the machine pulse
//   machinePulseFreq   center frequency of the machine pulse (Hz)
//   breathRate         rate of the cinematic breathing LFO (Hz)
//   breathDepth        depth of the cinematic breathing LFO
//   panSpread          stereo spread of the main signal
//   rotateRate         rate of the stereo rotation (Hz)
//   reverbMix          global reverb mix
//   hallSize           size of the large dark hall reverb
//   hallDamp           damping of the large dark hall reverb
//   dryLevel           level of the dry signal
//   wetLevel           level of the wet signal
//   intimateMix        mix of the intimate plate reverb
//   intimateSize       size of the intimate plate reverb
//   intimateDamp       damping of the intimate plate reverb
//   glueAmt            amount of glue compression
//   breathAmpDepth     depth of the breath-modulated amplitude
//   gain               master gain of the synth
//   bufnum             scope buffer index
// ============================================================

(
SynthDef(\logisticMap_chaoticSonification, {
    |out = 0, amp = 0.95, gate = 1,
     r = 3.9,
     x0 = 0.8,
     mapRate = 20,
     baseFreq = 65, freqRange = 450,
     subFreq = 38, subLevel = 0.85,
     bodySubLevel = 0.65,
     infrasubLevel = 0.30,
     tuningLFORate = 0.07, tuningLFOAmt = 0.03,
     detuneAmt = 0.15,
     sourceNoise = 0.4, rq = 0.07,
     sourceLPF = 1800,
     fbAmt = 0.75, drive = 6.5, distAmt = 1.0,
     chaosThresh = 3.57,
     explAttack = 0.002,
     explDecay = 1.2,
     explRate = 0.4,
     explGain = 2.2,
     presenceLevel = 0.12,
     presenceRate = 0.08,
     toneLPF = 3500,
     toneLFORate = 0.07,
     toneLFOAmt = 150,
     subLFORate = 0.05,
     subLFOAmt = 0.05,
     combFreq = 45, combDecay = 4.0, combMix = 0.35,
     guitarRevMix = 0.4, guitarRevSize = 0.95, guitarRevDamp = 0.7,
     guitarLPF = 3500,
     ghostFreq = 165, ghostDetune = 0.006, ghostLevel = 0.22,
     ghostFormant = 250, ghostEnvRate = 0.25,
     ghostLPF = 2000,
     ghostVibratoRate = 3.0, ghostVibratoDepth = 0.012,
     fftSize = 1024,
     holoFreeze = 0.85, holoScramble = 0.05, holoMix = 0.20,
     holoLPF = 3000,
     machinePulseLevel = 0.06,
     machinePulseFreq = 2000,
     breathRate = 0.015, breathDepth = 0.6,
     panSpread = 0.8,
     rotateRate = 0.05,
     reverbMix = 0.45,
     hallSize = 0.96, hallDamp = 0.85,
     dryLevel = 1.0, wetLevel = 0.65,
     intimateMix = 0.20, intimateSize = 0.35, intimateDamp = 0.4,
     glueAmt = 0.70,
     breathAmpDepth = 0.2,
     gain = 1.0, bufnum = 0|

    var env;
    var mapTrig, xPrev, xNext, xState;
    var chaosAmt, explTrig, explEnv;
    var presenceEnv, presenceSig;
    var tuningLFO, freq, detune;
    var noiseSrc, bodySig, fbSig, d1, d2, d3;
    var subOsc, subEnv, subLFO, subMod;
    var bodySubOsc, infrasubOsc, heartRate, heartEnv;
    var cleanBranch, tanhBranch, foldBranch, mixedSig;
    var toneLFO, toneCut;
    var panPos, panL, panR;
    var combSig, combFiltered, guitarEnv, guitarL, guitarR;
    var guitarRevL, guitarRevR;
    var ghostTrig, ghostEnv, ghostVibrato, ghostOsc, ghostFormantSig;
    var ghostL, ghostR;
    var fftBuf, holoChainL, holoChainR, holoL, holoR;
    var machinePulse;
    var breathLFO, breathMod;
    var intimateL, intimateR, hallL, hallR;
    var signal;

    env = EnvGen.kr(Env.asr(0.01, 1, 2), gate, doneAction: 2);

    mapTrig = Impulse.kr(mapRate);
    xPrev = LocalIn.ar(1);
    xNext = (r * xPrev * (1 - xPrev)).clip(0, 1);
    LocalOut.ar(xNext);
    xState = Latch.ar(xNext, mapTrig);

    chaosAmt = ((r - chaosThresh) / (4.0 - chaosThresh)).clip(0, 1);

    breathLFO = SinOsc.kr(breathRate).range(1 - breathDepth, 1 + breathDepth);
    breathMod = breathLFO;

    explTrig = Impulse.kr(explRate * (0.5 + (chaosAmt * 2)));
    explEnv = EnvGen.kr(
        Env.perc(explAttack, explDecay, 1, -4),
        explTrig * (chaosAmt > 0.1)
    );
    explEnv = explEnv * chaosAmt;

    tuningLFO = 1 + (SinOsc.kr(tuningLFORate).range(-1, 1) * tuningLFOAmt);
    freq = baseFreq + (xState * freqRange);
    detune = 1 + (chaosAmt * detuneAmt * (xState - 0.5) * 2);
    freq = freq * detune * tuningLFO;

    subLFO = 1 + (SinOsc.kr(subLFORate).range(-1, 1) * subLFOAmt);
    subMod = 1 + (xState * 0.5);
    subOsc = SinOsc.ar(subFreq * subMod, 0, 1.0);
    subEnv = LFNoise2.kr(0.06).range(0.6, 1.0);
    subOsc = LPF.ar(subOsc, 100 + (xState * 60)) * subEnv * subLevel * subLFO;
    subOsc = (subOsc * 1.8).tanh * 0.9;

    bodySubOsc = SinOsc.ar(28, 0, 1.0);
    bodySubOsc = (bodySubOsc * 2.5).tanh * bodySubLevel;
    bodySubOsc = LPF.ar(bodySubOsc, 60);

    heartRate = 0.6 + (chaosAmt * 0.8);
    heartEnv = EnvGen.kr(Env.perc(0.01, 0.3), Impulse.kr(heartRate));
    infrasubOsc = SinOsc.ar(24, 0, 1.0);
    infrasubOsc = (infrasubOsc * 2.0).tanh * infrasubLevel * heartEnv;
    infrasubOsc = LPF.ar(infrasubOsc, 40);

    noiseSrc = (ClipNoise.ar(0.7) + (PinkNoise.ar(0.5) * sourceNoise));
    noiseSrc = LPF.ar(noiseSrc, sourceLPF);

    bodySig = BPF.ar(noiseSrc, freq, rq) * 8;
    bodySig = bodySig + (BPF.ar(noiseSrc, freq * 2.01, rq * 1.5) * 4);
    bodySig = bodySig + (LPF.ar(Saw.ar(freq), sourceLPF) * 0.6);

    presenceEnv = 0.6 + (SinOsc.kr(presenceRate).range(-1, 1) * 0.4);
    presenceSig = BPF.ar(PinkNoise.ar(1), 300, 0.5) * presenceLevel * presenceEnv;
    presenceSig = HPF.ar(presenceSig, 100);
    bodySig = bodySig + presenceSig;

    fbSig = LocalIn.ar(1) * fbAmt;
    bodySig = bodySig + fbSig;

    d1 = (bodySig * drive).tanh;
    d2 = (d1 * 3).distort;
    d3 = (d2 * 2).clip2(0.4);
    d3 = LPF.ar(d3, 1000);

    LocalOut.ar(d3 * fbAmt);

    d3 = d3 * (0.5 + (explEnv * explGain));

    mixedSig = (d3 + subOsc + bodySubOsc + infrasubOsc) * 1.6;
    cleanBranch = mixedSig;
    tanhBranch = (mixedSig * 3.0).tanh;
    foldBranch = (mixedSig * 2.2).fold2(0.85);
    mixedSig = (cleanBranch * (1 - distAmt))
             + (tanhBranch * distAmt * 0.9)
             + (foldBranch * distAmt * 0.6);

    toneLFO = SinOsc.kr(toneLFORate).range(-1, 1) * toneLFOAmt;
    toneCut = (toneLPF + toneLFO).clip(800, 12000);
    mixedSig = LPF.ar(mixedSig, toneCut);
    mixedSig = HPF.ar(mixedSig, 30);

    panPos = SinOsc.kr(rotateRate).range(-1, 1);
    panL = Pan2.ar(mixedSig, (panPos + (panSpread * 0.6)).clip(-1, 1))[0];
    panR = Pan2.ar(mixedSig, (panPos.neg + (panSpread * 0.6)).clip(-1, 1))[1];

    combSig = CombC.ar(panL + panR, 0.5, combFreq.reciprocal, combDecay);
    combFiltered = LPF.ar(combSig, guitarLPF) * combMix;

    guitarEnv = EnvGen.kr(Env.asr(2.0, 1.0, 3.0), gate, doneAction: 0);

    guitarL = ((panL * guitarEnv) + combFiltered);
    guitarR = ((panR * guitarEnv) + combFiltered);
    guitarL = LPF.ar(guitarL, guitarLPF);
    guitarR = LPF.ar(guitarR, guitarLPF);

    guitarRevL = FreeVerb.ar(guitarL, 1.0, guitarRevSize, guitarRevDamp) * guitarRevMix;
    guitarRevR = FreeVerb.ar(guitarR, 1.0, guitarRevSize, guitarRevDamp) * guitarRevMix;

    guitarL = guitarL + guitarRevL;
    guitarR = guitarR + guitarRevR;

    ghostTrig = Impulse.kr(ghostEnvRate * (0.5 + (chaosAmt * 1.5)));
    ghostEnv = EnvGen.kr(
        Env.perc(0.5, 3.0, 1, -3),
        ghostTrig * (chaosAmt > 0.2)
    );
    ghostEnv = ghostEnv * chaosAmt * breathMod;

    ghostVibrato = SinOsc.kr(ghostVibratoRate).range(1 - ghostVibratoDepth, 1 + ghostVibratoDepth);

    ghostOsc = Mix.ar([
        SinOsc.ar(ghostFreq * 0.5 * ghostVibrato * (1 - ghostDetune), 0, 0.3),
        SinOsc.ar(ghostFreq * ghostVibrato * (1 - ghostDetune), 0, 0.35),
        SinOsc.ar(ghostFreq * ghostVibrato * (1 + ghostDetune), 0, 0.35)
    ]);

    ghostFormantSig = BPF.ar(ghostOsc, ghostFormant, 0.1) * 4;
    ghostFormantSig = ghostFormantSig + BPF.ar(ghostOsc, ghostFormant * 2.2, 0.15) * 2;
    ghostFormantSig = LPF.ar(ghostFormantSig, ghostLPF);

    ghostL = Pan2.ar(ghostFormantSig * ghostEnv * ghostLevel, -0.3)[0];
    ghostR = Pan2.ar(ghostFormantSig * ghostEnv * ghostLevel, 0.3)[1];

    fftBuf = LocalBuf(fftSize, 2);

    holoChainL = FFT(fftBuf, LPF.ar(guitarL + (ghostL * ghostLevel), 3000));
    holoChainL = PV_MagFreeze(holoChainL, holoFreeze * breathMod);
    holoChainL = PV_BinScramble(holoChainL, holoScramble, 0.1, 0.5);
    holoChainL = PV_MagSmear(holoChainL, 8);
    holoL = LPF.ar(IFFT(holoChainL), holoLPF) * holoMix;

    holoChainR = FFT(fftBuf, LPF.ar(guitarR + (ghostR * ghostLevel), 3000));
    holoChainR = PV_MagFreeze(holoChainR, holoFreeze * breathMod);
    holoChainR = PV_BinScramble(holoChainR, holoScramble, 0.1, 0.5);
    holoChainR = PV_MagSmear(holoChainR, 8);
    holoR = LPF.ar(IFFT(holoChainR), holoLPF) * holoMix;

    machinePulse = BPF.ar(Impulse.ar(mapRate * 0.5), machinePulseFreq, 0.1) * machinePulseLevel;

    panL = panL + guitarL * 0.5 + ghostL + holoL + machinePulse;
    panR = panR + guitarR * 0.5 + ghostR + holoR + machinePulse;

    intimateL = FreeVerb.ar(panL, 1.0, intimateSize, intimateDamp) * intimateMix;
    intimateR = FreeVerb.ar(panR, 1.0, intimateSize, intimateDamp) * intimateMix;

    panL = panL + intimateL;
    panR = panR + intimateR;

    hallL = FreeVerb.ar(panL, 1.0, hallSize, hallDamp);
    hallR = FreeVerb.ar(panR, 1.0, hallSize, hallDamp);

    hallL = LPF.ar(hallL, 4500);
    hallR = LPF.ar(hallR, 4500);
    hallL = (hallL * 1.05).tanh * 0.7;
    hallR = (hallR * 1.05).tanh * 0.7;

    signal = [
        (panL * dryLevel * (1 - reverbMix * 0.5)) + (hallL * wetLevel * reverbMix),
        (panR * dryLevel * (1 - reverbMix * 0.5)) + (hallR * wetLevel * reverbMix)
    ];

    signal = Compander.ar(signal, signal, 0.25, 0.4, 1.0, 0.01, 0.10);
    signal = signal * (1 + (glueAmt * 0.4));
    signal = LeakDC.ar(signal);
    signal = Limiter.ar(signal, 0.90, 0.01);

    signal = signal.tanh;
    signal = signal * (1 - breathAmpDepth + (breathMod * breathAmpDepth));

    Out.ar(out, signal * amp * gain * env);
    ScopeOut2.ar(signal, bufnum);
}).add;
)

s.sync;

(
~scopeBuf = Buffer.alloc(s, 2048, 2);

~logisticMapSonification = Synth(\logisticMap_chaoticSonification, [
    \amp, 0.95,
    \r, 3.9,
    \x0, 0.4,
    \mapRate, 20,
    \baseFreq, 65,
    \freqRange, 450,
    \subFreq, 38,
    \subLevel, 0.85,
    \bodySubLevel, 0.65,
    \infrasubLevel, 0.30,
    \tuningLFORate, 0.07,
    \tuningLFOAmt, 0.03,
    \detuneAmt, 0.15,
    \sourceNoise, 0.4,
    \rq, 0.07,
    \sourceLPF, 1800,
    \fbAmt, 0.75,
    \drive, 6.5,
    \distAmt, 1.0,
    \chaosThresh, 3.57,
    \explAttack, 0.002,
    \explDecay, 1.2,
    \explRate, 0.4,
    \explGain, 2.2,
    \presenceLevel, 0.12,
    \presenceRate, 0.08,
    \toneLPF, 3500,
    \toneLFORate, 0.07,
    \toneLFOAmt, 150,
    \subLFORate, 0.05,
    \subLFOAmt, 0.05,
    \combFreq, 45,
    \combDecay, 4.0,
    \combMix, 0.35,
    \guitarRevMix, 0.4,
    \guitarRevSize, 0.95,
    \guitarRevDamp, 0.7,
    \guitarLPF, 3500,
    \ghostFreq, 165,
    \ghostDetune, 0.006,
    \ghostLevel, 0.22,
    \ghostFormant, 250,
    \ghostEnvRate, 0.25,
    \ghostLPF, 2000,
    \ghostVibratoRate, 3.0,
    \ghostVibratoDepth, 0.012,
    \fftSize, 1024,
    \holoFreeze, 0.85,
    \holoScramble, 0.05,
    \holoMix, 0.20,
    \holoLPF, 3000,
    \machinePulseLevel, 0.06,
    \machinePulseFreq, 2000,
    \breathRate, 0.015,
    \breathDepth, 0.6,
    \panSpread, 0.8,
    \rotateRate, 0.05,
    \reverbMix, 0.45,
    \hallSize, 0.96,
    \hallDamp, 0.85,
    \dryLevel, 1.0,
    \wetLevel, 0.65,
    \intimateMix, 0.20,
    \intimateSize, 0.35,
    \intimateDamp, 0.4,
    \glueAmt, 0.70,
    \breathAmpDepth, 0.2,
    \gain, 1.0,
    \bufnum, ~scopeBuf.bufnum
]);
)

(
~scopeWin = Window("Logistic Map Scope", Rect(100, 100, 900, 400)).front;
~myScope = Stethoscope.new(s, view: ~scopeWin.view);
~myScope.scopeView.bufnum_(~scopeBuf.bufnum);
~myScope.scopeView.style_(2);
~myScope.scopeView.waveColors_([Color.magenta, Color.cyan]);
~myScope.scopeView.background_(Color.black);
~myScope.scopeView.xZoom_(4);
~myScope.scopeView.yZoom_(1.5);
)

~logisticMapSonification.set(\r, 2.5);
~logisticMapSonification.set(\r, 2.9);
~logisticMapSonification.set(\r, 3.2);
~logisticMapSonification.set(\r, 3.5);
~logisticMapSonification.set(\r, 3.7);
~logisticMapSonification.set(\r, 3.83);
~logisticMapSonification.set(\r, 3.9);
~logisticMapSonification.set(\r, 3.99);

~logisticMapSonification.set(\combFreq, 25, \combDecay, 6.0, \combMix, 0.5);
~logisticMapSonification.set(\combFreq, 65, \combDecay, 2.0, \combMix, 0.2);
~logisticMapSonification.set(\guitarRevMix, 0.1, \guitarRevSize, 0.28);
~logisticMapSonification.set(\guitarLPF, 2500);

~logisticMapSonification.set(\ghostFreq, 130, \ghostDetune, 0.03, \ghostLevel, 0.28);
~logisticMapSonification.set(\ghostFreq, 760, \ghostDetune, 0.01, \ghostLevel, 0.18);
~logisticMapSonification.set(\ghostFormant, 200);
~logisticMapSonification.set(\ghostFormant, 300);
~logisticMapSonification.set(\ghostEnvRate, 0.10);
~logisticMapSonification.set(\ghostEnvRate, 0.60);
~logisticMapSonification.set(\ghostLPF, 1500);
~logisticMapSonification.set(\ghostVibratoRate, 1.5, \ghostVibratoDepth, 0.025);
~logisticMapSonification.set(\ghostVibratoRate, 6.0, \ghostVibratoDepth, 0.008);

~logisticMapSonification.set(\holoFreeze, 0.90, \holoScramble, 0.02, \holoMix, 0.30);
~logisticMapSonification.set(\holoFreeze, 0.50, \holoScramble, 0.15, \holoMix, 0.15);
~logisticMapSonification.set(\holoLPF, 2000);

~logisticMapSonification.set(\machinePulseLevel, 0.10, \machinePulseFreq, 1500);
~logisticMapSonification.set(\machinePulseLevel, 0.03, \machinePulseFreq, 3000);

~logisticMapSonification.set(\intimateMix, 0.35, \intimateSize, 0.30, \intimateDamp, 0.40);
~logisticMapSonification.set(\intimateMix, 0.10, \intimateSize, 0.60, \intimateDamp, 0.55);

~logisticMapSonification.set(\breathRate, 0.005, \breathDepth, 0.80);
~logisticMapSonification.set(\breathRate, 0.04, \breathDepth, 0.35);

~logisticMapSonification.set(\reverbMix, 0.35, \hallSize, 0.92, \hallDamp, 0.75);
~logisticMapSonification.set(\reverbMix, 0.55, \hallSize, 0.98, \hallDamp, 0.85);

~logisticMapSonification.set(\breathAmpDepth, 0.5);
~logisticMapSonification.set(\breathAmpDepth, 0.1);

~logisticMapSonification.set(\amp, 1.0);
~logisticMapSonification.set(\gain, 1.2);

