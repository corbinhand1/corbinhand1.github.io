import React from 'react';
import { useShowStore, CUES, T } from '../stores/showStore';

/**
 * CueCallout — the warning right under the GO button, so visitors don't have to
 * look up at the Stage Manager panel to know a cue is coming.
 *   preshow  → "YOU'RE CALLING THE SHOW"
 *   standby  → "STANDBY LIGHTS" flashing (the warning)
 *   approach → steady, with a mini bar sweeping to the mark
 * The slot always reserves its height so nothing jumps.
 */
export const CueCallout: React.FC = () => {
  const status = useShowStore((s) => s.status);
  const cueIndex = useShowStore((s) => s.cueIndex);
  const results = useShowStore((s) => s.results.length);
  const dept = CUES[Math.min(cueIndex, CUES.length - 1)].name.toUpperCase();
  const travelMs = T.approach / (T.barMarkPct / 100);
  const firstCue = cueIndex === 0 && results === 0;

  let text = '';
  let cls = '';
  if (status === 'preshow') {
    text = "YOU'RE CALLING THE SHOW";
    cls = 'text-white/60';
  } else if (status === 'standby') {
    text = `STANDBY ${dept}`;
    cls = firstCue ? 'text-amber-300 cue-flash' : 'text-amber-300';
  } else if (status === 'approach') {
    text = firstCue ? `${dept} — HIT GO ON THE MARK` : `${dept}…`;
    cls = 'text-amber-200';
  }

  return (
    <div className="flex flex-col items-center justify-start" style={{ height: 44, marginTop: 14 }} aria-live="assertive">
      <style>{`
        @keyframes cue-flash-kf { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0.12; } }
        .cue-flash { animation: cue-flash-kf .5s steps(1, end) infinite; text-shadow: 0 0 12px rgba(252,211,77,.7); }
        @keyframes callout-sweep { from { width: 0%; } to { width: 100%; } }
        @media (prefers-reduced-motion: reduce) { .cue-flash { animation: none; } }
      `}</style>
      {text && (
        <div className={`font-mono text-[11px] sm:text-xs tracking-[0.22em] uppercase ${cls}`}>{text}</div>
      )}
      {(status === 'standby' || status === 'approach') && (
        <div className="relative mt-2 rounded-full bg-white/10 overflow-hidden" style={{ width: 'clamp(140px, 22vw, 220px)', height: 6 }} aria-hidden>
          <div
            className="absolute top-0 bottom-0 w-[3px] bg-green-400 shadow-[0_0_8px_rgba(74,222,128,0.9)]"
            style={{ left: `calc(${T.barMarkPct}% - 1.5px)` }}
          />
          <div
            key={`${cueIndex}-${status}`}
            className="absolute top-0 bottom-0 left-0 rounded-full bg-gradient-to-r from-amber-500/30 to-amber-300"
            style={{
              width: status === 'approach' ? undefined : '0%',
              animation: status === 'approach' ? `callout-sweep ${travelMs}ms linear forwards` : undefined,
            }}
          />
        </div>
      )}
    </div>
  );
};

export default CueCallout;
