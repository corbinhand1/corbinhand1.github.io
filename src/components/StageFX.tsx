import React, { useEffect, useRef, useState } from 'react';
import { useShowStore } from '../stores/showStore';
import { sfx } from '../lib/sfx';

const reducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ======================================================================
 * Kabuki drop — a velvet drop hangs in front of the logo (with the logo
 * "printed" on it, so the brand is visible from the first second). On
 * "Go Video" it releases and falls, revealing the live logo.
 * ==================================================================== */
export const KabukiDrop: React.FC = () => {
  const rolling = useShowStore((s) => s.videoRolling);
  const [state, setState] = useState<'hung' | 'dropping' | 'gone'>(rolling ? 'gone' : 'hung');

  useEffect(() => {
    if (rolling) {
      setState((s) => (s === 'hung' ? 'dropping' : s));
      const id = window.setTimeout(() => setState('gone'), reducedMotion() ? 0 : 750);
      return () => clearTimeout(id);
    }
    setState('hung'); // replay: re-hang the drop
  }, [rolling]);

  if (state === 'gone') return null;
  return (
    <div className={`kabuki ${state === 'dropping' ? 'kabuki--drop' : 'kabuki--hung'}`} aria-hidden>
      <style>{`
        .kabuki {
          position: absolute; inset: -14px -28px -10px; z-index: 40; pointer-events: none; max-width: none;
          border-radius: 6px 6px 10px 10px; transform-origin: 50% 100%;
          background:
            linear-gradient(to bottom, rgba(0,0,0,.45) 0%, rgba(0,0,0,0) 18%, rgba(0,0,0,0) 78%, rgba(0,0,0,.5) 100%),
            repeating-linear-gradient(90deg, rgba(0,0,0,.38) 0px, rgba(255,255,255,.07) 13px, rgba(0,0,0,.38) 27px),
            linear-gradient(90deg, #4a0912, #7a1222 50%, #4a0912);
          box-shadow: 0 18px 40px rgba(0,0,0,.55), inset 0 0 30px rgba(0,0,0,.5);
        }
        .kabuki::before { /* the pipe it hangs from */
          content: ''; position: absolute; left: -6px; right: -6px; top: -5px; height: 7px; border-radius: 4px;
          background: linear-gradient(#9aa3ad, #3c434b); box-shadow: 0 2px 4px rgba(0,0,0,.6);
        }
        .kabuki__logo {
          position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
        }
        .kabuki__logo img {
          height: 62%; width: auto; max-width: 88%; object-fit: contain;
          filter: grayscale(1) brightness(1.9) contrast(.85); opacity: .5; mix-blend-mode: screen;
        }
        .kabuki--hung { animation: kabuki-in .6s cubic-bezier(.2,.9,.3,1.2) both; }
        @keyframes kabuki-in { from { transform: translateY(-30px); opacity: 0; } to { transform: none; opacity: 1; } }
        .kabuki--drop { animation: kabuki-drop .7s cubic-bezier(.55,0,1,.45) forwards; }
        @keyframes kabuki-drop {
          0%   { transform: translateY(0) scaleY(1); opacity: 1; }
          12%  { transform: translateY(1.5%) scaleY(1.02); opacity: 1; }
          100% { transform: translateY(85%) scaleY(.12); opacity: 0; }
        }
        @media (prefers-reduced-motion: reduce) { .kabuki--drop, .kabuki--hung { animation: none; } }
      `}</style>
      <div className="kabuki__logo">
        <img src="/assets/Nebula Logo Color Text.png" alt="" />
      </div>
    </div>
  );
};

/* ======================================================================
 * CO2 jets — white cryo blasts from both bottom corners.
 * Fire with fireCO2(size).
 * ==================================================================== */
export function fireCO2(size = 1) {
  window.dispatchEvent(new CustomEvent('nebula:co2', { detail: size }));
}

type Blast = { id: number; size: number };

export const CO2Jets: React.FC = () => {
  const [blasts, setBlasts] = useState<Blast[]>([]);
  const id = useRef(0);

  useEffect(() => {
    const on = (e: Event) => {
      const size = Math.min(1.6, Math.max(0.6, (e as CustomEvent).detail ?? 1));
      const b = { id: ++id.current, size };
      setBlasts((bs) => [...bs.slice(-3), b]);
      sfx.co2(useShowStore.getState().soundOn, size);
      window.setTimeout(() => setBlasts((bs) => bs.filter((x) => x.id !== b.id)), 2400);
    };
    window.addEventListener('nebula:co2', on);
    return () => window.removeEventListener('nebula:co2', on);
  }, []);

  if (reducedMotion()) return null;
  return (
    <div className="fixed inset-0 pointer-events-none overflow-hidden" style={{ zIndex: 15 }} aria-hidden>
      <style>{`
        .co2 {
          position: absolute; bottom: -4vh; width: calc(var(--s) * 26vw); min-width: 120px; height: calc(var(--s) * 82vh);
          transform-origin: 50% 100%; max-width: none;
          animation: co2-blast 2.2s cubic-bezier(.15,.8,.3,1) forwards;
        }
        .co2--l { left: 4vw; --lean: 7deg; }
        .co2--r { right: 4vw; --lean: -7deg; }
        .co2__core, .co2__cloud { position: absolute; inset: 0; border-radius: 50% 50% 40% 40% / 70% 70% 30% 30%; }
        .co2__core {
          background: radial-gradient(ellipse 42% 98% at 50% 100%, #fff 0%, rgba(245,248,255,.92) 30%, rgba(230,238,255,.55) 58%, rgba(220,230,255,0) 82%);
          filter: blur(3px);
        }
        .co2__cloud {
          inset: -10% -35% 0;
          background: radial-gradient(ellipse 55% 65% at 50% 72%, rgba(245,248,255,.85), rgba(230,238,255,.35) 55%, rgba(230,238,255,0) 78%);
          filter: blur(14px);
          animation: co2-cloud 2.2s ease-out forwards;
        }
        @keyframes co2-blast {
          0%   { transform: rotate(var(--lean)) scaleY(.05) scaleX(.5); opacity: 0; }
          8%   { transform: rotate(var(--lean)) scaleY(1) scaleX(.8); opacity: 1; }
          45%  { transform: rotate(var(--lean)) scaleY(1.05) scaleX(1); opacity: 1; }
          100% { transform: rotate(var(--lean)) scaleY(1.15) scaleX(1.6) translateY(-6vh); opacity: 0; }
        }
        @media (max-width: 767px) {
          .co2 { height: calc(var(--s) * 52vh); width: calc(var(--s) * 30vw); min-width: 0; }
          .co2--l { left: -9vw; --lean: 3deg; }
          .co2--r { right: -9vw; --lean: -3deg; }
        }
        @keyframes co2-cloud { 0% { opacity: 0; } 20% { opacity: 1; } 100% { opacity: 0; transform: scale(1.5) translateY(-8vh); } }
      `}</style>
      {blasts.map((b) => (
        <React.Fragment key={b.id}>
          <div className="co2 co2--l" style={{ ['--s' as any]: b.size }}><div className="co2__cloud" /><div className="co2__core" /></div>
          <div className="co2 co2--r" style={{ ['--s' as any]: b.size }}><div className="co2__cloud" /><div className="co2__core" /></div>
        </React.Fragment>
      ))}
    </div>
  );
};

/* ======================================================================
 * Ballyhoo — moving lights swing and chase colour. The reward for a clean show.
 * Triggered by showStore.ballyhooAt changing.
 * ==================================================================== */
const BEAMS = [
  { x: 8, hue: 200, delay: 0 },
  { x: 24, hue: 280, delay: 0.15 },
  { x: 40, hue: 330, delay: 0.3 },
  { x: 60, hue: 40, delay: 0.3 },
  { x: 76, hue: 160, delay: 0.15 },
  { x: 92, hue: 220, delay: 0 },
];

export const Ballyhoo: React.FC = () => {
  const at = useShowStore((s) => s.ballyhooAt);
  const [active, setActive] = useState(false);

  useEffect(() => {
    if (!at) return;
    setActive(true);
    const id = window.setTimeout(() => setActive(false), 7000);
    return () => clearTimeout(id);
  }, [at]);

  if (!active || reducedMotion()) return null;
  return (
    <div className="fixed inset-0 pointer-events-none overflow-hidden ballyhoo" style={{ zIndex: 6 }} aria-hidden>
      <style>{`
        .ballyhoo { animation: bh-life 7s ease forwards; }
        @keyframes bh-life { 0% { opacity: 0; } 8% { opacity: 1; } 85% { opacity: 1; } 100% { opacity: 0; } }
        .bh-beam {
          position: absolute; top: -6vh; width: 26vw; height: 125vh; margin-left: -13vw; max-width: none;
          transform-origin: 50% 0%;
          clip-path: polygon(47% 0, 53% 0, 100% 100%, 0 100%);
          mix-blend-mode: screen; filter: blur(5px);
          animation: bh-swing 1.4s ease-in-out infinite alternate, bh-hue 2.8s linear infinite;
        }
        @keyframes bh-swing { from { transform: rotate(-38deg); } to { transform: rotate(38deg); } }
        @keyframes bh-hue { from { filter: blur(5px) hue-rotate(0deg); } to { filter: blur(5px) hue-rotate(360deg); } }
      `}</style>
      {BEAMS.map((b, i) => (
        <div
          key={i}
          className="bh-beam"
          style={{
            left: `${b.x}%`,
            animationDelay: `${b.delay}s, ${i * 0.2}s`,
            animationDirection: i % 2 ? 'alternate-reverse, normal' : 'alternate, normal',
            background: `linear-gradient(to bottom, hsla(${b.hue},100%,70%,.85) 0%, hsla(${b.hue},100%,60%,.35) 35%, hsla(${b.hue},100%,55%,0) 85%)`,
          }}
        />
      ))}
    </div>
  );
};
