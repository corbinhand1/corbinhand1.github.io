import React, { useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";

// Import extracted components
import { StageManager } from './StageManager';
import { ConfettiButton } from './ConfettiButton';
import { StickyNote } from './StickyNote';

// Import design system
import { BRAND } from '../config/design';
import { CUE_LINES } from '../config/timing';

/* -------------------- UTILS -------------------- */
function useClock(play: boolean) {
  const [ms, setMs] = useState(0);
  useEffect(() => {
    if (!play) return;
    let raf = 0;
    const start = performance.now();
    const loop = (t: number) => {
      setMs(t - start);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [play]);
  return ms;
}

const TypeLine: React.FC<{ show: boolean; children: React.ReactNode }> = ({
  show,
  children,
}) => {
  const [val, setVal] = useState("");
  useEffect(() => {
    if (!show) return setVal("");
    const str = String(children);
    let i = 0;
    const id = setInterval(() => {
      i++;
      setVal(str.slice(0, i));
      if (i >= str.length) clearInterval(id);
    }, 10);
    return () => clearInterval(id);
  }, [show, children]);
  return (
    <div className="font-mono text-slate-300/90 text-[14px] sm:text-[15px] md:text-[16px] tracking-tight">
      {val}
    </div>
  );
};

/* -------------------- LIGHTS/FX -------------------- */
function StageBeams({ level }: { level: number }) {
  const beams = [
    { delay: 0.0, rotate: -16, left: "-18vw", top: "-8vh", w: "90vw", h: "90vh" },
    { delay: 0.06, rotate: -5, left: "-8vw", top: "-6vh", w: "90vw", h: "90vh" },
    { delay: 0.1, rotate: 7, left: "12vw", top: "-10vh", w: "90vw", h: "90vh" },
  ];
  const opacity = 0.1 + level * 0.6;
  return (
    <motion.div
      style={{ position: 'fixed', inset: 0, pointerEvents: 'none' }}
      initial={{ opacity: 0 }}
      animate={{ opacity }}
      transition={{ duration: 2.5, ease: "easeOut" }}
    >
      {beams.map((b, i) => (
        <motion.div
          key={i}
          initial={{ x: -200, y: -240, opacity: 0 }}
          animate={{ x: 0, y: 0, opacity: 1 }}
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
      style={{
        background: `radial-gradient(1200px 800px at 50% -10%, ${BRAND.glow}, transparent 60%)`,
      }}
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

/* -------------------- STICKIES -------------------- */
const HAND_FONT_STACK =
  "Patrick Hand, Bradley Hand, Brush Script MT, Comic Sans MS, Marker Felt, Kalam, Indie Flower, cursive";

// Funny production mishaps that rotate
const PRODUCTION_MISHAPS = [
  "WiFi password is 'password123'",
  "Sound guy thought doors were 9am",
  "Video crew brought VHS tapes",
  "Catering showed up yesterday",
  "Lighting board speaks French",
  "Stage manager lost the script",
  "Props are still in the truck",
  "Client wants changes at 5pm",
  "Backup generator is out of gas",
  "Security guard locked the stage",
  "Coffee machine is broken",
  "Elevator is stuck on floor 3",
  "Fire marshal is running late",
  "Band wants vegan catering",
  "Sound check at 11pm tonight",
  "Parking lot is full",
  "Load-in starts at 2am",
  "Client forgot the check",
  "Rain date is tomorrow",
  "Power outlet is 50 feet away"
];

const CLEANUP_NOTES = [
  "Who's sweeping up the confetti?",
  "Cleanup crew went home",
  "Confetti stuck in everything",
  "Vacuum cleaner is broken",
  "Janitorial starts at midnight",
  "Confetti in the HVAC system",
  "Cleanup budget: $0",
  "Confetti cleanup: tomorrow",
  "Who ordered 1000lbs of confetti?",
  "Confetti in the sound booth",
  "Cleanup crew called in sick",
  "Confetti stuck to the ceiling",
  "Maintenance is on vacation",
  "Confetti in the green room",
  "Cleanup starts when we're done"
];

/* -------------------- CONFETTI (REAL LANDING) -------------------- */
type LandingSpec = {
  id: number;
  xPct: number;
  delayMs: number;
  w: number;
  h: number;
  color: string;
  rot: number;
};
type PilePiece = {
  id: number;
  xPct: number;
  yPx: number;
  w: number;
  h: number;
  color: string;
  rot: number;
};

function ConfettiPile({ pieces, heightPx }: { pieces: PilePiece[]; heightPx: number }) {
  return (
    <div
      className="absolute bottom-0 left-0 right-0 z-20 overflow-hidden pointer-events-none"
      style={{ height: `${heightPx}px` }}
    >
      <div className="relative w-full h-full">
        {pieces.map((p) => (
          <div
            key={p.id}
            style={{
              position: "absolute",
              left: `${p.xPct}%`,
              bottom: `${Math.min(p.yPx, heightPx)}px`,
              width: p.w,
              height: p.h,
              background: p.color,
              borderRadius: 1,
              transform: `rotate(${p.rot}deg)`,
            }}
          />
        ))}
      </div>
    </div>
  );
}

/* -------------------- STAGE MANAGER -------------------- */
/* -------------------- MICROPHONE CHECK BUBBLE -------------------- */
function MicrophoneCheck({ show }: { show: boolean }) {
  return (
    <AnimatePresence>
      {show && (
        <motion.div
          initial={{ opacity: 0, scale: 0.8, x: -20 }}
          animate={{ opacity: 1, scale: 1, x: 0 }}
          exit={{ opacity: 0, scale: 0.8, x: -20 }}
          transition={{ duration: 0.4, ease: "easeOut" }}
          style={{ 
            position: 'fixed',
            top: '4rem',
            left: '1rem',
            zIndex: 50
          }}
        >
          <div className="relative">
            {/* Speech bubble */}
            <div className="bg-white text-gray-800 px-3 sm:px-4 py-2 sm:py-3 rounded-2xl shadow-lg border-2 border-gray-300 max-w-[280px] sm:max-w-xs">
              <div className="font-medium text-xs sm:text-sm">Microphone Check 1212</div>
        </div>
            {/* Speech bubble tail pointing down-left */}
            <div 
              className="absolute -bottom-2 left-4 w-0 h-0"
              style={{
                borderLeft: "8px solid transparent",
                borderRight: "8px solid transparent", 
                borderTop: "8px solid white"
              }}
            />
            {/* Speech bubble tail shadow */}
            <div 
              className="absolute -bottom-1 left-3 w-0 h-0"
              style={{
                borderLeft: "9px solid transparent",
                borderRight: "9px solid transparent", 
                borderTop: "9px solid #d1d5db"
              }}
            />
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* -------------------- ROLLING BUBBLE -------------------- */
function RollingBubble({ show }: { show: boolean }) {
  return (
    <AnimatePresence>
      {show && (
        <motion.div
          initial={{ opacity: 0, scale: 0.8, x: -20 }}
          animate={{ opacity: 1, scale: 1, x: 0 }}
          exit={{ opacity: 0, scale: 0.8, x: -20 }}
          transition={{ duration: 0.4, ease: "easeOut" }}
          style={{ 
            position: 'fixed',
            top: '1rem',
            left: '1rem',
            zIndex: 50
          }}
        >
          <div className="relative">
            {/* Speech bubble */}
            <div className="bg-red-500 text-white px-3 sm:px-4 py-2 sm:py-3 rounded-2xl shadow-lg border-2 border-red-600 max-w-[280px] sm:max-w-xs">
              <div className="font-medium text-xs sm:text-sm flex items-center gap-2">
                <div className="w-2 h-2 bg-white rounded-full animate-pulse"></div>
                Video Rolling
              </div>
            </div>
            {/* Speech bubble tail pointing down-left */}
            <div 
              className="absolute -bottom-2 left-4 w-0 h-0"
              style={{
                borderLeft: "8px solid transparent",
                borderRight: "8px solid transparent", 
                borderTop: "8px solid #ef4444"
              }}
            />
            {/* Speech bubble tail shadow */}
            <div 
              className="absolute -bottom-1 left-3 w-0 h-0"
              style={{
                borderLeft: "9px solid transparent",
                borderRight: "9px solid transparent", 
                borderTop: "9px solid #dc2626"
              }}
            />
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* -------------------- CONTACT BUTTON -------------------- */
function ContactButton({ show }: { show: boolean }) {
  return (
    <AnimatePresence>
      {show && (
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 20 }}
          transition={{ duration: 0.5, ease: "easeOut" }}
          style={{ marginTop: '1.5rem' }}
        >
          <a
            href="mailto:corbin@nebulacreative.org"
            style={{
              display: 'inline-block',
              padding: '12px 24px',
              borderRadius: '8px',
              fontSize: '14px',
              fontWeight: '500',
              background: 'linear-gradient(to right, #059669, #0d9488)',
              color: 'white',
              textDecoration: 'none',
              minHeight: '48px',
              fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif',
              letterSpacing: '-0.01em',
              boxShadow: '0 10px 15px -3px rgba(0, 0, 0, 0.1)',
              transition: 'all 0.2s',
              border: 'none',
              cursor: 'pointer'
            }}
            aria-label="Contact Nebula Creative for stage management and show calling services"
          >
            Contact Us
          </a>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/* -------------------- MAIN COMPONENT -------------------- */
const NebulaShowtime: React.FC = () => {
  const [lightLevel, setLightLevel] = useState(0);
  const [pilePieces, setPilePieces] = useState<PilePiece[]>([]);
  const [pileHeight, setPileHeight] = useState(0);
  const [showMicCheck, setShowMicCheck] = useState(false);
  const [showRolling, setShowRolling] = useState(false);

  // Force viewport settings on mobile
  useEffect(() => {
    const viewport = document.querySelector('meta[name=viewport]');
    if (viewport) {
      viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=5.0');
    }
  }, []);
  const [showContactButton, setShowContactButton] = useState(false);
  const [isMobile, setIsMobile] = useState(true); // Default to mobile for safety
  const clockMs = useClock(true);
  
  // Set random sticky note text once on component mount - MOBILE ONLY
  const [randomCleanup] = useState(() => CLEANUP_NOTES[Math.floor(Math.random() * CLEANUP_NOTES.length)]);

  // MOBILE ONLY - No device detection needed
  useEffect(() => {
    setIsMobile(true); // Always mobile
  }, []);

  const handleConfettiPressed = () => {
    setShowContactButton(true);
  };

  // Turn on lights when "Go Lights!" cue is reached
  useEffect(() => {
    const goLightsCue = CUE_LINES.find(c => c.text === "Go Lights!");
    // Add 1.5 seconds delay to account for typing animation + user reading time
    const lightsTriggerTime = goLightsCue.t + 1500;
    if (goLightsCue && clockMs >= lightsTriggerTime && clockMs < lightsTriggerTime + 1000 && lightLevel === 0) {
      // Start the slow fade-in (2.5 seconds)
      setLightLevel(1);
      // Dim lights after the fade-in completes
      const timer = setTimeout(() => setLightLevel(0.4), 2500);
      return () => clearTimeout(timer);
    }
  }, [clockMs, lightLevel]);

  // Show microphone check when "Go Audio!" cue is reached
  useEffect(() => {
    const goAudioCue = CUE_LINES.find(c => c.text === "Go Audio!");
    // Add 1.5 seconds delay to account for typing animation + user reading time
    const micTriggerTime = goAudioCue.t + 1500;
    if (goAudioCue && clockMs >= micTriggerTime && clockMs < micTriggerTime + 1000 && !showMicCheck) {
      setShowMicCheck(true);
    }
  }, [clockMs, showMicCheck]);

  // Hide microphone check after 2.5 seconds
  useEffect(() => {
    if (showMicCheck) {
      const timer = setTimeout(() => {
        setShowMicCheck(false);
      }, 2500);
      return () => clearTimeout(timer);
    }
  }, [showMicCheck]);

  // Show rolling bubble when "Go Video!" cue is reached
  useEffect(() => {
    const goVideoCue = CUE_LINES.find(c => c.text === "Go Video!");
    // Add 1.5 seconds delay to account for typing animation + user reading time
    const rollingTriggerTime = goVideoCue.t + 1500;
    if (goVideoCue && clockMs >= rollingTriggerTime && clockMs < rollingTriggerTime + 1000 && !showRolling) {
      setShowRolling(true);
    }
  }, [clockMs, showRolling]);

  // Hide rolling bubble after 2.5 seconds
  useEffect(() => {
    if (showRolling) {
      const timer = setTimeout(() => {
        setShowRolling(false);
      }, 2500);
      return () => clearTimeout(timer);
    }
  }, [showRolling]);

  const scheduleLandings = (specs: LandingSpec[]) => {
    specs.forEach((spec) => {
    setTimeout(() => {
        setPilePieces((prev) => [
          ...prev,
          {
            id: spec.id,
            xPct: spec.xPct,
            yPx: 0,
            w: spec.w,
            h: spec.h,
            color: spec.color,
            rot: spec.rot,
          },
        ]);
      }, spec.delayMs);
    });
  };

  return (
    <>
      <BlackLayer />
      <Noise />
      <StageBeams level={lightLevel} />
      
      <div className="min-h-screen flex flex-col items-center justify-center px-4 sm:px-6 relative">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8 }}
          style={{ 
            textAlign: 'center',
            maxWidth: '56rem',
            width: '100%',
            position: 'relative',
            zIndex: 10
          }}
        >
          <header className="mb-4 sm:mb-6 relative z-20 text-center">
            <img 
              src="/assets/Nebula Logo Color Text.png" 
              alt="Nebula Creative Logo - Professional Stage Management, Show Calling, Production Management, and Tour Management Services for Live Events, Concerts, Festivals, and Corporate Shows Worldwide" 
              className="h-32 sm:h-40 md:h-48 lg:h-64 w-auto relative z-30 logo-mobile"
            />
        </header>
          <main>
            <h1 className="sr-only">Nebula Creative - Professional Stage Management, Show Calling, Production Management, and Tour Management Services</h1>
            <p 
              className="text-base sm:text-lg md:text-xl text-slate-300 mb-6 sm:mb-8 md:mb-12 max-w-2xl mx-auto px-2 relative z-20 leading-relaxed"
              style={{
                fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif',
                fontWeight: '400',
                letterSpacing: '-0.01em'
              }}
              role="banner"
              aria-label="Company tagline: We make the show happen — on time, on budget, on brand"
            >
              We make the show happen — on time, on budget, on brand.
            </p>
          </main>
          
          <div className="relative z-20">
            <ConfettiButton scheduleLandings={scheduleLandings} clockMs={clockMs} onConfettiPressed={handleConfettiPressed} />
            <ContactButton show={showContactButton} />
          </div>
        </motion.div>

        <ConfettiPile pieces={pilePieces} heightPx={pileHeight} />
        
        {/* MOBILE ONLY - Single sticky note */}
        <StickyNote 
          text={randomCleanup} 
          pos={{ right: 0, bottom: 0, rot: 8 }} 
          className="sticky-note-mobile"
        />
      </div>

      <StageManager clockMs={clockMs} announce={() => {}} isMobile={isMobile} />
      <MicrophoneCheck show={showMicCheck} />
      <RollingBubble show={showRolling} />
    </>
  );
};

export default NebulaShowtime;