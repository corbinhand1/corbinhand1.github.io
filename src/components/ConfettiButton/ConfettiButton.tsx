import React, { useEffect, useState, useMemo, useRef } from 'react';
import confetti from 'canvas-confetti';
import { useShowStore } from '../../stores/showStore';
import { sfx } from '../../lib/sfx';
import { AudioMeter } from '../AudioMeter';

// Types for confetti effects
interface LandingSpec {
  id: number;
  xPct: number;
  delayMs: number;
  w: number;
  h: number;
  color: string;
  rot: number;
}

// Confetti engine hook
function useConfettiEngine() {
  return useMemo(() => {
    const anyConf = confetti as any;
    if (anyConf.create) {
      // Ensure full viewport coverage on mobile
      const canvas = anyConf.create(undefined, { 
        resize: true, 
        useWorker: true, 
        zIndex: 1000,
        // Force full viewport height on mobile
        height: window.innerHeight,
        width: window.innerWidth
      });
      return canvas;
    }
    return confetti;
  }, []);
}

// Rain particle options builder
function buildRainParticleOptions() {
  return {
    startVelocity: 0,
    gravity: 0.7,
    ticks: 3000, // Increased ticks for longer fall
    spread: 20,
    scalar: 0.9,
    originY: -0.1,
    zIndex: 1000,
    // Ensure particles fall past the search bar area
    drift: 0.1, // Slight drift for more natural fall
  };
}

/**
 * ConfettiButton Component
 * Cycles through different confetti effects when clicked
 * 
 * Props:
 * - scheduleLandings: Function to schedule confetti landings
 * - onConfettiPressed: Callback when button is pressed
 */
export const ConfettiButton: React.FC<{
  scheduleLandings: (items: LandingSpec[]) => void;
}> = ({ scheduleLandings }) => {
  const [count, setCount] = useState(0);
  const fire = useConfettiEngine();
  const COLORS = ["#FFD166", "#EF476F", "#06D6A0", "#118AB2", "#FF9F1C", "#9B5DE5"];

  const status = useShowStore((s) => s.status);
  const callGo = useShowStore((s) => s.callGo);
  const coverOpen = useShowStore((s) => s.coverOpen);
  const setCoverOpen = useShowStore((s) => s.setCoverOpen);
  const registerLaunch = useShowStore((s) => s.registerLaunch);
  const lockedUntil = useShowStore((s) => s.lockedUntil);
  const soundOn = useShowStore((s) => s.soundOn);

  const launchMode = status === 'done';
  const goLive = status === 'standby' || status === 'approach';

  // Lockout countdown (fire marshal)
  const [nowMs, setNowMs] = useState(Date.now());
  const locked = lockedUntil > nowMs;
  useEffect(() => {
    if (lockedUntil <= Date.now()) return;
    setNowMs(Date.now());
    const id = window.setInterval(() => {
      setNowMs(Date.now());
      if (Date.now() >= lockedUntil) window.clearInterval(id);
    }, 250);
    return () => window.clearInterval(id);
  }, [lockedUntil]);
  const lockSecs = Math.max(0, Math.ceil((lockedUntil - nowMs) / 1000));

  // Cover closes itself after a while if nobody presses anything
  const idleRef = useRef<number | undefined>(undefined);
  const bumpIdle = () => {
    window.clearTimeout(idleRef.current);
    idleRef.current = window.setTimeout(() => useShowStore.getState().setCoverOpen(false), 12000);
  };
  useEffect(() => () => window.clearTimeout(idleRef.current), []);

  const isArmed = launchMode ? coverOpen && !locked : goLive;

  const reducedMotion = typeof window !== 'undefined'
    ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
    : false;

  function makeSpecs(
    total: number,
    base: { delayMin: number; delayMax: number; xDist?: "uniform" | "sides" | "center" }
  ) {
    const items: LandingSpec[] = [];
    for (let i = 0; i < total; i++) {
      const rot = Math.random() * 60 - 30;
      const w = 8 + Math.floor(Math.random() * 6);
      const h = 3 + Math.floor(Math.random() * 3);
      const color = COLORS[Math.floor(Math.random() * COLORS.length)];
      let xPct = Math.random() * 100;
      if (base.xDist === "sides") xPct = Math.random() < 0.5 ? Math.random() * 18 : 82 + Math.random() * 18;
      if (base.xDist === "center") xPct = 35 + Math.random() * 30;
      const delayMs = base.delayMin + Math.random() * (base.delayMax - base.delayMin);
      items.push({ id: Date.now() + i + Math.random(), xPct, delayMs, w, h, color, rot });
    }
    return items;
  }

  function announce(msg: string) {
    useShowStore.getState().announce(msg, 'SFX', 'chatter');
  }

  function startRain() {
    const base = buildRainParticleOptions();
    const duration = 15000;
    const end = Date.now() + duration;

    // On-screen visual
    const interval = setInterval(() => {
      fire({
        particleCount: 15,
        ...base,
        origin: { x: Math.random(), y: -0.1 },
        // Ensure full viewport coverage on mobile
        ...(window.innerWidth < 768 && {
          ticks: 4000, // Extra long fall for mobile
          gravity: 0.5, // Slower gravity for longer fall
        }),
      });
      if (Date.now() > end) clearInterval(interval);
    }, 200);

    // Landing specs
    const specs = makeSpecs(120, { delayMin: 2000, delayMax: 16000 });
    scheduleLandings(specs);
    announce("Rain effect started");
  }

  const effects = [
    () => {
      fire({ 
        particleCount: 300, 
        spread: 160, 
        origin: { y: 0.6 },
        // Mobile-specific adjustments
        ...(window.innerWidth < 768 && {
          ticks: 3000,
          gravity: 0.6,
        }),
      });
      const specs = makeSpecs(80, { delayMin: 2000, delayMax: 4000 });
      scheduleLandings(specs);
      announce("Classic burst");
    },
    () => {
      startRain();
    },
    () => {
      const mobileAdjustments = window.innerWidth < 768 ? { ticks: 3000, gravity: 0.6 } : {};
      fire({ 
        particleCount: 200, 
        angle: 60, 
        spread: 55, 
        origin: { x: 0, y: 0.6 },
        ...mobileAdjustments,
      });
      fire({ 
        particleCount: 200, 
        angle: 120, 
        spread: 55, 
        origin: { x: 1, y: 0.6 },
        ...mobileAdjustments,
      });
      const specs = makeSpecs(100, { delayMin: 2000, delayMax: 4000, xDist: "sides" });
      scheduleLandings(specs);
      announce("Side cannons");
    },
    () => {
      const mobileAdjustments = window.innerWidth < 768 ? { ticks: 3000, gravity: 0.6 } : {};
      fire({
        particleCount: 400,
        spread: 160,
        colors: COLORS,
        origin: { y: 0.6 },
        ...mobileAdjustments,
      });
      const specs = makeSpecs(120, { delayMin: 2000, delayMax: 5000 });
      scheduleLandings(specs);
      announce("Color chaos");
    },
    () => {
      const mobileAdjustments = window.innerWidth < 768 ? { ticks: 3000, gravity: 0.6 } : {};
      fire({ 
        particleCount: 1000, 
        spread: 360, 
        startVelocity: 40, 
        origin: { y: 0.6 },
        ...mobileAdjustments,
      });
      const specs = makeSpecs(200, { delayMin: 2000, delayMax: 6000 });
      scheduleLandings(specs);
      announce("MEGA EXPLOSION");
    },
  ];

  const EFFECT_SIZE = [1, 0.7, 1.1, 1.3, 1.9];
  const fireEffect = (n: number) => {
    const i = n % effects.length;
    effects[i]();
    sfx.thump(useShowStore.getState().soundOn, EFFECT_SIZE[i]);
    // CO2 jets on the big ones (side cannons, MEGA EXPLOSION)
    if (i === 2 || i === 4) window.dispatchEvent(new CustomEvent('nebula:co2', { detail: i === 4 ? 1.5 : 1 }));
    setCount(n + 1);
  };

  // "GO Confetti!" from the show caller fires the first burst
  const countRef = useRef(count);
  countRef.current = count;
  useEffect(() => {
    const onGo = () => fireEffect(countRef.current);
    window.addEventListener('nebula:go-confetti', onGo);
    return () => window.removeEventListener('nebula:go-confetti', onGo);
  });

  const handleClick = () => {
    if (!launchMode) {
      if (goLive) callGo();
      return;
    }
    if (locked) return;
    if (!coverOpen) {
      setCoverOpen(true);
      bumpIdle();
      return;
    }
    fireEffect(count);
    registerLaunch();
    bumpIdle();
  };

  const label = launchMode ? (locked ? `LOCKED ${lockSecs}` : 'LAUNCH') : 'GO';

  return (
    <>
      {/* CSS animations for Big Red Button */}
      <style>{`
        @keyframes button-pulse-ring {
          0% { box-shadow: 0 0 0 0 rgba(255,70,70,0.25), 0 0 36px rgba(255,60,60,0.55), 0 0 96px rgba(255,60,60,0.25); }
          50% { box-shadow: 0 0 0 12px rgba(255,70,70,0.00), 0 0 60px rgba(255,60,60,0.38), 0 0 120px rgba(255,60,60,0.18); }
          100% { box-shadow: 0 0 0 0 rgba(255,70,70,0.25), 0 0 36px rgba(255,60,60,0.55), 0 0 96px rgba(255,60,60,0.25); }
        }
        .big-red-button:hover {
          transform: ${isArmed && !reducedMotion ? 'scale(1.03)' : 'scale(1)'} !important;
          transition: transform 0.2s ease !important;
        }
        .big-red-button:active {
          transform: ${isArmed && !reducedMotion ? 'scale(0.985)' : 'scale(1)'} !important;
          transition: transform 0.1s ease !important;
        }
      `}</style>
      
      {/* ───────────────── Confetti Button Slot (prevents layout shift) ───────────────── */}
      <div className="relative w-full flex items-center justify-center">
        {/* Reserve a consistent slot height from page load; no layout jump */}
        <div className="relative w-full flex items-center justify-center" style={{ overflow: 'visible', marginTop: 'clamp(18px, 2.4vw, 28px)' }}>
          <div
            className="relative"
            /* choose a single diameter; keep it square */
            style={{
              width: 'clamp(112px, 15vw, 180px)',
              height: 'clamp(112px, 15vw, 180px)',
              overflow: 'visible',          // <- important: allow aura to extend
            }}
          >
          {/* ===== HYPER-REAL LAUNCH BUTTON (NO LED) ===== */}
          <style>{`
            .launch-btn {
              position: relative;
              border-radius: 9999px;
              outline: none;
              width: 100%;
              height: 100%;
              user-select: none;
              -webkit-tap-highlight-color: transparent;
              transition: transform .18s ease, box-shadow .28s ease, filter .28s ease;
              will-change: transform, box-shadow, filter;
            }

            /* Outer anodized bezel */
            .launch-btn .bezel {
              position: absolute; inset: 0; border-radius: 9999px; pointer-events: none;
              background:
                radial-gradient(120% 120% at 30% 25%, rgba(255,255,255,.10) 0%, rgba(255,255,255,.02) 32%, rgba(255,255,255,0) 60%),
                conic-gradient(from 210deg at 50% 50%, #242424 0deg, #2e2e2e 60deg, #161616 140deg, #2a2a2a 220deg, #1a1a1a 320deg, #242424 360deg);
              box-shadow:
                inset 0 0 0 2px rgba(255,255,255,.06),
                inset 0 0 0 11px rgba(0,0,0,.35),
                inset 0 24px 40px rgba(0,0,0,.45);
            }

            /* Button cap (material) — dim vs armed via data-armed */
            .launch-btn .cap {
              position: absolute; inset: 6%; border-radius: 9999px; pointer-events: none;
              box-shadow: inset 0 10px 18px rgba(255,255,255,.10), inset 0 -18px 36px rgba(0,0,0,.45);
              transition: box-shadow .25s ease, filter .25s ease, background .25s ease, transform .18s ease;
            }
            .launch-btn[data-armed="false"] .cap {
              background:
                radial-gradient(80% 80% at 32% 28%, #7b2a2a 0%, #5a0f0f 42%, #3c0a0a 70%, #210606 100%);
              filter: saturate(.85) brightness(.9);
            }
            .launch-btn[data-armed="true"] .cap {
              background:
                radial-gradient(85% 85% at 34% 30%, #ff5d5d 0%, #e21818 45%, #b30f0f 72%, #710a0a 100%);
              filter: saturate(1.02) brightness(.98);
              box-shadow:
                inset 0 12px 22px rgba(255,255,255,.16),
                inset 0 -22px 44px rgba(0,0,0,.52),
                0 0 0 4px rgba(255,40,40,.20),
                0 10px 42px rgba(255,60,60,.28);
            }

            /* Inner ring AO for depth */
            .launch-btn .ringShadow {
              position: absolute; inset: 6%; border-radius: 9999px; pointer-events: none;
              box-shadow: inset 0 0 0 2px rgba(0,0,0,.40), inset 0 0 24px rgba(0,0,0,.52);
            }

            /* Static glass lens (no moving sweep) */
            .launch-btn .glass {
              position: absolute; inset: 6%; border-radius: 9999px; pointer-events: none;
              background:
                radial-gradient(120% 120% at 28% 22%, rgba(255,255,255,.22) 0%, rgba(255,255,255,.08) 22%, rgba(255,255,255,0) 48%),
                radial-gradient(100% 100% at 70% 78%, rgba(255,255,255,.06) 0%, rgba(255,255,255,0) 55%);
              mix-blend-mode: screen;
              filter: blur(.6px);
              opacity: .9;
            }

            /* helper: don't let the button container clip extended layers */
            .launch-btn { overflow: visible; }

            /* Armed rim light (tight ring hugging the cap) — perfectly centered */
            .launch-btn .rimLight {
              position: absolute;
              top: 50%; left: 50%;
              width: calc(100% + 8px);   /* ring thickness around the button */
              height: calc(100% + 8px);
              transform: translate(-50%, -50%);
              border-radius: 9999px;
              pointer-events: none;
              opacity: 0;
              transition: opacity .25s ease;
              background: radial-gradient(
                circle at 50% 50%,
                rgba(255,120,120,.22) 0%,
                rgba(255,120,120,.10) 38%,
                rgba(255,120,120,0) 55%
              );
              filter: blur(3px);
            }
            .launch-btn[data-armed="true"] .rimLight { opacity: .65; }

            /* Aura pulse (bigger, soft outer halo) — perfectly centered */
            .launch-btn .aura {
              position: absolute;
              top: 50%; left: 50%;
              /* how far the halo extends beyond the button; increase for bigger glow */
              --glow-pad: 80px;                      /* <- ADJUST pad here */
              width: calc(100% + var(--glow-pad));
              height: calc(100% + var(--glow-pad));
              transform: translate(-50%, -50%);
              border-radius: 9999px;
              pointer-events: none;
              background: radial-gradient(
                circle at 50% 50%,
                rgba(255,60,60,.18) 0%,
                rgba(255,60,60,.12) 32%,
                rgba(255,60,60,0) 60%
              );
              opacity: 0;                /* default off */
            }
            @keyframes launch-aura-breath {
              0%   { transform: translate(-50%, -50%) scale(1.00); opacity: .28; }
              50%  { transform: translate(-50%, -50%) scale(1.06); opacity: .18; }
              100% { transform: translate(-50%, -50%) scale(1.00); opacity: .28; }
            }
            .launch-btn[data-armed="true"] .aura {
              animation: launch-aura-breath 3.2s ease-in-out infinite;
            }

            /* Centered label (engraved/embossed hybrid) */
            .launch-btn .label {
              position:absolute; inset:0; display:flex; align-items:center; justify-content:center; pointer-events:none; text-align:center;
            }
            .launch-btn .label span {
              position:absolute; font-weight:900; text-transform:uppercase; white-space:nowrap;
              letter-spacing:.14em; font-size: clamp(10px, 2.2vw, 16px);
            }
            .launch-btn .label .shadow {
              transform: translateY(1px);
              filter: blur(.4px);
              color:#000; opacity:.28;
            }
            .launch-btn[data-armed="true"] .label .shadow { opacity:.34; }
            .launch-btn .label .face {
              -webkit-text-stroke: .7px rgba(0,0,0,.48);
              color: rgba(230,230,230,.78);
              text-shadow: 0 1px 0 rgba(255,255,255,.18), 0 1px 1px rgba(0,0,0,.35);
            }
            .launch-btn[data-armed="true"] .label .face {
              -webkit-text-stroke: .6px rgba(0,0,0,.34);
              color: rgba(255,255,255,.96);
              text-shadow: 0 1px 0 rgba(255,255,255,.32), 0 2px 2px rgba(0,0,0,.36), 0 -1px 0 rgba(255,255,255,.10);
            }

            /* GO mode: green cue light */
            .launch-btn[data-mode="go"][data-armed="true"] .cap {
              background: radial-gradient(85% 85% at 34% 30%, #7dffae 0%, #19c45a 45%, #0e8a3c 72%, #08481f 100%);
              box-shadow: inset 0 12px 22px rgba(255,255,255,.16), inset 0 -22px 44px rgba(0,0,0,.52), 0 0 0 4px rgba(40,255,120,.18), 0 10px 42px rgba(60,255,120,.28);
            }
            .launch-btn[data-mode="go"][data-armed="false"] .cap {
              background: radial-gradient(80% 80% at 32% 28%, #2f5a3d 0%, #173823 42%, #0d2216 70%, #061109 100%);
            }
            .launch-btn[data-mode="go"] .aura { background: radial-gradient(circle at 50% 50%, rgba(60,255,120,.18) 0%, rgba(60,255,120,.10) 32%, rgba(60,255,120,0) 60%); }
            .launch-btn[data-mode="go"] .label span { font-size: clamp(16px, 3.4vw, 26px); letter-spacing: .2em; }

            /* Safety cover */
            .cover-wrap {
              position: absolute; inset: -9%; perspective: 520px; pointer-events: none; z-index: 2;
              max-width: none; /* mobile CSS clamps * to 100%, which would shove the cover left */
            }
            .cover {
              position: absolute; inset: 0; border-radius: 24%;
              transform-origin: 50% 0%;
              transition: transform .45s cubic-bezier(.3,1.4,.5,1), opacity .3s ease;
              background: linear-gradient(160deg, rgba(255,120,120,.22) 0%, rgba(200,20,20,.16) 45%, rgba(120,0,0,.28) 100%);
              border: 1.5px solid rgba(255,170,170,.45);
              box-shadow: inset 0 2px 0 rgba(255,255,255,.25), inset 0 -10px 30px rgba(80,0,0,.35), 0 12px 30px rgba(0,0,0,.35);
              backdrop-filter: blur(1.5px);
              -webkit-backdrop-filter: blur(1.5px);
            }
            .cover-wrap[data-open="true"] .cover { transform: rotateX(118deg); opacity: .18; }
            .cover-wrap[data-locked="true"] .cover { transition-duration: .18s; }
            .cover-hinge {
              position: absolute; left: 12%; right: 12%; top: -7px; height: 10px; border-radius: 4px;
              background: repeating-linear-gradient(-45deg, #f5c400 0 7px, #111 7px 14px);
              box-shadow: 0 2px 4px rgba(0,0,0,.5);
            }
            .cover-sheen {
              position: absolute; inset: 0; border-radius: inherit;
              background: linear-gradient(115deg, rgba(255,255,255,.28) 0%, rgba(255,255,255,0) 35%, rgba(255,255,255,0) 70%, rgba(255,255,255,.12) 100%);
            }
            .cover-text {
              position: absolute; left: 0; right: 0; bottom: 9%; text-align: center;
              font: 800 clamp(7px, 1.2vw, 10px)/1 ui-monospace, SFMono-Regular, Menlo, monospace;
              letter-spacing: .2em; color: rgba(255,220,220,.85);
            }
            .cover-wrap[data-open="true"] .cover-text { opacity: 0; }

            /* Interactions (armed only) */
            .launch-btn[data-armed="true"]:hover { transform: translateY(-1px) scale(1.02); }
            .launch-btn[data-armed="true"]:active { transform: translateY(1px) scale(.985); }
            .launch-btn[data-armed="true"]:active .cap {
              box-shadow: inset 0 6px 14px rgba(255,255,255,.10), inset 0 -10px 22px rgba(0,0,0,.55);
              filter: brightness(.96);
            }
          `}</style>

          <button
            type="button"
            aria-label={launchMode ? (coverOpen ? 'Launch confetti' : 'Lift the safety cover') : 'GO — call the cue'}
            aria-disabled={!(launchMode ? !locked : goLive)}
            tabIndex={(launchMode ? !locked : goLive) ? 0 : -1}
            data-armed={isArmed ? 'true' : 'false'}
            data-mode={launchMode ? 'launch' : 'go'}
            className="launch-btn"
            onClick={handleClick}
            style={{ pointerEvents: (launchMode ? !locked : goLive) ? 'auto' : 'none' }}
          >
            {/* Layer order matters for realism */}
            <span className="bezel" aria-hidden />
            <span className="cap" aria-hidden />
            <span className="ringShadow" aria-hidden />
            <span className="glass" aria-hidden />
            <span className="rimLight" aria-hidden />
            {!reducedMotion && isArmed && <span className="aura" aria-hidden />}

            {/* Centered label */}
            <span className="label">
              <span className="shadow">{label}</span>
              <span className="face">{label}</span>
            </span>
          </button>

          {/* Safety cover (LAUNCH mode only). Hinged at the top; click to lift. */}
          {launchMode && (
            <div className="cover-wrap" aria-hidden data-open={coverOpen ? 'true' : 'false'} data-locked={locked ? 'true' : 'false'}>
              <div className="cover">
                <span className="cover-hinge" />
                <span className="cover-sheen" />
                <span className="cover-text">{locked ? 'LOCKED OUT' : 'LIFT COVER'}</span>
              </div>
            </div>
          )}

          {/* L/R audio meters either side of the button */}
          <AudioMeter />
          </div>
        </div>
      </div>
    </>
  );
};

export default ConfettiButton;
