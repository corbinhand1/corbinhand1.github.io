import React, { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { useShowStore } from '../stores/showStore';
import { CHATTER, SM_REPLIES } from '../config/chatter';
import { sfx } from '../lib/sfx';

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ------------------------------------------------------------------ */
/* Follow spot: a warm spot that tracks the pointer once lights are up */
/* ------------------------------------------------------------------ */
function FollowSpot() {
  const lightsUp = useShowStore((s) => s.lightLevel > 0);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!lightsUp || prefersReducedMotion()) return;
    const cur = { x: window.innerWidth / 2, y: window.innerHeight * 0.32 };
    const target = { ...cur };
    let raf = 0;

    const paint = () => {
      ref.current?.style.setProperty('--sx', `${cur.x}px`);
      ref.current?.style.setProperty('--sy', `${cur.y}px`);
    };
    const step = () => {
      // a little lag, like a real operator
      cur.x += (target.x - cur.x) * 0.12;
      cur.y += (target.y - cur.y) * 0.12;
      paint();
      if (Math.abs(target.x - cur.x) > 0.5 || Math.abs(target.y - cur.y) > 0.5) {
        raf = requestAnimationFrame(step);
      } else {
        raf = 0;
      }
    };
    const onMove = (e: PointerEvent) => {
      target.x = e.clientX;
      target.y = e.clientY;
      if (!raf) raf = requestAnimationFrame(step);
    };
    paint();
    window.addEventListener('pointermove', onMove, { passive: true });
    window.addEventListener('pointerdown', onMove, { passive: true });
    return () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerdown', onMove);
      cancelAnimationFrame(raf);
    };
  }, [lightsUp]);

  return (
    <div
      ref={ref}
      aria-hidden
      className="fixed inset-0 pointer-events-none"
      style={{
        zIndex: 12,
        opacity: lightsUp ? 1 : 0,
        transition: 'opacity 2s ease',
        mixBlendMode: 'screen',
        background:
          'radial-gradient(circle clamp(110px, 16vw, 190px) at var(--sx, 50%) var(--sy, 32%), rgba(255,236,200,0.26) 0%, rgba(255,226,170,0.14) 55%, rgba(255,220,160,0) 100%)',
      }}
    />
  );
}

/* --------------------------- Haze ("places") --------------------------- */
function Haze() {
  const haze = useShowStore((s) => s.haze);
  return (
    <AnimatePresence>
      {haze && (
        <motion.div
          aria-hidden
          className="fixed inset-0 pointer-events-none overflow-hidden"
          style={{ zIndex: 13 }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 2.5 }}
        >
          <style>{`
            @keyframes haze-drift-a { 0% { transform: translate(-20vw, 10vh) scale(1); } 50% { transform: translate(15vw, -5vh) scale(1.2); } 100% { transform: translate(-20vw, 10vh) scale(1); } }
            @keyframes haze-drift-b { 0% { transform: translate(25vw, 20vh) scale(1.1); } 50% { transform: translate(-10vw, 5vh) scale(0.9); } 100% { transform: translate(25vw, 20vh) scale(1.1); } }
            @keyframes haze-drift-c { 0% { transform: translate(0, 40vh) scale(1.3); } 50% { transform: translate(10vw, 25vh) scale(1.1); } 100% { transform: translate(0, 40vh) scale(1.3); } }
            .haze-blob { position: absolute; left: 10vw; top: 0; width: 90vw; height: 70vh; border-radius: 50%; filter: blur(60px); mix-blend-mode: screen; }
          `}</style>
          <div className="haze-blob" style={{ background: 'radial-gradient(closest-side, rgba(220,225,255,.24), transparent)', animation: 'haze-drift-a 22s ease-in-out infinite' }} />
          <div className="haze-blob" style={{ background: 'radial-gradient(closest-side, rgba(255,230,200,.18), transparent)', animation: 'haze-drift-b 28s ease-in-out infinite' }} />
          <div className="haze-blob" style={{ background: 'radial-gradient(closest-side, rgba(200,215,255,.20), transparent)', animation: 'haze-drift-c 34s ease-in-out infinite' }} />
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* ---------------- Blackout: everything dark except the big button ---------------- */
function Blackout() {
  const on = useShowStore((s) => s.blackout);
  const [hole, setHole] = useState({ x: 50, y: 60, r: 90, unit: '%' as '%' | 'px' });

  useEffect(() => {
    if (!on) return;
    const btn = document.querySelector('.launch-btn');
    if (btn) {
      const r = btn.getBoundingClientRect();
      setHole({ x: r.left + r.width / 2, y: r.top + r.height / 2, r: r.width / 2, unit: 'px' });
    }
  }, [on]);

  const at = `${hole.x}${hole.unit} ${hole.y}${hole.unit}`;
  return (
    <AnimatePresence>
      {on && (
        <motion.div
          aria-hidden
          className="fixed inset-0 pointer-events-none"
          style={{
            zIndex: 9990,
            background: `radial-gradient(circle at ${at}, rgba(0,0,0,0) 0px, rgba(0,0,0,0) ${hole.r * 1.25}px, rgba(0,0,0,0.97) ${hole.r * 2.1}px)`,
          }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.12 }}
        />
      )}
    </AnimatePresence>
  );
}

/* --------------- House lights (fire marshal) --------------- */
function HouseLights() {
  const on = useShowStore((s) => s.houseLights);
  return (
    <AnimatePresence>
      {on && (
        <motion.div
          aria-hidden
          className="fixed inset-0 pointer-events-none"
          style={{ zIndex: 9989, background: 'linear-gradient(180deg, rgba(240,244,255,.30), rgba(240,244,255,.18))', mixBlendMode: 'screen' }}
          // fluorescent tubes flicker on
          initial={{ opacity: 0 }}
          animate={{ opacity: [0, 0.9, 0.2, 1, 0.6, 1] }}
          exit={{ opacity: 0, transition: { duration: 1.2 } }}
          transition={{ duration: 0.7, times: [0, 0.1, 0.2, 0.35, 0.5, 1] }}
        />
      )}
    </AnimatePresence>
  );
}

/* --------------- Keyboard: space/enter = GO, plus easter eggs --------------- */
export function triggerHaze() {
  const st = useShowStore.getState();
  if (st.haze) return;
  st.setHaze(true);
  st.announce('Places, please.', 'SM', 'cue');
  st.announce('Haze is up. Sorry, smoke detectors.', 'LX', 'chatter');
  window.setTimeout(() => useShowStore.getState().setHaze(false), 22000);
}

export function triggerBlackout() {
  const st = useShowStore.getState();
  if (st.blackout) return;
  st.setBlackout(true);
  st.announce('Go blackout.', 'SM', 'cue');
  sfx.click(st.soundOn);
  window.setTimeout(() => {
    const s2 = useShowStore.getState();
    s2.setBlackout(false);
    s2.announce('Lights restored. Who touched the grand master?', 'LX', 'chatter');
  }, 6000);
}

function useKeyboard() {
  useEffect(() => {
    let buf = '';
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const t = e.target instanceof HTMLElement ? e.target : null;
      const tag = t?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || t?.isContentEditable) return;

      const st = useShowStore.getState();
      const calling = st.status === 'standby' || st.status === 'approach';
      // Space/Enter call GO — unless a button has focus (then its own click handles it)
      if (calling && (e.key === ' ' || e.key === 'Enter') && tag !== 'BUTTON' && tag !== 'A' && t?.getAttribute('role') !== 'button') {
        e.preventDefault();
        st.callGo();
        return;
      }

      if (e.key.length === 1) {
        buf = (buf + e.key.toLowerCase()).slice(-12);
        if (buf.endsWith('places')) { buf = ''; triggerHaze(); }
        else if (buf.endsWith('blackout')) { buf = ''; triggerBlackout(); }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}

/* --------------- Headset chatter once the show is up --------------- */
function useHeadsetChatter() {
  const done = useShowStore((s) => s.status === 'done');
  useEffect(() => {
    if (!done) return;
    const order = [...CHATTER].sort(() => Math.random() - 0.5);
    let i = 0;
    let t: number;
    const next = (first = false) => {
      t = window.setTimeout(() => {
        if (document.hidden) return next();
        const line = order[i++ % order.length];
        const st = useShowStore.getState();
        st.announce(line.text, line.who, 'chatter');
        if (Math.random() < 0.6) {
          window.setTimeout(() => {
            useShowStore.getState().announce(SM_REPLIES[Math.floor(Math.random() * SM_REPLIES.length)], 'SM', 'info');
          }, 1400);
        }
        next();
      }, first ? 5000 : 11000 + Math.random() * 12000);
    };
    next(true);
    return () => clearTimeout(t);
  }, [done]);
}

export const ShowFX: React.FC = () => {
  useKeyboard();
  useHeadsetChatter();
  return (
    <>
      <FollowSpot />
      <Haze />
      <HouseLights />
      <Blackout />
    </>
  );
};

export default ShowFX;
