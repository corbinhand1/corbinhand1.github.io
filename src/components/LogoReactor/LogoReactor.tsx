/**
 * LogoReactor — No-Flash, No-Gloss, No-Jump (Layout-Safe)
 * -------------------------------------------------------
 * - STANDBY: logo dim/desaturated/soft blur (off).
 * - On "Go Video!": 520ms premium fade-in (no sweep/flash).
 * - LIVE: ultra-slow plasma + tagline that NEVER causes layout shifts.
 *   • Tagline is always mounted; we only animate opacity/translate.
 *   • A responsive min-height reserves space for two lines from the start.
 *   • All motion uses transform/opacity; plasma is absolute overlay.
 */

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import { useVideoStore } from '../../stores/videoStore';

type Phase = 'standby' | 'live';

const EASE_SNAPPY = [0.15, 0.9, 0.1, 1] as const;

type Particle = {
  id: number;
  baseAngle: number;
  speed: number;   // deg/s
  size: number;    // px
  hue: number;     // 200..245
  opacity: number; // 0.5..1.0
  rStart: number;
  rTarget: number;
  rStartTime: number;
  rDuration: number;
};

const clamp = (n: number, a: number, b: number) => Math.max(a, Math.min(b, n));
const rand  = (min: number, max: number) => min + Math.random() * (max - min);
const easeInOutCubic = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const easeOutBack    = (t: number, s = 0.35) => 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2);
const easedLerp      = (a: number, b: number, t: number, ease = easeInOutCubic) => a + (b - a) * ease(clamp(t, 0, 1));

export const LogoReactor: React.FC = () => {
  const { isVideoRolling } = useVideoStore();
  const [phase, setPhase] = useState<Phase>('standby');

  // Reduced motion
  const reduced = useMemo(
    () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches,
    []
  );

  // Transition to LIVE on video start
  useEffect(() => {
    if (isVideoRolling && phase === 'standby') setPhase('live');
  }, [isVideoRolling, phase]);

  // Subtle oscillator (live only) for tiny modulation (doesn't affect layout)
  const [osc, setOsc] = useState(0);
  useEffect(() => {
    if (reduced || phase !== 'live') return;
    const t0 = performance.now();
    const loop = (t: number) => {
      const dt = (t - t0) / 1000;
      setOsc((Math.sin(dt * Math.PI * 2 * 0.12) + 1) / 2); // very slow
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }, [phase, reduced]);

  // Particles (slow, independent, rare lane-changes)
  const PARTICLE_COUNT = 20;
  const nowMs = () => performance.now();
  const makeParticle = (i: number): Particle => {
    const baseR = rand(72, 118);
    return {
      id: i,
      baseAngle: (360 / PARTICLE_COUNT) * i + rand(-8, 8),
      speed: rand(1.0, 2.5),      // ultra slow
      size: rand(3, 6),
      hue: 205 + Math.random() * 40,
      opacity: 0.55 + Math.random() * 0.35,
      rStart: baseR,
      rTarget: baseR,
      rStartTime: nowMs(),
      rDuration: rand(6000, 10000),
    };
  };

  const particlesRef = useRef<Particle[]>([]);
  if (particlesRef.current.length === 0) {
    particlesRef.current = Array.from({ length: PARTICLE_COUNT }, (_, i) => makeParticle(i));
  }

  const currentRadius = (p: Particle) => {
    const t = clamp((nowMs() - p.rStartTime) / p.rDuration, 0, 1);
    const ease = t > 0.9 ? (tt: number) => easeOutBack(tt, 0.25) : easeInOutCubic;
    return easedLerp(p.rStart, p.rTarget, t, ease);
  };

  const retargetParticle = (p: Particle) => {
    p.rStart     = currentRadius(p);
    p.rTarget    = rand(68, 124);
    p.rStartTime = nowMs();
    p.rDuration  = rand(6400, 10400);
    p.speed      = clamp(p.speed * rand(0.94, 1.06), 1.0, 3.0);
  };

  const laneTimers = useRef<number[]>([]);
  useEffect(() => {
    if (reduced || phase !== 'live') return;
    particlesRef.current.forEach((p) => {
      const id = window.setInterval(() => retargetParticle(p), rand(12000, 18000));
      laneTimers.current.push(id);
    });
    return () => { laneTimers.current.forEach(clearInterval); laneTimers.current = []; };
  }, [phase, reduced]);

  // Timebase for orbits
  const [tSec, setTSec] = useState(0);
  useEffect(() => {
    if (reduced || phase !== 'live') return;
    const t0 = performance.now();
    const loop = () => {
      setTSec((performance.now() - t0) / 1000);
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }, [phase, reduced]);

  const speedFactor  = 1 + 0.05 * (osc - 0.5) * 2; // ≤ ±5%
  const radiusFactor = 1 + 0.005 * (osc - 0.5);    // ≤ ±0.5%

  // LOGO: No-gloss reveal (only transform/filters; no layout)
  const logoAnim =
    phase === 'standby'
      ? { filter: 'brightness(0.18) saturate(0.5) blur(2px)', opacity: 0.55, scale: 1 }
      : {
          filter: 'brightness(1) saturate(1) blur(0px)',
          opacity: 1,
          scale: [0.996, 1.004, 1],
          transition: { duration: 0.52, ease: EASE_SNAPPY },
        };

  // Canvas geometry
  const CANVAS = 340;
  const cx = CANVAS / 2;
  const cy = CANVAS / 2;

  // Tagline reserved space: big enough for 2 lines on mobile, 1 line on desktop
  // (Always mounted, animated only via opacity/translate.)
  const TAGLINE_MIN_H = 'clamp(36px, 5.2vh, 48px)'; // generous: prevents any push even when wrapping

  return (
    <>
      {/* CSS animations for plasma system */}
      <style>{`
        @keyframes aura-pulse {
          0%, 100% { opacity: 0.22; transform: scale(1); }
          50% { opacity: 0.34; transform: scale(1.04); }
        }
        @keyframes spin-slow {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
      
      {/* layout="position" smooths any outer positional adjustments from parent */}
      <div className="relative flex items-center justify-center">
      {/* Logo + Tagline wrapper — transform/opacity only; no layout shifts */}
      <div className="relative z-30 inline-flex flex-col items-center">
        <img
          src="/assets/Nebula Logo Color Text.png"
          alt="Nebula Creative Logo"
          className="h-32 sm:h-40 md:h-48 lg:h-64 w-auto"
          style={{ 
            willChange: 'transform', 
            transformOrigin: '50% 50%',
            filter: logoAnim.filter,
            opacity: logoAnim.opacity,
            transform: logoAnim.scale ? `scale(${logoAnim.scale})` : 'scale(1)',
            transition: logoAnim.transition ? `${logoAnim.transition.duration}s ${logoAnim.transition.ease}` : 'none'
          }}
        />

        {/* Spacer between logo and tagline (fixed from start) */}
        <div style={{ height: 'clamp(8px, 1.6vh, 16px)' }} />

        {/* Tagline container: ALWAYS PRESENT with min-height to reserve space */}
        <div
          className="w-full flex items-center justify-center pointer-events-none"
          style={{ minHeight: TAGLINE_MIN_H }}
        >
          <div
            // Always mounted: animate visibility only; no reflow
            aria-hidden={phase !== 'live'}
            className="text-[11px] sm:text-xs font-mono uppercase tracking-[0.18em] text-slate-100 text-center"
            style={{ 
              willChange: 'transform, opacity',
              opacity: phase === 'live' ? 1 : 0,
              transform: phase === 'live' ? 'translateY(0)' : 'translateY(6px)',
              transition: 'opacity 0.6s ease-out, transform 0.6s ease-out'
            }}
          >
            We make the show happen — on time, on budget, on brand.
          </div>
        </div>
      </div>

      {/* LIVE — Plasma System (absolute overlay; never affects layout) */}
      {phase === 'live' && (
        <div className="absolute inset-0 z-20 pointer-events-none flex items-center justify-center">
          {/* Soft aura */}
          <div
            className="absolute inset-0"
            style={{
              background: 'radial-gradient(circle, rgba(32,164,255,0.20) 0%, transparent 70%)',
              filter: 'blur(14px)',
              mixBlendMode: 'screen',
              animation: 'aura-pulse 24s ease-in-out infinite'
            }}
          />

          {/* Whole system slow spin: ~1 rotation / 240s */}
          <div
            className="relative"
            style={{ 
              width: CANVAS, 
              height: CANVAS,
              animation: 'spin-slow 240s linear infinite'
            }}
          >
            {/* Connectors */}
            <svg className="absolute inset-0" width={CANVAS} height={CANVAS} viewBox={`0 0 ${CANVAS} ${CANVAS}`}>
              {particlesRef.current.map((p, i) => {
                const q = particlesRef.current[(i + 3) % PARTICLE_COUNT];
                const angleA = (p.baseAngle + p.speed * speedFactor * tSec) * (Math.PI / 180);
                const angleB = (q.baseAngle + q.speed * speedFactor * tSec) * (Math.PI / 180);
                const rA = currentRadius(p) * radiusFactor;
                const rB = currentRadius(q) * radiusFactor;
                const ax = cx + rA * Math.cos(angleA);
                const ay = cy + rA * Math.sin(angleA);
                const bx = cx + rB * Math.cos(angleB);
                const by = cy + rB * Math.sin(angleB);
                return <line key={`line-${i}`} x1={ax} y1={ay} x2={bx} y2={by} stroke="rgba(32,164,255,0.14)" strokeWidth="1" />;
              })}
            </svg>

            {/* Particles */}
            {particlesRef.current.map((p) => {
              const angle = (p.baseAngle + p.speed * speedFactor * tSec) * (Math.PI / 180);
              const r = currentRadius(p) * radiusFactor;
              const x = cx + r * Math.cos(angle) - p.size / 2;
              const y = cy + r * Math.sin(angle) - p.size / 2;
              const color = `hsla(${p.hue}, 90%, 62%, ${p.opacity})`;
              const glow = Math.max(6, p.size * 2);
              return (
                <div
                  key={p.id}
                  className="absolute rounded-full"
                  style={{
                    left: x,
                    top: y,
                    width: p.size,
                    height: p.size,
                    background: color,
                    boxShadow: `0 0 ${glow}px ${color}`,
                  }}
                />
              );
            })}
          </div>
        </div>
      )}
    </div>
    </>
  );
};