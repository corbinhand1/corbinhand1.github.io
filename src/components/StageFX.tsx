import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useShowStore } from '../stores/showStore';
import { sfx } from '../lib/sfx';

/** Go Video timeline: gobo out, a beat, then the drop falls out of frame */
export const KABUKI = { GOBO_OUT: 280, BEAT: 220, FALL: 740 };
/** When the stage behind is fully revealed (ms after Go Video) */
export const KABUKI_REVEAL_MS = KABUKI.GOBO_OUT + KABUKI.BEAT + KABUKI.FALL;

const reducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* ======================================================================
 * Kabuki drop — a full-width velvet drop that hangs from the top of the
 * window down to just below the logo, with the logo "printed" on it so the
 * brand is visible from the first second. On "Go Video" it releases and
 * falls, revealing the live logo. When the lights come up, they wash the
 * curtain (the stage beams themselves are behind it).
 *
 * It's still anchored to the logo wrapper (so its bottom edge sits just under
 * the logo); we measure that wrapper's page position and stretch the drop out
 * to the window's left/right edges and up to the top.
 * ==================================================================== */
type Geo = { x: number; y: number; w: number; h: number; vw: number; logo: { x: number; y: number; w: number; h: number } | null };

function pagePosition(el: HTMLElement) {
  // offsetLeft/Top ignore transforms, so the hero's entrance animation and the
  // stagehand's push don't throw the measurement off
  let x = 0, y = 0, n: HTMLElement | null = el;
  while (n) { x += n.offsetLeft; y += n.offsetTop; n = n.offsetParent as HTMLElement | null; }
  return { x, y };
}

export const KabukiDrop: React.FC = () => {
  const rolling = useShowStore((s) => s.videoRolling);
  const lightLevel = useShowStore((s) => s.lightLevel);
  const lightsUp = lightLevel > 0;
  const setKabukiOut = useShowStore((s) => s.setKabukiOut);
  // hung -> goboOut (gobo snaps out) -> dropping (released) -> gone
  const [state, setState] = useState<'hung' | 'goboOut' | 'dropping' | 'gone'>(rolling ? 'gone' : 'hung');
  const ref = useRef<HTMLDivElement>(null);
  const [geo, setGeo] = useState<Geo | null>(null);

  useEffect(() => {
    if (rolling) {
      if (reducedMotion()) { setState('gone'); return; }
      // Go Video: gobo out first, a beat, then release the drop
      setState((s) => (s === 'hung' ? 'goboOut' : s));
      const { GOBO_OUT, BEAT, FALL } = KABUKI;
      const t1 = window.setTimeout(() => setState((s) => (s === 'goboOut' ? 'dropping' : s)), GOBO_OUT + BEAT);
      const t2 = window.setTimeout(() => setState('gone'), GOBO_OUT + BEAT + FALL);
      return () => { clearTimeout(t1); clearTimeout(t2); };
    }
    setState('hung'); // replay: re-hang the drop
  }, [rolling]);

  // Tell the rest of the show when the stage behind is revealed (beams + logo wait for this)
  useEffect(() => { setKabukiOut(state === 'gone'); }, [state, setKabukiOut]);

  useLayoutEffect(() => {
    if (state === 'gone') return;
    const parent = ref.current?.parentElement;
    if (!parent) return;
    const measure = () => {
      const { x, y } = pagePosition(parent);
      // the real logo image, so the printed one sits exactly on top of it
      const img = parent.querySelector('img[alt="Nebula Creative Logo"]') as HTMLImageElement | null;
      const lp = img ? pagePosition(img) : null;
      setGeo({
        x, y, w: parent.offsetWidth, h: parent.offsetHeight, vw: document.documentElement.clientWidth,
        logo: img && lp ? { x: lp.x, y: lp.y, w: img.offsetWidth, h: img.offsetHeight } : null,
      });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(parent);
    const img = parent.querySelector('img[alt="Nebula Creative Logo"]');
    if (img) ro.observe(img);
    window.addEventListener('resize', measure);
    return () => { ro.disconnect(); window.removeEventListener('resize', measure); };
  }, [state]);

  if (state === 'gone') return null;

  const box: React.CSSProperties = geo
    ? { left: -geo.x, top: -geo.y, width: geo.vw, height: geo.y + geo.h + 10 }
    : { visibility: 'hidden' };
  // the gobo sits exactly over the real logo; the hotspot is centred on it
  const L = geo?.logo;
  const logoBox: React.CSSProperties = L ? { left: L.x, top: L.y, width: L.w, height: L.h } : { visibility: 'hidden' };
  const hot = geo && L
    ? { ['--cx' as any]: `${((L.x + L.w / 2) / geo.vw) * 100}%`, ['--cy' as any]: `${((L.y + L.h / 2) / (geo.y + geo.h + 10)) * 100}%` }
    : {};

  return (
    <div ref={ref} className={`kabuki ${state === 'dropping' ? 'kabuki--drop' : 'kabuki--hung'} ${state === 'hung' ? '' : 'kabuki--gobo-out'}`} style={{ ...box, ...hot }} aria-hidden>
      <style>{`
        .kabuki {
          position: absolute; z-index: 40; pointer-events: none; max-width: none; overflow: hidden;
          /* a soft shadow where the hem meets the deck */
          filter: drop-shadow(0 14px 18px rgba(0,0,0,.55));
        }
        /* the drape itself: everything inside falls together */
        .kabuki__drape {
          position: absolute; inset: 0; will-change: transform;
          /* Real velvet: Unsplash photo by Liana S (@cherstve_pechivo), Unsplash License (free, no attribution required) */
          background: #2a040b url('/assets/curtain-velvet.jpg') center 30% / cover no-repeat;
        }
        /* stage lighting: front-of-house hotspot on the logo, falloff to the sides and up into the flies,
           and the fabric getting darker toward the floor */
        .kabuki__shadow {
          position: absolute; inset: 0;
          background:
            radial-gradient(ellipse 62% 88% at var(--cx, 50%) var(--cy, 55%), rgba(0,0,0,0) 30%, rgba(0,0,0,.42) 72%, rgba(0,0,0,.78) 100%),
            linear-gradient(to bottom, rgba(0,0,0,.85) 0%, rgba(0,0,0,.35) 22%, rgba(0,0,0,0) 46%, rgba(0,0,0,0) 78%, rgba(0,0,0,.4) 100%);
        }
        .kabuki__hotspot {
          position: absolute; inset: 0; mix-blend-mode: screen;
          background: radial-gradient(ellipse 34% 52% at var(--cx, 50%) var(--cy, 55%), rgba(255,196,160,.20), rgba(255,170,130,.07) 50%, rgba(0,0,0,0) 75%);
        }
        .kabuki__wash { /* the stage beams hitting the velvet on "Go Lights" */
          position: absolute; inset: 0; mix-blend-mode: screen; opacity: 0; transition: opacity 2.5s ease-out;
          background:
            radial-gradient(ellipse 22% 80% at 24% 0%, rgba(255,190,90,.30), rgba(255,150,40,.08) 55%, transparent 75%),
            radial-gradient(ellipse 22% 80% at 50% 0%, rgba(255,190,90,.24), rgba(255,150,40,.06) 55%, transparent 75%),
            radial-gradient(ellipse 22% 80% at 76% 0%, rgba(255,190,90,.30), rgba(255,150,40,.08) 55%, transparent 75%);
        }
        .kabuki__wash[data-on="true"] { opacity: 1; }
        /* the logo as a projected gobo: bent by the folds (SVG displacement), shaded by them (overlay),
           with a soft edge and a little light spill */
        .kabuki__gobo { position: absolute; max-width: none; transition: opacity .28s ease-in; }
        .kabuki--gobo-out .kabuki__gobo { opacity: 0; } /* gobo cue out before the drop */
        .kabuki__gobo img {
          position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain;
        }
        .kabuki__gobo .g-light {
          filter: url(#kabuki-folds) grayscale(1) brightness(3) blur(.5px);
          mix-blend-mode: overlay; opacity: .95;
        }
        .kabuki__gobo .g-glow {
          filter: url(#kabuki-folds) grayscale(1) brightness(2.2) sepia(.35) blur(6px);
          mix-blend-mode: screen; opacity: .22;
        }
        .kabuki--hung { animation: kabuki-in .5s ease-out both; }
        @keyframes kabuki-in { from { opacity: 0; } to { opacity: 1; } }
        /* Released from the pipe: a split-second sag, then free fall straight down out of frame */
        .kabuki--drop .kabuki__drape { animation: kabuki-fall .7s linear forwards; }
        /* release sag (ease-out), then free fall: distance grows with time squared (ease-in quad) */
        @keyframes kabuki-fall {
          0%   { transform: translateY(0);    animation-timing-function: cubic-bezier(.2,.7,.4,1); }
          10%  { transform: translateY(1.4%); animation-timing-function: cubic-bezier(.55,.085,.68,.53); }
          100% { transform: translateY(103%); }
        }
        @media (prefers-reduced-motion: reduce) { .kabuki--drop .kabuki__drape, .kabuki--hung { animation: none; } }
      `}</style>
      {/* horizontal-only waviness that follows the vertical folds */}
      <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden>
        <filter id="kabuki-folds" x="-5%" y="-5%" width="110%" height="110%">
          <feTurbulence type="fractalNoise" baseFrequency="0.035 0.0008" numOctaves="2" seed="11" result="n" />
          <feDisplacementMap in="SourceGraphic" in2="n" scale="9" xChannelSelector="R" yChannelSelector="B" />
        </filter>
      </svg>
      <div className="kabuki__drape">
        <div className="kabuki__shadow" />
        <div className="kabuki__hotspot" />
        {/* Lights Go: front light on the drape. Flashes to full, then settles with the rig level */}
        <div className="kabuki__wash" data-on={lightsUp ? 'true' : 'false'} style={lightsUp ? { opacity: 0.6 + 0.4 * lightLevel } : undefined} />
        <div className="kabuki__gobo" style={logoBox}>
          <img className="g-glow" src="/assets/Nebula Logo Color Text.png" alt="" />
          <img className="g-light" src="/assets/Nebula Logo Color Text.png" alt="" />
        </div>
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
