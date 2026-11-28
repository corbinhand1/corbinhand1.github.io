/**
 * sfx — tiny WebAudio synth for comms sounds. No audio files.
 * Every call takes `on` so callers don't need to check the toggle themselves.
 * Muted by default; the AudioContext is only created after a user gesture.
 */

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let murmur: { src: AudioBufferSourceNode; gain: GainNode } | null = null;

function ac(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  if (!ctx) {
    const C = (window as any).AudioContext || (window as any).webkitAudioContext;
    if (!C) return null;
    ctx = new C();
    master = ctx.createGain();
    master.gain.value = 0.6;
    master.connect(ctx.destination);
  }
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

function noiseBuffer(c: AudioContext, seconds: number, brown = false): AudioBuffer {
  const len = Math.floor(c.sampleRate * seconds);
  const buf = c.createBuffer(1, len, c.sampleRate);
  const d = buf.getChannelData(0);
  let last = 0;
  for (let i = 0; i < len; i++) {
    const w = Math.random() * 2 - 1;
    if (brown) {
      last = (last + 0.02 * w) / 1.02;
      d[i] = last * 3.5;
    } else {
      d[i] = w;
    }
  }
  return buf;
}

function tone(freq: number, start: number, dur: number, vol = 0.15, type: OscillatorType = 'sine', endFreq?: number) {
  const c = ac();
  if (!c || !master) return;
  const o = c.createOscillator();
  const g = c.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, c.currentTime + start);
  if (endFreq) o.frequency.exponentialRampToValueAtTime(endFreq, c.currentTime + start + dur);
  g.gain.setValueAtTime(0.0001, c.currentTime + start);
  g.gain.exponentialRampToValueAtTime(vol, c.currentTime + start + 0.01);
  g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + start + dur);
  o.connect(g).connect(master);
  o.start(c.currentTime + start);
  o.stop(c.currentTime + start + dur + 0.05);
}

function noise(start: number, dur: number, vol: number, filter: BiquadFilterType, f0: number, f1?: number) {
  const c = ac();
  if (!c || !master) return;
  const src = c.createBufferSource();
  src.buffer = noiseBuffer(c, dur + 0.05);
  const bq = c.createBiquadFilter();
  bq.type = filter;
  bq.frequency.setValueAtTime(f0, c.currentTime + start);
  if (f1) bq.frequency.exponentialRampToValueAtTime(f1, c.currentTime + start + dur);
  const g = c.createGain();
  g.gain.setValueAtTime(vol, c.currentTime + start);
  g.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + start + dur);
  src.connect(bq).connect(g).connect(master);
  src.start(c.currentTime + start);
}

export const sfx = {
  /** Create/resume the context. Call from a user gesture. */
  unlock() {
    ac();
  },

  /** Headset key click */
  click(on: boolean) {
    if (!on) return;
    noise(0, 0.03, 0.25, 'highpass', 2500);
  },

  /** Two-tone standby blip */
  standby(on: boolean) {
    if (!on) return;
    noise(0, 0.025, 0.15, 'highpass', 2500);
    tone(880, 0.03, 0.09, 0.08, 'square');
    tone(660, 0.13, 0.11, 0.08, 'square');
  },

  /** Rising GO chirp */
  go(on: boolean) {
    if (!on) return;
    noise(0, 0.025, 0.2, 'highpass', 2500);
    tone(600, 0.02, 0.09, 0.12, 'triangle', 1300);
  },

  /** Perfect-call ding */
  ding(on: boolean) {
    if (!on) return;
    tone(1568, 0.12, 0.6, 0.08, 'sine');
    tone(2093, 0.18, 0.7, 0.05, 'sine');
  },

  /** Confetti cannon thump. Bigger = more boom. */
  thump(on: boolean, size = 1) {
    if (!on) return;
    tone(140, 0, 0.4 + 0.15 * size, 0.35 * Math.min(size, 1.6), 'sine', 38);
    noise(0, 0.25 + 0.1 * size, 0.3 * Math.min(size, 1.5), 'lowpass', 1800, 200);
    noise(0.04, 0.5, 0.06, 'highpass', 4000); // paper flutter
  },

  /** Broom swish */
  sweep(on: boolean) {
    if (!on) return;
    noise(0, 0.45, 0.18, 'bandpass', 600, 3500);
    noise(0.5, 0.45, 0.18, 'bandpass', 3500, 600);
  },

  /** Fire marshal siren */
  siren(on: boolean) {
    if (!on) return;
    for (let i = 0; i < 3; i++) {
      tone(620, i * 1.1, 0.55, 0.07, 'sawtooth', 980);
      tone(980, i * 1.1 + 0.55, 0.55, 0.07, 'sawtooth', 620);
    }
  },

  /** Low crowd/room murmur loop while the show is up */
  setMurmur(on: boolean) {
    const c = on ? ac() : ctx;
    if (!c || !master) return;
    if (on && !murmur) {
      const src = c.createBufferSource();
      src.buffer = noiseBuffer(c, 4, true);
      src.loop = true;
      const bq = c.createBiquadFilter();
      bq.type = 'bandpass';
      bq.frequency.value = 420;
      bq.Q.value = 0.7;
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, c.currentTime);
      g.gain.exponentialRampToValueAtTime(0.05, c.currentTime + 1.5);
      src.connect(bq).connect(g).connect(master);
      src.start();
      murmur = { src, gain: g };
    } else if (!on && murmur) {
      const m = murmur;
      murmur = null;
      m.gain.gain.cancelScheduledValues(c.currentTime);
      m.gain.gain.setValueAtTime(Math.max(m.gain.gain.value, 0.0001), c.currentTime);
      m.gain.gain.exponentialRampToValueAtTime(0.0001, c.currentTime + 0.6);
      m.src.stop(c.currentTime + 0.7);
    }
  },
};
