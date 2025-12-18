import React, { useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";

// Import extracted components
import { StageManager } from './StageManager';
import { ConfettiButton } from './ConfettiButton';
import { StickyNote } from './StickyNote';
import { AboutEthosOverlay } from './AboutEthosOverlay';
import { LogoReactor } from './LogoReactor';

// Import state management
import { useVideoStore } from '../stores/videoStore';

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


/* -------------------- CONTACT BUTTON -------------------- */
function ContactButton({ show }: { show: boolean }) {
  return (
    <div style={{ marginTop: '1.5rem', minHeight: '48px' }}>
      <motion.div
        initial={{ opacity: 0, scale: 0.9, y: 20 }}
        animate={{ 
          opacity: show ? 1 : 0, 
          scale: show ? 1 : 0.9, 
          y: show ? 0 : 20 
        }}
        transition={{
          duration: 0.6,
          ease: [0.16, 1, 0.3, 1],
          scale: { duration: 0.5, ease: [0.16, 1, 0.3, 1] }
        }}
        style={{ 
          pointerEvents: show ? 'auto' : 'none',
          visibility: show ? 'visible' : 'hidden'
        }}
      >
        <a
          href="mailto:corbin@nebulacreative.org"
          className="inline-block px-6 py-3 rounded-2xl text-white font-light text-sm tracking-wide no-underline min-h-[48px] cursor-pointer relative overflow-hidden"
          style={{
            background: `
              linear-gradient(135deg, rgba(0,0,0,0.15) 0%, rgba(0,0,0,0.25) 100%),
              rgba(255,255,255,0.02)
            `,
            backdropFilter: 'blur(20px) saturate(180%)',
            border: '1px solid rgba(255, 255, 255, 0.08)',
            boxShadow: `
              inset 0 1px 0 rgba(255, 255, 255, 0.1),
              0 0 0 1px rgba(255, 255, 255, 0.05),
              0 25px 50px -12px rgba(0, 0, 0, 0.25)
            `,
            transition: 'transform 0.3s ease, box-shadow 0.3s ease'
          }}
          aria-label="Contact Nebula Creative for stage management and show calling services"
          onMouseEnter={(e) => {
            if (show) {
              e.currentTarget.style.transform = 'scale(1.05) translateY(-2px)';
            }
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.transform = 'scale(1) translateY(0)';
          }}
          onMouseDown={(e) => {
            if (show) {
              e.currentTarget.style.transform = 'scale(0.98) translateY(-2px)';
            }
          }}
          onMouseUp={(e) => {
            if (show) {
              e.currentTarget.style.transform = 'scale(1.05) translateY(-2px)';
            }
          }}
        >
          {/* Multi-layer Glass Shimmer */}
          <div className="absolute inset-0 bg-gradient-to-br from-white/10 via-transparent to-white/5 rounded-2xl"></div>
          <div className="absolute inset-0 bg-gradient-to-tl from-transparent via-white/3 to-transparent rounded-2xl"></div>
          
          {/* Content */}
          <div className="relative z-10 flex items-center justify-center h-full">
            Contact Us
          </div>
        </a>
      </motion.div>
    </div>
  );
}

/* -------------------- MAIN COMPONENT -------------------- */
const NebulaShowtime: React.FC = () => {
  const [lightLevel, setLightLevel] = useState(0);
  const [pilePieces, setPilePieces] = useState<PilePiece[]>([]);
  const [pileHeight, setPileHeight] = useState(0);
  const [showRolling, setShowRolling] = useState(false);
  
  
  // Video store integration
  const { triggerVideoSequence, resetVideoState } = useVideoStore();

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


  // Trigger video sequence when "Go Video!" cue is reached
  useEffect(() => {
    const goVideoCue = CUE_LINES.find(c => c.text === "Go Video!");
    // Add 1.5 seconds delay to account for typing animation + user reading time
    const rollingTriggerTime = goVideoCue.t + 1500;
    if (goVideoCue && clockMs >= rollingTriggerTime && clockMs < rollingTriggerTime + 1000) {
      triggerVideoSequence();
    }
  }, [clockMs, triggerVideoSequence]);


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
            <LogoReactor />
            
            {/* Navigation Link */}
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.8, delay: 1.0 }}
              className="mt-4"
            >
              <a
                href="/cuetocue/"
                className="inline-block px-4 py-2 rounded-lg text-white/70 hover:text-white text-sm font-light tracking-wide no-underline transition-all duration-300 hover:bg-white/5"
                style={{
                  backdropFilter: 'blur(10px)',
                  border: '1px solid rgba(255, 255, 255, 0.1)',
                }}
                aria-label="Open Cue to Cue Viewer"
              >
                Cue to Cue Viewer
              </a>
            </motion.div>
        </header>
          <main>
            <h1 className="sr-only">Nebula Creative - Professional Stage Management, Show Calling, Production Management, and Tour Management Services</h1>
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
      
      
      <AboutEthosOverlay />
    </>
  );
};

export default NebulaShowtime;