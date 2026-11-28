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
  const lightsUp = useShowStore((s) => s.lightLevel > 0);
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
      // Before the logo image loads its width is 0 (height is set by CSS). Never measure it as
      // 0 wide: derive the width from the height and the logo's shape (1.5 : 1).
      let lw = img?.offsetWidth ?? 0;
      const lh = img?.offsetHeight ?? 0;
      if (img && !lw && lh) {
        const aspect = img.naturalWidth && img.naturalHeight ? img.naturalWidth / img.naturalHeight : 1.5;
        lw = Math.round(lh * aspect);
      }
      // offsetLeft is from the image's left edge; if it has no width yet it sits at the centre
      const lx = lp ? (img!.offsetWidth ? lp.x : lp.x - lw / 2) : 0;
      setGeo({
        x, y, w: parent.offsetWidth, h: parent.offsetHeight, vw: document.documentElement.clientWidth,
        logo: img && lp && lw && lh ? { x: lx, y: lp.y, w: lw, h: lh } : null,
      });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(parent);
    const img = parent.querySelector('img[alt="Nebula Creative Logo"]');
    if (img) { ro.observe(img); img.addEventListener('load', measure); }
    window.addEventListener('resize', measure);
    return () => { ro.disconnect(); img?.removeEventListener('load', measure); window.removeEventListener('resize', measure); };
  }, [state]);

  if (state === 'gone') return null;

  const box: React.CSSProperties = geo
    ? { left: -geo.x, top: -geo.y, width: geo.vw, height: geo.y + geo.h + 10 }
    : { visibility: 'hidden' };
  // the gobo sits exactly over the real logo; the hotspot is centred on it
  const L = geo?.logo;
  const logoBox: React.CSSProperties = L ? { left: L.x, top: L.y, width: L.w, height: L.h } : { visibility: 'hidden' };
  const hot = geo && L
    ? {
        ['--cx' as any]: `${((L.x + L.w / 2) / geo.vw) * 100}%`,
        ['--cy' as any]: `${((L.y + L.h / 2) / (geo.y + geo.h + 10)) * 100}%`,
      }
    : {};

  // Lights Go wash, built AROUND the logo (no mask: Safari drops masks on fading, blended
  // layers, which let the light hit the gobo). One beam in the space left of the logo, one
  // right of it, and light on the fabric below it; every gradient is zero over the logo box.
  let washBg: string | undefined;
  if (geo && L) {
    const Hk = geo.y + geo.h + 10;
    const m = Math.max(24, L.w * 0.1);                 // clear margin around the logo
    const leftEdge = L.x - m, rightEdge = L.x + L.w + m;
    const beams: string[] = [];
    const beam = (x0: number, x1: number) => {
      const w = x1 - x0;
      if (w < 30) return;
      beams.push(`radial-gradient(ellipse ${w / 2}px ${Hk * 0.95}px at ${x0 + w / 2}px 0px, rgba(255,190,90,.36) 0%, rgba(255,150,40,.12) 55%, rgba(255,150,40,0) 100%)`);
    };
    beam(0, leftEdge);
    beam(rightEdge, geo.vw);
    const y0 = L.y + L.h + m;
    if (y0 < Hk - 10) {
      beams.push(`linear-gradient(to bottom, rgba(255,170,80,0) ${y0}px, rgba(255,170,80,.16) ${y0 + 40}px, rgba(255,150,40,.08) 100%)`);
    }
    washBg = beams.join(', ');
  }

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
        /* No blend modes anywhere in the curtain: when the Lights Go fade starts, browsers
           (Safari especially) re-layer the page and a blended layer can lose its backdrop,
           which made the gobo flash raw white. Plain transparency looks the same and can't flip. */
        .kabuki__hotspot {
          position: absolute; inset: 0;
          background: radial-gradient(ellipse 34% 52% at var(--cx, 50%) var(--cy, 55%), rgba(255,200,170,.14), rgba(255,175,140,.05) 50%, rgba(0,0,0,0) 75%);
        }
        .kabuki__wash { /* the stage beams hitting the velvet on "Go Lights" (background set inline, around the logo) */
          position: absolute; inset: 0; opacity: 0; transition: opacity 3s ease-in-out;
        }
        .kabuki__wash[data-on="true"] { opacity: .62; }
        /* the logo as a projected gobo: bent by the folds (SVG displacement), shaded by them (overlay),
           with a soft edge and a little light spill */
        .kabuki__gobo { position: absolute; max-width: none; transition: opacity .28s ease-in; }
        .kabuki--gobo-out .kabuki__gobo { opacity: 0; } /* gobo cue out before the drop */
        .kabuki__gobo img {
          position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain;
        }
        .kabuki__gobo .g-light {
          filter: url(#kabuki-folds) grayscale(1) brightness(2) sepia(.2) blur(.5px);
          opacity: .42;
        }
        .kabuki__gobo .g-glow {
          filter: url(#kabuki-folds) grayscale(1) brightness(2.2) sepia(.35) blur(6px);
          opacity: .12;
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
        {/* Lights Go: front light on the drape. A smooth fade to a steady level (no flash) */}
        <div className="kabuki__wash" data-on={lightsUp ? 'true' : 'false'} style={washBg ? { background: washBg } : undefined} />
        <div className="kabuki__gobo" style={logoBox}>
          <img className="g-glow" src="/assets/Nebula Logo Color Text.png" alt="" />
          <img className="g-light" src="/assets/Nebula Logo Color Text.png" alt="" />
        </div>
      </div>
    </div>
  );
};

/* ======================================================================
 * CO2 jets — a particle simulation of a real cryo blast from both bottom
 * corners: a tight, bright jet out of the nozzle that widens and slows as it
 * climbs, churns with turbulence, blooms at the top, rolls over and sinks
 * back (CO2 is heavier than air) while it thins out. Backlit cool white.
 * Sized to the window so the whole event stays in frame.
 * Fire with fireCO2(size).
 * ==================================================================== */
export function fireCO2(size = 1) {
  window.dispatchEvent(new CustomEvent('nebula:co2', { detail: size }));
}

type Puff = {
  x: number; y: number; vx: number; vy: number;
  r: number; r0: number; grow: number; age: number; life: number; a: number;
};
type Emitter = { x: number; y: number; dir: number; until: number; rate: number; speed: number; carry: number; scale: number; spread: number };

/** vapour sprite: `hard` gives a firmer edge for the dense jet, soft for the shredding cloud */
function makeSprite(px: number, hard: boolean) {
  const c = document.createElement('canvas');
  c.width = c.height = px;
  const g = c.getContext('2d')!;
  const grd = g.createRadialGradient(px / 2, px / 2, 0, px / 2, px / 2, px / 2);
  if (hard) {
    grd.addColorStop(0, 'rgba(250,252,255,1)');
    grd.addColorStop(0.55, 'rgba(240,246,255,.85)');
    grd.addColorStop(0.8, 'rgba(228,238,255,.25)');
    grd.addColorStop(1, 'rgba(228,238,255,0)');
  } else {
    grd.addColorStop(0, 'rgba(244,248,255,1)');
    grd.addColorStop(0.35, 'rgba(232,240,255,.5)');
    grd.addColorStop(0.7, 'rgba(220,232,255,.14)');
    grd.addColorStop(1, 'rgba(220,232,255,0)');
  }
  g.fillStyle = grd;
  g.fillRect(0, 0, px, px);
  return c;
}

// cheap smooth pseudo-noise for turbulence
const swirl = (x: number, y: number, t: number) =>
  Math.sin(x * 0.017 + t * 2.1) * Math.cos(y * 0.019 - t * 1.6) + 0.5 * Math.sin((x + y) * 0.031 + t * 2.9);

export const CO2Jets: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (reducedMotion()) return;
    const canvas = canvasRef.current!;
    const ctx = canvas.getContext('2d')!;
    const hardSprite = makeSprite(96, true);
    const softSprite = makeSprite(96, false);
    let W = 0, H = 0, dpr = 1;
    const resize = () => {
      dpr = Math.min(2, window.devicePixelRatio || 1);
      W = window.innerWidth; H = window.innerHeight;
      canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    };
    resize();
    window.addEventListener('resize', resize);

    const puffs: Puff[] = [];
    const emitters: Emitter[] = [];
    let raf = 0, last = 0, t = 0;

    // Tuning -------------------------------------------------------------
    const DRAG = 3.1;         // per second: climb ≈ speed / DRAG
    const GRAVITY = 0.34;     // * H per s^2: the spent cloud sinks back
    const JET_AGE = 0.22;     // s: how long a particle stays part of the dense jet
    // --------------------------------------------------------------------

    const fire = (size: number) => {
      const now = performance.now();
      const mobile = W < 768;
      for (const side of [-1, 1]) {
        emitters.push({
          x: side < 0 ? W * (mobile ? 0.1 : 0.07) : W * (mobile ? 0.9 : 0.93),
          y: H + 4,
          dir: -Math.PI / 2 + side * -0.05,
          until: now + (240 + 110 * size),                      // a short, hard burst
          rate: (mobile ? 900 : 1700) * Math.min(size, 1.5),
          speed: H * 2.3 * Math.sqrt(size),                      // tops out ~70% of the window
          carry: 0,
          // particle size and cone width follow the screen width, so phones get slimmer columns
          scale: Math.min(1, Math.max(0.45, W / 1200)),
          spread: mobile ? 0.11 : 0.2,
        });
      }
      if (!raf) { last = now; raf = requestAnimationFrame(tick); }
    };

    const tick = (now: number) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now; t += dt;

      // emit
      for (let i = emitters.length - 1; i >= 0; i--) {
        const e = emitters[i];
        if (now > e.until) { emitters.splice(i, 1); continue; }
        e.carry += e.rate * dt;
        const n = Math.floor(e.carry);
        e.carry -= n;
        for (let k = 0; k < n; k++) {
          const ang = e.dir + (Math.random() - 0.5) * e.spread;   // a column, not a line
          const sp = e.speed * (0.85 + Math.random() * 0.25);
          const r = (7 + Math.random() * 8) * e.scale;
          puffs.push({
            x: e.x + (Math.random() - 0.5) * 6, y: e.y,
            vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
            r, r0: r, grow: (70 + Math.random() * 90) * e.scale,
            age: 0, life: 1.0 + Math.random() * 0.65,   // the whole blast is gone in ~1.6s
            a: 0.5 + Math.random() * 0.3,
          });
        }
      }

      // simulate
      const drag = Math.exp(-DRAG * dt);
      for (let i = puffs.length - 1; i >= 0; i--) {
        const p = puffs[i];
        p.age += dt;
        if (p.age >= p.life) { puffs.splice(i, 1); continue; }
        const speed = Math.hypot(p.vx, p.vy);
        const slow = Math.max(0, 1 - speed / (H * 0.7));
        // the spent top shreds: strong sideways turbulence and a quick sink
        p.vx += (swirl(p.x, p.y, t) * 900 + (Math.random() - 0.5) * 700) * slow * dt;
        p.vy += (GRAVITY * H * slow + swirl(p.y, p.x, t + 3) * 420 * slow) * dt;
        p.vx *= drag; p.vy *= drag;
        p.x += p.vx * dt; p.y += p.vy * dt;
        p.r = Math.min(Math.min(H * 0.11, W * 0.09), p.r + p.grow * dt * (0.7 + 1.5 * slow));
      }

      // draw: each particle is stretched along its motion, so the jet reads as streaks
      // and the breakup reads as torn wisps rather than round puffs
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const draw = (hot: boolean) => {
        ctx.globalCompositeOperation = hot ? 'lighter' : 'source-over';
        for (const p of puffs) {
          const jet = p.age < JET_AGE;
          if (hot && !jet) continue;
          const k = p.age / p.life;
          const fadeIn = Math.min(1, p.age / 0.02);
          const fadeOut = (1 - k) * (1 - k);
          const thin = Math.max(0.1, Math.pow(p.r0 / p.r, 0.6));
          const alpha = hot
            ? 0.16 * (1 - p.age / JET_AGE)
            : p.a * fadeIn * fadeOut * (jet ? 0.9 : thin * 1.25);
          if (alpha <= 0.004) continue;
          const speed = Math.hypot(p.vx, p.vy);
          const stretch = 1 + Math.min(1.8, speed / (H * 0.7)) + (jet ? 0 : 0.5);
          const ang = Math.atan2(p.vy, p.vx);
          const c = Math.cos(ang), s = Math.sin(ang);
          // translate → rotate to motion → stretch along it, squeeze across it
          const sx = stretch, sy = 1;
          ctx.setTransform(dpr * c * sx, dpr * s * sx, -dpr * s * sy, dpr * c * sy, dpr * p.x, dpr * p.y);
          ctx.globalAlpha = Math.min(1, alpha);
          ctx.drawImage(jet ? hardSprite : softSprite, -p.r, -p.r, p.r * 2, p.r * 2);
        }
      };
      draw(false);
      draw(true);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = 'source-over';

      if (puffs.length || emitters.length) raf = requestAnimationFrame(tick);
      else { raf = 0; ctx.clearRect(0, 0, canvas.width, canvas.height); }
    };

    const on = (e: Event) => {
      const size = Math.min(1.6, Math.max(0.6, (e as CustomEvent).detail ?? 1));
      sfx.co2(useShowStore.getState().soundOn, size);
      fire(size);
    };
    window.addEventListener('nebula:co2', on);
    return () => {
      window.removeEventListener('nebula:co2', on);
      window.removeEventListener('resize', resize);
      cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className="fixed inset-0 pointer-events-none"
      style={{ zIndex: 15, width: '100vw', height: '100vh', maxWidth: 'none' }}
    />
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
