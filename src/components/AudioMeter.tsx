import React, { useEffect, useRef } from 'react';
import { useShowStore } from '../stores/showStore';
import { ENV_FPS, ENV_L, ENV_R } from '../config/drumRoll';

/**
 * AudioMeter — stereo LED meters either side of the big button, like a console strip.
 * Dark except while the drum roll is playing: they follow its real loudness (measured
 * from the file), slam into the red on the hit, then fall back to dark when it ends.
 * Visual only, so visitors see audio "go" even with sound muted.
 *
 * Drawn by writing to segment styles directly (no React re-render per frame).
 */

const SEGMENTS = 12;
const colorFor = (i: number) => (i >= 10 ? '#ef4444' : i >= 8 ? '#f59e0b' : '#22c55e');

// RMS → meter position (dB scale, hit = 0 dB = top)
const toLevel = (v: number) => {
  const db = 20 * Math.log10(Math.max(v, 1e-4));
  return Math.min(1, Math.max(0, (db + 30) / 30));
};

function Strip({ refs, side }: { refs: React.MutableRefObject<HTMLSpanElement[]>; side: 'L' | 'R' }) {
  return (
    <>
      <div className="meter-col">
        {Array.from({ length: SEGMENTS }, (_, k) => {
          const i = SEGMENTS - 1 - k; // top segment first
          return (
            <span
              key={i}
              ref={(el) => { if (el) refs.current[i] = el; }}
              className="meter-seg"
              style={{ background: colorFor(i) }}
            />
          );
        })}
      </div>
      <span className="meter-label">{side}</span>
    </>
  );
}

export const AudioMeter: React.FC = () => {
  const startedAt = useShowStore((s) => s.audioStartedAt);
  const left = useRef<HTMLSpanElement[]>([]);
  const right = useRef<HTMLSpanElement[]>([]);

  useEffect(() => {
    const paint = (segs: HTMLSpanElement[], level: number, peak: number) => {
      const lit = Math.round(level * SEGMENTS);
      const pk = Math.round(peak * SEGMENTS) - 1;
      for (let i = 0; i < SEGMENTS; i++) {
        const el = segs[i];
        if (!el) continue;
        const on = i < lit || (i === pk && pk >= 0);
        el.style.opacity = on ? '1' : '0.13';
        el.style.boxShadow = on ? `0 0 6px ${colorFor(i)}` : 'none';
      }
    };

    if (!startedAt) {
      paint(left.current, 0, 0);
      paint(right.current, 0, 0);
      return;
    }

    let raf = 0;
    let last = 0;
    const cur = { l: 0, r: 0, pl: 0, pr: 0 };
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (now - last < 33) return; // ~30fps is plenty for LEDs
      last = now;

      const frame = Math.floor(((now - startedAt) / 1000) * ENV_FPS);
      const playing = frame < ENV_L.length;
      const tl = playing ? toLevel(ENV_L[frame]) : 0;
      const tr = playing ? toLevel(ENV_R[frame]) : 0;
      // Fast attack, slower release, like real meters
      cur.l = tl > cur.l ? tl : cur.l * 0.82 + tl * 0.18;
      cur.r = tr > cur.r ? tr : cur.r * 0.82 + tr * 0.18;
      cur.pl = Math.max(cur.l, cur.pl - 0.012);
      cur.pr = Math.max(cur.r, cur.pr - 0.012);
      paint(left.current, cur.l, cur.pl);
      paint(right.current, cur.r, cur.pr);
      // Track over and meters have fallen to zero: go dark and stop
      if (!playing && cur.l < 0.02 && cur.r < 0.02) {
        paint(left.current, 0, 0);
        paint(right.current, 0, 0);
        cancelAnimationFrame(raf);
      }
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [startedAt]);

  return (
    <>
      <style>{`
        .meter-pair { position: absolute; inset: 0; pointer-events: none; }
        .meter-strip {
          position: absolute; top: 8%; height: 84%; width: clamp(9px, 1.1vw, 13px);
          display: flex; flex-direction: column; align-items: center; gap: 4px; max-width: none;
        }
        .meter-strip--l { right: calc(100% + 9% + clamp(10px, 1.6vw, 22px)); }
        .meter-strip--r { left: calc(100% + 9% + clamp(10px, 1.6vw, 22px)); }
        .meter-col {
          flex: 1; width: 100%; display: flex; flex-direction: column; gap: 2px; padding: 2px;
          border-radius: 4px; background: rgba(0,0,0,.45); border: 1px solid rgba(255,255,255,.08);
          box-shadow: inset 0 1px 3px rgba(0,0,0,.6);
        }
        .meter-seg { flex: 1; border-radius: 1.5px; opacity: .13; transition: opacity 40ms linear; }
        .meter-label { font: 600 8px/1 ui-monospace, SFMono-Regular, Menlo, monospace; color: rgba(255,255,255,.4); letter-spacing: .08em; }
      `}</style>
      <div className="meter-pair" aria-hidden>
        <div className="meter-strip meter-strip--l"><Strip refs={left} side="L" /></div>
        <div className="meter-strip meter-strip--r"><Strip refs={right} side="R" /></div>
      </div>
    </>
  );
};

export default AudioMeter;
