import React, { useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useShowStore, CUES, T, type Tone } from '../../stores/showStore';

/**
 * StageManager — the headset log, plus the cue bar for calling the show.
 */

const TONE_CLASS: Record<Tone, string> = {
  cue: 'text-white/90 bg-white/5 border-white/10',
  good: 'text-green-300 bg-green-400/10 border-green-400/20',
  warn: 'text-amber-200 bg-amber-400/10 border-amber-300/20',
  alert: 'text-red-200 bg-red-500/20 border-red-400/40',
  chatter: 'text-sky-200/90 bg-sky-400/5 border-sky-300/10',
  info: 'text-white/70 bg-white/[0.03] border-white/10',
};

const WHO_CLASS: Record<string, string> = {
  SM: 'text-white/60',
  YOU: 'text-green-300',
  ASM: 'text-sky-300',
  FOH: 'text-red-300',
  LX: 'text-amber-300',
  AUDIO: 'text-fuchsia-300',
  VIDEO: 'text-cyan-300',
  CREW: 'text-lime-300',
  CATERING: 'text-orange-300',
  PROD: 'text-violet-300',
};

function CueBar() {
  const status = useShowStore((s) => s.status);
  const cueIndex = useShowStore((s) => s.cueIndex);
  const callGo = useShowStore((s) => s.callGo);
  const calling = status === 'standby' || status === 'approach';
  const dept = CUES[Math.min(cueIndex, CUES.length - 1)].dept;
  const firstCue = useShowStore((s) => s.cueIndex === 0 && s.results.length === 0);
  const travelMs = T.approach / (T.barMarkPct / 100);

  return (
    <AnimatePresence initial={false}>
      {calling && (
        <motion.div
          key="cuebar"
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: 'auto' }}
          exit={{ opacity: 0, height: 0 }}
          transition={{ duration: 0.3 }}
          className="overflow-hidden"
        >
          <button
            type="button"
            onClick={callGo}
            className="cuebar-btn w-full mt-2 text-left rounded-xl p-2 border border-white/10 bg-black/20"
            aria-label={`Call Go ${dept}`}
          >
            <div className="flex items-baseline justify-between font-mono text-[10px] sm:text-[11px] tracking-wider uppercase">
              <span className={status === 'approach' ? 'text-amber-200' : `text-amber-300 ${firstCue ? 'sm-flash' : ''}`}>
                ● Standby {dept}
              </span>
              <span className="text-white/40 hidden sm:inline">space = GO</span>
            </div>
            <div className="relative h-2.5 mt-1.5 rounded-full bg-white/10 overflow-hidden">
              {/* the mark */}
              <div
                className="absolute top-0 bottom-0 w-[3px] bg-green-400 shadow-[0_0_8px_rgba(74,222,128,0.9)]"
                style={{ left: `calc(${T.barMarkPct}% - 1.5px)` }}
              />
              {/* the sweep */}
              <div
                key={`${cueIndex}-${status}`}
                className="absolute top-0 bottom-0 left-0 rounded-full bg-gradient-to-r from-amber-500/30 to-amber-300"
                style={{
                  width: status === 'approach' ? undefined : '0%',
                  animation: status === 'approach' ? `cue-sweep ${travelMs}ms linear forwards` : undefined,
                }}
              />
            </div>
          </button>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export const StageManager: React.FC = () => {
  const log = useShowStore((s) => s.log);
  const status = useShowStore((s) => s.status);
  const startShow = useShowStore((s) => s.startShow);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [log]);

  const visible = log.slice(-12);

  return (
    <motion.aside
      className="w-[200px] sm:w-[250px] md:w-64 lg:w-80 xl:w-[400px] max-w-[calc(100vw-16px)] fixed right-2 z-50 font-system"
      style={{ top: '8px' }}
      role="complementary"
      aria-label="Stage Manager - Live Event Production Log"
      initial={{ opacity: 0, scale: 0.9, y: -20 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
    >
      <style>{`
        @keyframes cue-sweep { from { width: 0%; } to { width: 100%; } }
        @keyframes sm-flash-kf { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0.15; } }
        .sm-flash { animation: sm-flash-kf .5s steps(1, end) infinite; }
        @media (prefers-reduced-motion: reduce) { .sm-flash { animation: none; } }
        .cuebar-btn { min-height: 0 !important; padding: 8px !important; }
      `}</style>
      <div
        className="relative rounded-3xl shadow-2xl overflow-hidden"
        style={{
          background: 'linear-gradient(135deg, rgba(0,0,0,0.15) 0%, rgba(0,0,0,0.25) 100%), rgba(255,255,255,0.02)',
          backdropFilter: 'blur(20px) saturate(180%)',
          WebkitBackdropFilter: 'blur(20px) saturate(180%)',
          border: '1px solid rgba(255, 255, 255, 0.08)',
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.1), 0 0 0 1px rgba(255,255,255,0.05), 0 25px 50px -12px rgba(0,0,0,0.25)',
        }}
      >
        <div className="absolute inset-0 bg-gradient-to-br from-white/10 via-transparent to-white/5 rounded-3xl pointer-events-none" />

        <div className="relative z-10 p-3">
          <header className="flex items-center gap-2 mb-2 pb-2 border-b border-white/10">
            <div className="relative w-3 h-3 rounded-full flex-shrink-0" role="status" aria-label="Comms online">
              <div className="absolute inset-0 bg-green-400 rounded-full animate-pulse" />
              <div className="absolute inset-0 bg-green-400 rounded-full" style={{ boxShadow: '0 0 8px rgba(34,197,94,0.6), 0 0 16px rgba(34,197,94,0.3)' }} />
            </div>
            <h2 className="text-sm sm:text-base lg:text-lg font-light text-white tracking-wide m-0 flex-1 whitespace-nowrap">Stage Manager</h2>
            {status === 'done' && (
              <motion.button
                type="button"
                onClick={startShow}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                className="sm-replay text-[10px] sm:text-[11px] font-mono uppercase tracking-wider text-white/80 hover:text-white rounded-full border border-white/15 hover:border-white/40 bg-white/5 px-2.5 py-1"
                aria-label="Call the show again"
                title="Take the headset and call it again"
              >
                ↻<span className="hidden sm:inline"> Call it</span>
              </motion.button>
            )}
          </header>
          <style>{`.sm-replay { min-height: 0 !important; min-width: 0 !important; padding: 3px 10px !important; }`}</style>

          <div
            ref={scrollRef}
            className="h-28 sm:h-36 md:h-40 lg:h-44 xl:h-48 overflow-y-auto overflow-x-hidden flex flex-col gap-1 rounded-2xl p-2"
            role="log"
            aria-live="polite"
            aria-label="Production cues and stage management logs"
            style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.05)' }}
          >
            <AnimatePresence initial={false}>
              {visible.map((entry) => (
                <motion.div
                  key={entry.id}
                  className={`leading-tight px-1.5 py-1 rounded-lg break-words font-mono flex items-baseline gap-1.5 border ${TONE_CLASS[entry.tone]}`}
                  initial={{ opacity: 0, y: 8, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
                >
                  <span className="text-[7px] lg:text-[8px] tracking-tight flex-shrink-0 opacity-50 hidden sm:inline">{entry.time}</span>
                  {entry.who && (
                    <span className={`text-[9px] sm:text-[10px] font-bold flex-shrink-0 ${WHO_CLASS[entry.who] ?? 'text-white/60'}`}>{entry.who}</span>
                  )}
                  <span className="text-[9px] sm:text-[10px] lg:text-[11px] flex-1">{entry.text}</span>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>

          <CueBar />
        </div>
      </div>
    </motion.aside>
  );
};

export default StageManager;
