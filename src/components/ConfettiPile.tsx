import React, { useEffect, useRef, useState } from 'react';
import { Sweeper, sweepTiming, SWEEP_MS } from './Stagehand';

/**
 * ConfettiPile — confetti that actually lands and piles up at the bottom.
 * Landings are queued and flushed once per frame so hundreds of pieces
 * don't re-render the whole page. Sweep with `sweepPile()`: the stagehand
 * walks across with a push broom and the pile moves with his broom.
 */

export interface LandingSpec {
  id: number;
  xPct: number;
  delayMs: number;
  w: number;
  h: number;
  color: string;
  rot: number;
}

interface Piece {
  id: number;
  xPct: number;
  yPx: number;
  w: number;
  h: number;
  color: string;
  rot: number;
}

const COLS = 60;
const MAX_PIECES = 1400;

let queue: LandingSpec[] = [];
let flushScheduled = false;
let listener: ((items: LandingSpec[]) => void) | null = null;
let sweepListener: (() => void) | null = null;
let pieceCount = 0;
let pendingTimers: number[] = [];

export function scheduleLandings(specs: LandingSpec[]) {
  specs.forEach((spec) => {
    const id = window.setTimeout(() => {
      queue.push(spec);
      if (!flushScheduled) {
        flushScheduled = true;
        requestAnimationFrame(() => {
          flushScheduled = false;
          const items = queue;
          queue = [];
          listener?.(items);
        });
      }
    }, spec.delayMs);
    pendingTimers.push(id);
  });
}

export const pileSize = () => pieceCount;

export function sweepPile() {
  // Anything still falling gets swept too
  pendingTimers.forEach(clearTimeout);
  pendingTimers = [];
  queue = [];
  sweepListener?.();
}

export const ConfettiPile: React.FC = () => {
  const [pieces, setPieces] = useState<Piece[]>([]);
  const [sweep, setSweep] = useState<ReturnType<typeof sweepTiming> | null>(null);
  const sweeping = !!sweep;
  const heights = useRef<number[]>(new Array(COLS).fill(0));
  const maxH = typeof window !== 'undefined' ? Math.round(Math.min(160, window.innerHeight * 0.18)) : 140;

  useEffect(() => {
    listener = (items) => {
      setPieces((prev) => {
        const next = prev.length + items.length > MAX_PIECES ? prev.slice(prev.length + items.length - MAX_PIECES) : prev.slice();
        for (const s of items) {
          const col = Math.min(COLS - 1, Math.max(0, Math.floor((s.xPct / 100) * COLS)));
          // spill into a lower neighbour so the pile slumps naturally
          let c = col;
          const l = Math.max(0, col - 1), r = Math.min(COLS - 1, col + 1);
          if (heights.current[l] < heights.current[c] - 6) c = l;
          if (heights.current[r] < heights.current[c] - 6) c = r;
          const y = heights.current[c] + Math.random() * 2;
          heights.current[c] = Math.min(maxH, heights.current[c] + s.h * 0.55);
          next.push({
            id: s.id,
            xPct: (c + Math.random()) * (100 / COLS),
            yPx: y,
            w: s.w,
            h: s.h,
            color: s.color,
            rot: s.rot * 2.5,
          });
        }
        pieceCount = next.length;
        return next;
      });
    };
    sweepListener = () => setSweep(sweepTiming());
    return () => {
      listener = null;
      sweepListener = null;
    };
  }, [maxH]);

  useEffect(() => {
    if (!sweeping) return;
    const id = window.setTimeout(() => {
      heights.current = new Array(COLS).fill(0);
      pieceCount = 0;
      setPieces([]);
      setSweep(null);
    }, SWEEP_MS);
    return () => clearTimeout(id);
  }, [sweeping]);

  const pileH = Math.max(0, ...heights.current) + 10;

  return (
    <>
      <style>{`
        @keyframes pile-push { from { transform: translateX(0); } to { transform: translateX(var(--end)); } }
      `}</style>
      <div
        className="fixed bottom-0 left-0 right-0 pointer-events-none"
        style={{ height: pileH, zIndex: 20 }}
        aria-hidden
      >
        <div
          className="relative w-full h-full"
          style={sweep ? {
            ['--end' as any]: `${sweep.pileEnd}px`,
            animation: `pile-push ${sweep.pileDur}ms linear ${sweep.pileDelay}ms both`,
          } : undefined}
        >
          {pieces.map((p) => (
            <div
              key={p.id}
              style={{
                position: 'absolute',
                left: `${p.xPct}%`,
                bottom: p.yPx,
                width: p.w,
                height: p.h,
                background: p.color,
                borderRadius: 1,
                transform: `rotate(${p.rot}deg)`,
                boxShadow: '0 1px 1px rgba(0,0,0,.25)',
              }}
            />
          ))}
        </div>
      </div>
      {sweep && <Sweeper timing={sweep} />}
    </>
  );
};

export default ConfettiPile;
