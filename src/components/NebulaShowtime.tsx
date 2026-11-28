import React, { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";

import { StageManager } from './StageManager';
import { ConfettiButton } from './ConfettiButton';
import { StickyNote } from './StickyNote';
import { AboutEthosOverlay } from './AboutEthosOverlay';
import { LogoReactor } from './LogoReactor';
import { ConfettiPile, scheduleLandings, sweepPile, pileSize } from './ConfettiPile';
import { ShowFX, triggerHaze } from './ShowFX';
import { CueCallout } from './CueCallout';
import { KabukiDrop, CO2Jets, Ballyhoo } from './StageFX';
import { Stagehand, SWEEP_MS } from './Stagehand';
import { AudioMeter } from './AudioMeter';

import { useShowStore } from '../stores/showStore';
import { sfx } from '../lib/sfx';
import { haptic } from '../lib/haptics';
import { BRAND } from '../config/design';
import { CLEANUP_NOTES } from '../config/chatter';

/* -------------------- LIGHTS/FX -------------------- */
function StageBeams() {
  const level = useShowStore((s) => s.lightLevel);
  const haze = useShowStore((s) => s.haze);
  // The beams are upstage of the kabuki: they're only seen once it has dropped
  const kabukiOut = useShowStore((s) => s.kabukiOut);
  const beams = [
    { delay: 0.0, rotate: -16, left: "-18vw", top: "-8vh", w: "90vw", h: "90vh" },
    { delay: 0.06, rotate: -5, left: "-8vw", top: "-6vh", w: "90vw", h: "90vh" },
    { delay: 0.1, rotate: 7, left: "12vw", top: "-10vh", w: "90vw", h: "90vh" },
  ];
  const on = level > 0 && kabukiOut;
  // Haze makes the beams read much stronger, like the real thing
  const opacity = on ? Math.min(1, 0.1 + level * 0.6 + (haze ? 0.3 : 0)) : 0;
  return (
    <motion.div
      style={{ position: 'fixed', inset: 0, pointerEvents: 'none' }}
      initial={{ opacity: 0 }}
      animate={{ opacity }}
      transition={{ duration: on ? 2.5 : 0.6, ease: "easeOut" }}
    >
      {beams.map((b, i) => (
        <motion.div
          key={i}
          initial={{ x: -200, y: -240, opacity: 0 }}
          animate={on ? { x: 0, y: 0, opacity: 1 } : { x: -200, y: -240, opacity: 0 }}
          transition={{ duration: 2.5, ease: "easeOut", delay: b.delay }}
          style={{
            position: "absolute",
            left: b.left,
            top: b.top,
            width: b.w,
            height: b.h,
            transform: `rotate(${b.rotate}deg)`,
            filter: "blur(12px)",
            mixBlendMode: "screen" as any,
          }}
        >
          <div
            style={{
              width: "100%",
              height: "100%",
              background:
                "radial-gradient(ellipse at 50% 35%, rgba(255,193,7,0.9) 0%, rgba(255,152,0,0.6) 22%, rgba(255,193,7,0.15) 50%, rgba(255,193,7,0) 70%)",
            }}
          />
        </motion.div>
      ))}
    </motion.div>
  );
}

function BlackLayer() {
  return (
    <div
      className="fixed inset-0 -z-10"
      style={{ background: `radial-gradient(1200px 800px at 50% -10%, ${BRAND.glow}, transparent 60%)` }}
    />
  );
}

function Noise() {
  return (
    <div
      className="pointer-events-none fixed inset-0 -z-10 opacity-[0.07]"
      style={{
        backgroundImage:
          "url('data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"60\" height=\"60\"><filter id=\"n\"><feTurbulence baseFrequency=\"0.8\" numOctaves=\"2\"/></filter><rect width=\"100%\" height=\"100%\" filter=\"url(%23n)\" opacity=\"0.4\"/></svg>')",
        backgroundSize: "auto",
      }}
    />
  );
}

/* -------------------- CONTACT BUTTON -------------------- */
function ContactButton({ show }: { show: boolean }) {
  return (
    <div style={{ marginTop: '1.5rem', minHeight: '48px' }}>
      <motion.div
        initial={{ opacity: 0, scale: 0.9, y: 20 }}
        animate={{ opacity: show ? 1 : 0, scale: show ? 1 : 0.9, y: show ? 0 : 20 }}
        transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
        style={{ pointerEvents: show ? 'auto' : 'none', visibility: show ? 'visible' : 'hidden' }}
      >
        <motion.a
          href="mailto:corbin@nebulacreative.org?subject=Let's%20call%20a%20show"
          className="inline-block px-6 py-3 rounded-2xl text-white font-light text-sm tracking-wide no-underline min-h-[48px] cursor-pointer relative overflow-hidden"
          style={{
            background: 'linear-gradient(135deg, rgba(0,0,0,0.15) 0%, rgba(0,0,0,0.25) 100%), rgba(255,255,255,0.02)',
            backdropFilter: 'blur(20px) saturate(180%)',
            border: '1px solid rgba(255, 255, 255, 0.08)',
            boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.1), 0 0 0 1px rgba(255,255,255,0.05), 0 25px 50px -12px rgba(0,0,0,0.25)',
          }}
          whileHover={{ scale: 1.05, y: -2 }}
          whileTap={{ scale: 0.98 }}
          aria-label="Contact Nebula Creative for stage management and show calling services"
        >
          <div className="absolute inset-0 bg-gradient-to-br from-white/10 via-transparent to-white/5 rounded-2xl" />
          <div className="relative z-10 flex items-center justify-center h-full">Contact Us</div>
        </motion.a>
      </motion.div>
    </div>
  );
}

/* -------------------- SOUND TOGGLE -------------------- */
function SoundToggle() {
  const soundOn = useShowStore((s) => s.soundOn);
  const toggleSound = useShowStore((s) => s.toggleSound);
  return (
    <motion.button
      type="button"
      initial={{ opacity: 0, scale: 0.8 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay: 1.4, duration: 0.8, ease: [0.4, 0, 0.2, 1] }}
      onClick={() => { haptic('tap'); toggleSound(); }}
      className="fixed bottom-6 left-[7.5rem] md:bottom-8 md:left-24 z-[9998] group"
      aria-label={soundOn ? 'Mute comms audio' : 'Turn on comms audio'}
      aria-pressed={soundOn}
      title={soundOn ? 'Comms audio on' : 'Comms audio off'}
    >
      <div className={`relative w-14 h-14 rounded-full bg-black/20 backdrop-blur-xl border transition-all duration-500 flex items-center justify-center ${soundOn ? 'border-green-400/50' : 'border-white/10 group-hover:border-white/30'}`}>
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" className={soundOn ? 'text-green-300' : 'text-white/70 group-hover:text-white'}>
          {/* headset */}
          <path d="M4 14v-2a8 8 0 0 1 16 0v2" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
          <rect x="3" y="13" width="4" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
          <rect x="17" y="13" width="4" height="6" rx="1.5" stroke="currentColor" strokeWidth="1.3" />
          <path d="M19 19c0 1.5-2 2.5-5 2.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />
          {!soundOn && <path d="M3 3l18 18" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" />}
        </svg>
      </div>
    </motion.button>
  );
}

/* -------------------- MAIN COMPONENT -------------------- */
const NebulaShowtime: React.FC = () => {
  const status = useShowStore((s) => s.status);
  const stageShift = useShowStore((s) => s.stageShift);
  const startShow = useShowStore((s) => s.startShow);
  const [everDone, setEverDone] = useState(false);
  const [noteIdx, setNoteIdx] = useState(() => Math.floor(Math.random() * CLEANUP_NOTES.length));
  const [hasPile, setHasPile] = useState(false);
  const sweepingRef = useRef(false);

  // Roll the show once on mount (guarded against StrictMode double-mount)
  useEffect(() => {
    if (useShowStore.getState().log.length === 0) startShow();
  }, [startShow]);

  useEffect(() => {
    if (status === 'done') setEverDone(true);
  }, [status]);

  // Poll the pile size cheaply so the note knows whether there is anything to sweep
  useEffect(() => {
    const id = window.setInterval(() => setHasPile(pileSize() > 0), 500);
    return () => clearInterval(id);
  }, []);

  const onNote = () => {
    haptic('tap');
    if (sweepingRef.current) return;
    const st = useShowStore.getState();
    if (pileSize() > 0) {
      sweepingRef.current = true;
      sweepPile();
      // a swish per pass of the broom while he crosses
      for (let k = 0; k < 3; k++) window.setTimeout(() => sfx.sweep(useShowStore.getState().soundOn), k * 1050);
      st.announce(['Sweeping. Again.', 'On it. Bring a bigger broom.', 'Confetti struck.', 'Found some in my shoe.'][Math.floor(Math.random() * 4)], 'CREW', 'chatter');
      window.setTimeout(() => {
        sweepingRef.current = false;
        setHasPile(false);
        setNoteIdx((i) => (i + 1) % CLEANUP_NOTES.length);
      }, SWEEP_MS + 50);
    } else {
      st.announce(everDone ? 'Nothing to sweep. Yet.' : 'Hold for cleanup until after the show.', 'SM', 'info');
      setNoteIdx((i) => (i + 1) % CLEANUP_NOTES.length);
    }
  };

  // Tap the logo 5 times quickly for haze (the mobile version of typing "places")
  const taps = useRef<number[]>([]);
  const onLogoTap = () => {
    const t = Date.now();
    taps.current = [...taps.current.filter((x) => t - x < 1500), t];
    if (taps.current.length >= 5) {
      taps.current = [];
      triggerHaze();
    }
  };

  return (
    <>
      <BlackLayer />
      <Noise />
      <StageBeams />
      <Ballyhoo />

      <div className="min-h-screen flex flex-col items-center justify-center px-4 sm:px-6 md:pr-[18.5rem] lg:pr-[21rem] xl:pr-6 relative nebula-stage">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          style={{ textAlign: 'center', maxWidth: '56rem', width: '100%', position: 'relative', zIndex: 10 }}
        >
          {/* The "stage": everything here moves when the stagehand pushes it */}
          <div
            className="relative mx-auto"
            style={{ width: 'fit-content', maxWidth: '100%', transform: `translateX(${stageShift}px)`, transition: 'transform 1.6s cubic-bezier(.55,.05,.35,1)' }}
          >
          <header className="mb-4 sm:mb-6 relative z-20 text-center">
            <div onClick={onLogoTap} className="relative inline-block">
              <LogoReactor />
              <KabukiDrop />
            </div>
          </header>
          <main>
            <h1 className="sr-only">Nebula Creative - Professional Stage Management, Show Calling, Production Management, and Tour Management Services</h1>
          </main>

          <div className="relative z-20">
            <ConfettiButton scheduleLandings={scheduleLandings} />
            {status !== 'done' && <CueCallout />}
            <ContactButton show={everDone} />
          </div>
          <Stagehand />
          </div>
        </motion.div>

        <ConfettiPile />

        <StickyNote
          text={CLEANUP_NOTES[noteIdx]}
          noteKey={noteIdx}
          onActivate={onNote}
          hint={hasPile ? 'Sweep it up' : 'Next note'}
        />
      </div>

      <StageManager />
      <AudioMeter />
      <CO2Jets />
      <ShowFX />
      <SoundToggle />
      <AboutEthosOverlay />
    </>
  );
};

export default NebulaShowtime;
