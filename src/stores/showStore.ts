import { create } from 'zustand';
import { sfx } from '../lib/sfx';

/**
 * showStore — the single source of truth for the show.
 *
 * The visitor calls the show: each cue goes Standby → a timing bar sweeps toward
 * a mark → the visitor hits GO (button / space / enter). If they don't, the ASM
 * calls it for them, so passive visitors still see the whole sequence.
 */

export type Dept = 'Lights' | 'Video' | 'Audio' | 'Confetti';
export type Tone = 'cue' | 'good' | 'warn' | 'alert' | 'chatter' | 'info';

export interface LogEntry {
  id: number;
  time: string;
  who?: string;
  text: string;
  tone: Tone;
}

export interface CueResult {
  dept: Dept;
  deltaMs: number | null; // null = ASM called it
}

export type CallStatus =
  | 'preshow'   // before the first standby
  | 'standby'   // "Standby X." logged, bar not moving yet
  | 'approach'  // bar sweeping toward the mark; GO accepted
  | 'executing' // cue fired, waiting for the next standby
  | 'done';     // show is up; LAUNCH mode

export const CUES: { dept: Dept; op: string }[] = [
  { dept: 'Lights', op: 'the LD' },
  { dept: 'Video', op: 'the video op' },
  { dept: 'Audio', op: 'the A1' },
  { dept: 'Confetti', op: 'the SFX tech' },
];

// Timing (ms)
export const T = {
  firstStandby: 1200,
  standbyHold: 650,    // Standby logged → bar starts
  approach: 1500,      // bar travel time to the mark
  grace: 450,          // how late a GO still counts
  betweenCues: 750,
  barMarkPct: 80,      // where the mark sits on the bar (%)
};

const BEST_KEY = 'nebula.bestCallAvgMs';
const SOUND_KEY = 'nebula.sound';

let logId = 0;
let timers: number[] = [];
let runId = 0;

const now = () => new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });
const later = (fn: () => void, ms: number) => {
  const id = window.setTimeout(fn, ms);
  timers.push(id);
};
const clearTimers = () => {
  timers.forEach(clearTimeout);
  timers = [];
};

function readBest(): number | null {
  try {
    const v = localStorage.getItem(BEST_KEY);
    return v ? Number(v) : null;
  } catch {
    return null;
  }
}

interface ShowState {
  // calling game
  status: CallStatus;
  cueIndex: number;
  targetAt: number;       // performance.now() when the bar hits the mark
  results: CueResult[];
  bestAvgMs: number | null;

  // effects driven by cues
  lightLevel: number;
  videoRolling: boolean;
  audioUp: boolean;

  // log
  log: LogEntry[];

  // big button / fire marshal
  coverOpen: boolean;
  launches: number;        // presses since last lockout
  totalLaunches: number;
  lockedUntil: number;     // Date.now() ms
  houseLights: boolean;

  // fx toggles
  soundOn: boolean;
  haze: boolean;
  blackout: boolean;

  // actions
  announce: (text: string, who?: string, tone?: Tone) => void;
  startShow: () => void;
  callGo: () => void;
  setCoverOpen: (open: boolean) => void;
  registerLaunch: () => void;
  toggleSound: () => void;
  setHaze: (on: boolean) => void;
  setBlackout: (on: boolean) => void;
}

function grade(dept: Dept, op: string, delta: number): { text: string; tone: Tone } {
  const abs = Math.round(Math.abs(delta));
  const dir = delta > 0 ? 'late' : 'early';
  if (abs <= 60) return { text: `Perfect call. ${abs}ms.`, tone: 'good' };
  if (abs <= 150) return { text: `Clean. ${abs}ms ${dir}.`, tone: 'good' };
  if (abs <= 300) return { text: `${abs}ms ${dir}. ${op.charAt(0).toUpperCase() + op.slice(1)} noticed.`, tone: 'warn' };
  return { text: `${abs}ms ${dir}. ${dept === 'Confetti' ? 'Confetti happened anyway.' : `${op.charAt(0).toUpperCase() + op.slice(1)} is looking at you.`}`, tone: 'warn' };
}

export const useShowStore = create<ShowState>((set, get) => {
  const announce: ShowState['announce'] = (text, who, tone = 'info') => {
    set((s) => ({ log: [...s.log.slice(-40), { id: ++logId, time: now(), who, text, tone }] }));
  };

  const fireCue = (dept: Dept) => {
    switch (dept) {
      case 'Lights':
        set({ lightLevel: 1 });
        later(() => set({ lightLevel: 0.4 }), 2500);
        break;
      case 'Video':
        set({ videoRolling: true });
        break;
      case 'Audio':
        set({ audioUp: true });
        sfx.setMurmur(get().soundOn);
        break;
      case 'Confetti':
        // The big button listens for this and fires the first burst
        window.dispatchEvent(new CustomEvent('nebula:go-confetti'));
        break;
    }
  };

  const finishShow = () => {
    const { results } = get();
    const called = results.filter((r) => r.deltaMs !== null) as { dept: Dept; deltaMs: number }[];
    set({ status: 'done' });
    if (called.length === 0) {
      announce('Show report: ASM called the whole thing. Hit ↻ and take the headset.', 'SM', 'info');
      return;
    }
    const clean = called.filter((r) => Math.abs(r.deltaMs) <= 150).length;
    const avg = Math.round(called.reduce((a, r) => a + Math.abs(r.deltaMs), 0) / called.length);
    let best = get().bestAvgMs;
    let newBest = false;
    if (called.length === CUES.length && (best === null || avg < best)) {
      best = avg;
      newBest = true;
      try { localStorage.setItem(BEST_KEY, String(avg)); } catch { /* private mode */ }
      set({ bestAvgMs: avg });
    }
    announce(
      `Show report: ${clean}/${CUES.length} clean · avg ${avg}ms${newBest ? ' · NEW BEST' : best !== null ? ` · best ${best}ms` : ''}`,
      'SM',
      clean === CUES.length ? 'good' : 'info'
    );
  };

  const runCue = (i: number, myRun: number) => {
    if (myRun !== runId) return;
    if (i >= CUES.length) {
      finishShow();
      return;
    }
    const { dept } = CUES[i];
    set({ status: 'standby', cueIndex: i });
    announce(`Standby ${dept}.`, 'SM', 'cue');
    sfx.standby(get().soundOn);

    later(() => {
      if (myRun !== runId) return;
      set({ status: 'approach', targetAt: performance.now() + T.approach });
      // If nobody calls it, the ASM does.
      later(() => {
        if (myRun !== runId || get().status !== 'approach' || get().cueIndex !== i) return;
        set((s) => ({ status: 'executing', results: [...s.results, { dept, deltaMs: null }] }));
        announce(`Go ${dept}. (I got it.)`, 'ASM', 'chatter');
        sfx.go(get().soundOn);
        fireCue(dept);
        later(() => runCue(i + 1, myRun), T.betweenCues);
      }, T.approach + T.grace);
    }, T.standbyHold);
  };

  let soundOn = false;
  try { soundOn = localStorage.getItem(SOUND_KEY) === 'on'; } catch { /* ignore */ }

  return {
    status: 'preshow',
    cueIndex: 0,
    targetAt: 0,
    results: [],
    bestAvgMs: readBest(),

    lightLevel: 0,
    videoRolling: false,
    audioUp: false,

    log: [],

    coverOpen: false,
    launches: 0,
    totalLaunches: 0,
    lockedUntil: 0,
    houseLights: false,

    soundOn,
    haze: false,
    blackout: false,

    announce,

    startShow: () => {
      clearTimers();
      const myRun = ++runId;
      const replay = get().log.length > 0;
      set({
        status: 'preshow',
        cueIndex: 0,
        results: [],
        lightLevel: 0,
        videoRolling: false,
        audioUp: false,
        coverOpen: false,
      });
      sfx.setMurmur(false);
      if (replay) announce('Resetting to top of show.', 'SM', 'info');
      announce('You have the headset. Hit GO (or space) when the bar hits the mark.', 'SM', 'info');
      later(() => runCue(0, myRun), replay ? 900 : T.firstStandby);
    },

    callGo: () => {
      const s = get();
      if (s.status === 'standby') {
        announce('Hold… not yet.', 'SM', 'warn');
        return;
      }
      if (s.status !== 'approach') return;
      const delta = performance.now() - s.targetAt;
      if (delta < -T.approach * 0.75) {
        announce('Hold… not yet.', 'SM', 'warn');
        return;
      }
      const { dept, op } = CUES[s.cueIndex];
      set((st) => ({ status: 'executing', results: [...st.results, { dept, deltaMs: delta }] }));
      sfx.go(s.soundOn);
      announce(dept === 'Confetti' ? 'GO Confetti!' : `Go ${dept}!`, 'YOU', 'cue');
      const g = grade(dept, op, delta);
      announce(g.text, 'SM', g.tone);
      if (g.tone === 'good' && Math.abs(delta) <= 60) sfx.ding(s.soundOn);
      fireCue(dept);
      const myRun = runId;
      later(() => runCue(s.cueIndex + 1, myRun), T.betweenCues);
    },

    setCoverOpen: (open) => {
      if (open === get().coverOpen) return;
      set({ coverOpen: open });
      sfx.click(get().soundOn);
    },

    registerLaunch: () => {
      const launches = get().launches + 1;
      set((s) => ({ launches, totalLaunches: s.totalLaunches + 1 }));
      if (launches === 5) announce('Easy on the button…', 'SM', 'warn');
      if (launches === 6) announce('Fire marshal is asking questions.', 'FOH', 'warn');
      if (launches === 7) announce('Seriously. Last one.', 'SM', 'warn');
      if (launches >= 8) {
        const lockMs = 7000;
        set({ lockedUntil: Date.now() + lockMs, houseLights: true, coverOpen: false, launches: 0 });
        announce('🚒 FIRE MARSHAL HAS ENTERED THE BUILDING', 'FOH', 'alert');
        announce('House lights up. Button is locked out.', 'SM', 'alert');
        sfx.siren(get().soundOn);
        window.setTimeout(() => {
          set({ houseLights: false });
          announce('Fire marshal: "Fine. But keep it out of the HVAC."', 'FOH', 'chatter');
          announce('We are clear. Button is live.', 'SM', 'good');
        }, lockMs);
      }
    },

    toggleSound: () => {
      const on = !get().soundOn;
      set({ soundOn: on });
      try { localStorage.setItem(SOUND_KEY, on ? 'on' : 'off'); } catch { /* ignore */ }
      sfx.unlock();
      sfx.setMurmur(on && get().audioUp);
      if (on) sfx.click(true);
    },

    setHaze: (on) => set({ haze: on }),
    setBlackout: (on) => set({ blackout: on }),
  };
});
