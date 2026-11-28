import React, { useEffect, useRef, useState } from 'react';
import { useShowStore } from '../stores/showStore';

/**
 * Stagehand — the "move the stage a little to the left" gag.
 *
 * Beat 1: PROD asks to move the stage a little to the left. A stagehand in blacks
 *         (headlamp, beanie, gaff roll, radio) walks in from the right, leans into
 *         the stage, shoves it left, walks off.
 * Beat 2: PROD: "Client says split the difference." He comes back from the left,
 *         pushes it all the way back to where it started, thumbs-up, walks off.
 * Runs once per visit.
 *
 * He lives inside the stage wrapper, so he moves with the stage while pushing.
 * Start it with startStageMove().
 */

export const STAGE_SHIFT_PX = 26;

let gagUsed = false;
/** True once the gag has been triggered this visit (chatter stops using the line). */
export const stageGagUsed = () => gagUsed;

export function startStageMove() {
  // Only once, and only after the cues are complete
  if (gagUsed || useShowStore.getState().status !== 'done') return;
  gagUsed = true;
  window.dispatchEvent(new CustomEvent('nebula:stagehand'));
}

type Phase = 'off' | 'enter' | 'push' | 'thumbs' | 'exit';
type Side = 'right' | 'left'; // which side he stands on (right side pushes the stage left)

const T = { enter: 1500, push: 1700, thumbs: 1500, exit: 1300 };

/** The character, drawn facing LEFT. Mirrored for the other side.
 *  `broom` hands him a push broom held out in front, head on the deck. */
export function Figure({ broom = false }: { broom?: boolean }) {
  return (
    <svg viewBox="0 0 64 104" className="sh-svg" aria-hidden>
      <defs>
        <radialGradient id="sh-lamp" cx="0" cy="0.5" r="1">
          <stop offset="0" stopColor="rgba(255,240,200,.9)" />
          <stop offset="1" stopColor="rgba(255,240,200,0)" />
        </radialGradient>
      </defs>
      <g className="sh-body">
        {/* back leg */}
        <g className="sh-leg sh-leg--b">
          <path d="M33 60 L33 92" stroke="#2b2e3a" strokeWidth="7" strokeLinecap="round" fill="none" />
          <path d="M35 95 H24" stroke="#0c0c0e" strokeWidth="5.5" strokeLinecap="round" />
        </g>
        {/* torso */}
        <g className="sh-torso">
          <path d="M22 34 Q22 28 30 28 L36 28 Q44 28 44 36 L44 62 L22 62 Z" fill="#30343f" stroke="rgba(255,255,255,.5)" strokeWidth="1.2" />
          {/* belt, gaff roll, radio */}
          <rect x="22" y="56" width="22" height="3.5" fill="#0b0b0d" />
          <circle cx="42" cy="58" r="4.2" fill="#9aa1a8" stroke="#5e656c" strokeWidth="1.6" />
          <circle cx="42" cy="58" r="1.6" fill="#17171b" />
          <rect x="23" y="49" width="5" height="9" rx="1" fill="#2a2a30" />
          <line x1="25" y1="49" x2="25" y2="44" stroke="#2a2a30" strokeWidth="1.2" />
          {/* head, beanie, headlamp */}
          <circle cx="31" cy="19" r="8" fill="#c99a78" />
          <path d="M22.5 18 Q23 9 31 9 Q39 9 39.5 18 Z" fill="#3a3f4d" />
          <rect x="22" y="16.5" width="18" height="3" rx="1.5" fill="#2c2c33" />
          <rect x="20.5" y="15.8" width="4" height="4.4" rx="1" fill="#e8e2c8" />
          <path className="sh-lamp" d="M21 18 L-22 4 L-22 34 Z" fill="url(#sh-lamp)" />
          {broom && (
            <g className="sh-broom">
              {/* handle: from behind his hands down to the head on the deck, out in front */}
              <line x1="25" y1="40" x2="-6" y2="92" stroke="#a87444" strokeWidth="2.6" strokeLinecap="round" />
              {/* head + bristles */}
              <rect x="-19" y="90" width="24" height="4.6" rx="1.2" fill="#6e4524" stroke="#3d2513" strokeWidth=".8" />
              <rect x="-18" y="94.4" width="22" height="3.6" rx=".6" fill="#d6bd7b" />
              <path d="M-16 94.6 v3.2 M-12 94.6 v3.2 M-8 94.6 v3.2 M-4 94.6 v3.2 M0 94.6 v3.2" stroke="#a88d4c" strokeWidth=".6" />
            </g>
          )}
          {/* arm */}
          <g className="sh-arm">
            <path d="M30 34 L18 46" stroke="#3a3f4d" strokeWidth="6.5" strokeLinecap="round" />
            <circle cx="17" cy="47" r="3.4" fill="#c99a78" />
          </g>
          {/* thumbs-up: arm raised high and out, away from the stage, oversized fist + thumb */}
          <g className="sh-arm-up">
            <path d="M37 32 L47 22 L51 13" stroke="#3a3f4d" strokeWidth="6.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
            {/* fist */}
            <rect x="46" y="4" width="11" height="10" rx="3.5" fill="#d8a885" stroke="#6b4530" strokeWidth="1.1" />
            <path d="M47.5 7.5 h7 M47.5 10.5 h7" stroke="#6b4530" strokeWidth=".8" strokeLinecap="round" />
            {/* thumb, pointing up */}
            <rect x="53" y="-6" width="4.6" height="12" rx="2.3" fill="#d8a885" stroke="#6b4530" strokeWidth="1.1" />
            {/* glint */}
            <path className="sh-glint" d="M63 -8 l1.4 3.4 3.4 1.4 -3.4 1.4 -1.4 3.4 -1.4 -3.4 -3.4 -1.4 3.4 -1.4 z" fill="#fff6c8" />
          </g>
        </g>
        {/* front leg */}
        <g className="sh-leg sh-leg--f">
          <path d="M31 60 L31 92" stroke="#343846" strokeWidth="7" strokeLinecap="round" fill="none" />
          <path d="M33 95 H22" stroke="#0c0c0e" strokeWidth="5.5" strokeLinecap="round" />
        </g>
      </g>
    </svg>
  );
}

export const Stagehand: React.FC = () => {
  const [phase, setPhase] = useState<Phase>('off');
  const [side, setSide] = useState<Side>('right');
  const busy = useRef(false);
  const timers = useRef<number[]>([]);

  useEffect(() => {
    const later = (fn: () => void, ms: number) => timers.current.push(window.setTimeout(fn, ms));
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const beat = (s: Side, shift: number, thumbs: boolean, done: () => void) => {
      const st = useShowStore.getState();
      if (reduced) {
        st.setStageShift(shift);
        done();
        return;
      }
      setSide(s);
      setPhase('enter');
      later(() => {
        setPhase('push');
        useShowStore.getState().setStageShift(shift);
      }, T.enter);
      const hold = thumbs ? T.thumbs : 250; // brief straighten-up when there's no thumbs-up
      if (thumbs) later(() => setPhase('thumbs'), T.enter + T.push);
      later(() => setPhase('exit'), T.enter + T.push + hold);
      later(() => {
        setPhase('off');
        done();
      }, T.enter + T.push + hold + T.exit);
    };

    const run = () => {
      if (busy.current || useShowStore.getState().status !== 'done') return;
      busy.current = true;
      later(() => {
        beat('right', -STAGE_SHIFT_PX, false, () => {
          useShowStore.getState().announce('Stage moved. A little to the left.', 'CREW', 'chatter');
          later(() => {
            useShowStore.getState().announce('Client says split the difference.', 'PROD', 'chatter');
            later(() => {
              beat('left', 0, true, () => {
                useShowStore.getState().announce('Difference split.', 'CREW', 'chatter');
              });
            }, 1400);
          }, 5000);
        });
      }, 900);
    };

    // Dev only: freeze him in a pose for visual QA, e.g. __stagehandPose('left', 'thumbs')
    if ((import.meta as any).env?.DEV) {
      (window as any).__stagehandPose = (sd: Side, ph: Phase) => { setSide(sd); setPhase(ph); };
    }

    // If the show restarts (↻) mid-gag, he vanishes and the stage snaps home
    const unsub = useShowStore.subscribe((st, prev) => {
      if (busy.current && prev.status === 'done' && st.status !== 'done') {
        timers.current.forEach(clearTimeout);
        timers.current = [];
        setPhase('off');
        useShowStore.getState().setStageShift(0);
      }
    });

    window.addEventListener('nebula:stagehand', run);
    return () => {
      window.removeEventListener('nebula:stagehand', run);
      unsub();
      timers.current.forEach(clearTimeout);
    };
  }, []);

  if (phase === 'off') return null;
  return (
    <div className={`stagehand stagehand--${side}`} data-phase={phase} aria-hidden>
      <style>{`
        .stagehand {
          position: absolute; bottom: 0; z-index: 30; pointer-events: none; max-width: none;
          width: clamp(64px, 7.4vw, 96px); height: clamp(104px, 12vw, 156px);
        }
        /* He stands just outside the stage, shoulder to its edge */
        .stagehand--right { left: calc(100% - 22px); }
        .stagehand--left  { right: calc(100% - 22px); }
        .stagehand--left .sh-flip { transform: scaleX(-1); }
        /* Phones: the stage is full width, so he stands just inside its edge */
        @media (max-width: 767px) {
          .stagehand--right { left: auto; right: 2px; }
          .stagehand--left  { right: auto; left: 2px; }
        }
        .sh-flip, .sh-walk { width: 100%; height: 100%; }
        .sh-svg { width: 100%; height: 100%; overflow: visible; filter: drop-shadow(0 0 1.5px rgba(255,255,255,.55)) drop-shadow(0 0 10px rgba(160,190,255,.25)); }

        /* walk in / out from off-screen */
        .stagehand--right[data-phase="enter"] .sh-walk { animation: sh-in-r ${T.enter}ms cubic-bezier(.3,.6,.4,1) both; }
        /* The left-side stagehand lives inside a mirrored box (.sh-flip), which also
           mirrors movement: the right-side keyframes read as "from/to the left". */
        .stagehand--left[data-phase="enter"]  .sh-walk { animation: sh-in-r ${T.enter}ms cubic-bezier(.3,.6,.4,1) both; }
        .stagehand--right[data-phase="exit"]  .sh-walk { animation: sh-out-r ${T.exit}ms cubic-bezier(.5,0,.8,.6) both; }
        .stagehand--left[data-phase="exit"]   .sh-walk { animation: sh-out-r ${T.exit}ms cubic-bezier(.5,0,.8,.6) both; }
        @keyframes sh-in-r  { from { transform: translateX(55vw); } to { transform: none; } }
        @keyframes sh-out-r { from { transform: none; } to { transform: translateX(55vw); } }
        /* exiting he turns around and walks away */
        .stagehand[data-phase="exit"] .sh-svg { transform: scaleX(-1); }

        /* legs */
        .sh-leg { transform-box: fill-box; transform-origin: 50% 0%; }
        .stagehand[data-phase="enter"] .sh-leg--f, .stagehand[data-phase="exit"] .sh-leg--f { animation: sh-step .36s ease-in-out infinite alternate; }
        .stagehand[data-phase="enter"] .sh-leg--b, .stagehand[data-phase="exit"] .sh-leg--b { animation: sh-step .36s ease-in-out infinite alternate-reverse; }
        .stagehand[data-phase="push"] .sh-leg--f { animation: sh-step .5s ease-in-out infinite alternate; }
        .stagehand[data-phase="push"] .sh-leg--b { animation: sh-step-push .5s ease-in-out infinite alternate-reverse; }
        @keyframes sh-step { from { transform: rotate(-20deg); } to { transform: rotate(20deg); } }
        @keyframes sh-step-push { from { transform: rotate(10deg); } to { transform: rotate(38deg); } }

        /* bob while walking */
        .sh-body { transform-box: view-box; transform-origin: 50% 92%; }
        .stagehand[data-phase="enter"] .sh-body, .stagehand[data-phase="exit"] .sh-body { animation: sh-bob .18s ease-in-out infinite alternate; }
        @keyframes sh-bob { from { transform: translateY(0); } to { transform: translateY(-2px); } }

        /* push: lean in hard, both arms on the stage */
        .sh-torso { transform-box: view-box; transform-origin: 50% 60%; transition: transform .25s ease; }
        .stagehand[data-phase="push"] .sh-torso { transform: rotate(-24deg) translateX(-3px); animation: sh-strain .25s ease-in-out infinite alternate; }
        @keyframes sh-strain { from { transform: rotate(-24deg) translateX(-3px); } to { transform: rotate(-26deg) translateX(-4px); } }
        .sh-arm { transform-box: view-box; transform-origin: 47% 33%; transition: transform .2s ease; }
        .stagehand[data-phase="push"] .sh-arm { transform: rotate(38deg); }

        /* thumbs up */
        .sh-arm-up { opacity: 0; transform-box: view-box; transform-origin: 58% 31%; }
        .stagehand[data-phase="thumbs"] .sh-arm { opacity: 0; }
        .stagehand[data-phase="thumbs"] .sh-arm-up { opacity: 1; animation: sh-thumb-pop .45s cubic-bezier(.3,1.6,.5,1) both; }
        @keyframes sh-thumb-pop { from { transform: rotate(40deg) scale(.4); } to { transform: none; } }
        .sh-glint { opacity: 0; transform-box: fill-box; transform-origin: center; }
        .stagehand[data-phase="thumbs"] .sh-glint { animation: sh-glint .7s ease-out .35s both; }
        @keyframes sh-glint { 0% { opacity: 0; transform: scale(.2) rotate(0deg); } 40% { opacity: 1; transform: scale(1.3) rotate(45deg); } 100% { opacity: 0; transform: scale(.6) rotate(90deg); } }
        .stagehand[data-phase="thumbs"] .sh-body { animation: sh-nod .3s ease-in-out .3s 2 alternate; }
        @keyframes sh-nod { to { transform: translateY(-3px); } }

        .sh-lamp { opacity: .85; }
      `}</style>
      <div className="sh-flip">
        <div className="sh-walk">
          <Figure />
        </div>
      </div>
    </div>
  );
};

export default Stagehand;

/* ======================================================================
 * Sweeper — the same stagehand with a push broom. Walks left → right along
 * the bottom of the window and shoves the confetti pile off-screen.
 * ConfettiPile uses sweepTiming() so the pile moves exactly with his broom.
 * ==================================================================== */
export const SWEEP_MS = 3200;

export function sweepTiming() {
  const vw = document.documentElement.clientWidth;
  const w = window.innerWidth < 768 ? 64 : 88;     // figure width (px)
  const h = Math.round(w * 1.625);
  const reach = w + Math.round((19 / 64) * w);     // broom tip, measured from his box's left edge
  const s0 = -(reach + 12);                        // start: broom just off the left edge
  const s1 = vw + 24;                              // end: he's fully off the right edge
  const speed = (s1 - s0) / SWEEP_MS;              // px per ms
  const pileDelay = (0 - (s0 + reach)) / speed;    // when the broom tip reaches the pile's left edge
  return { w, h, s0, s1, pileDelay, pileDur: SWEEP_MS - pileDelay, pileEnd: s1 + reach };
}

export const Sweeper: React.FC<{ timing: ReturnType<typeof sweepTiming> }> = ({ timing }) => (
  <div
    className="sweeper"
    aria-hidden
    style={{
      width: timing.w,
      height: timing.h,
      ['--s0' as any]: `${timing.s0}px`,
      ['--s1' as any]: `${timing.s1}px`,
      animationDuration: `${SWEEP_MS}ms`,
    }}
  >
    <style>{`
      .sweeper {
        position: fixed; left: 0; bottom: 2px; z-index: 60; pointer-events: none; max-width: none;
        animation: sweeper-walk linear forwards;
      }
      @keyframes sweeper-walk { from { transform: translateX(var(--s0)); } to { transform: translateX(var(--s1)); } }
      .sweeper .sh-svg {
        width: 100%; height: 100%; overflow: visible; transform: scaleX(-1); /* face the way he walks */
        filter: drop-shadow(0 0 1.5px rgba(255,255,255,.55)) drop-shadow(0 0 10px rgba(160,190,255,.25));
      }
      .sweeper .sh-arm-up { display: none; }
      .sweeper .sh-lamp { opacity: .85; }
      .sweeper .sh-leg { transform-box: fill-box; transform-origin: 50% 0%; }
      .sweeper .sh-leg--f { animation: sw-step .34s ease-in-out infinite alternate; }
      .sweeper .sh-leg--b { animation: sw-step .34s ease-in-out infinite alternate-reverse; }
      @keyframes sw-step { from { transform: rotate(-18deg); } to { transform: rotate(18deg); } }
      .sweeper .sh-body { animation: sw-bob .17s ease-in-out infinite alternate; }
      @keyframes sw-bob { from { transform: translateY(0); } to { transform: translateY(-1.5px); } }
      /* scrub the broom back and forth as he walks */
      .sweeper .sh-broom, .sweeper .sh-arm { animation: sw-scrub .17s ease-in-out infinite alternate; }
      @keyframes sw-scrub { from { transform: translateX(0); } to { transform: translateX(-2.5px); } }
      @media (prefers-reduced-motion: reduce) { .sweeper { display: none; } }
    `}</style>
    <Figure broom />
  </div>
);
