import React, { useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import confetti from "canvas-confetti";

/**
 * Nebula Creative — Show Preview (Realistic Confetti Landing + Logs)
 * - Lights: GO to 100%, dim to 40%, stay on
 * - Stage Manager: initial cues + logs when you change confetti effect
 * - Button centered; cycles 5 effects
 * - Realistic pile: pieces land after a fall delay (no instant pop at bottom)
 * - Height-map pile so the heap grows with a natural slope
 * - Two sticky notes bottom-right
 */

/* -------------------- THEME -------------------- */
const BRAND = {
  bgA: "#0a0f15",
  bgB: "#0e1421",
  postit: "#FFEB3B",
  ink: "#111111",
  glass: "rgba(255,255,255,0.06)",
  border: "rgba(255,255,255,0.12)",
  glow: "rgba(148, 197, 255, 0.25)",
};

const cueLines = [
  { t: 0, text: "Standby Lights." },
  { t: 900, text: "Standby Video." },
  { t: 1800, text: "Standby Audio." },
  { t: 2800, text: "Standby Confetti." },
  { t: 4000, text: "Go Lights!" },
  { t: 5800, text: "Go Video!" },
  { t: 7600, text: "Go Audio!" },
  { t: 9000, text: "GO Confetti!" },
  { t: 11000, text: "GO Nebula Creative." },
];

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

function useConfettiEngine() {
  return useMemo(() => {
    const anyConf = confetti as any;
    if (anyConf.create)
      return anyConf.create(undefined, { resize: true, useWorker: true, zIndex: 1000 });
    return confetti;
  }, []);
}

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
      className="fixed inset-0 pointer-events-none"
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
          className="absolute"
          style={{
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
  "Kalam, Indie Flower, Permanent Marker, Caveat, Comic Sans MS, cursive";

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

function Sticky({
  text,
  pos,
  className = "",
}: {
  text: string;
  pos: { right: number; bottom: number; rot?: number };
  className?: string;
}) {
  const size = "clamp(80px, 8vw, 120px)";
  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 220, damping: 18 }}
      className={`fixed z-[40] sm:z-[60] pointer-events-none ${className}`}
      style={{ right: pos.right, bottom: pos.bottom, transform: `rotate(${pos.rot ?? -2}deg)` }}
    >
      <div
        style={{
          width: size,
          height: size,
          backgroundColor: "#FFF59D", // Slightly warmer, more realistic yellow
          color: BRAND.ink,
          // Multiple layered shadows for realistic depth
          boxShadow: `
            0 1px 3px rgba(0,0,0,0.12),
            0 1px 2px rgba(0,0,0,0.24),
            0 4px 8px rgba(0,0,0,0.15),
            0 8px 16px rgba(0,0,0,0.1),
            inset 0 1px 0 rgba(255,255,255,0.3)
          `,
          borderRadius: 4,
          padding: 8,
          fontFamily: HAND_FONT_STACK,
          fontSize: 11,
          fontWeight: 400,
          lineHeight: 1.1,
          letterSpacing: 0.2,
          // Handwriting imperfections
          textShadow: "0.5px 0.5px 0px rgba(0,0,0,0.1)",
          // Paper texture and grain
          backgroundImage: `
            radial-gradient(circle at 20% 30%, rgba(255,255,255,0.1) 0%, transparent 50%),
            radial-gradient(circle at 80% 70%, rgba(255,255,255,0.05) 0%, transparent 50%),
            radial-gradient(circle at 40% 80%, rgba(0,0,0,0.02) 0%, transparent 50%),
            linear-gradient(45deg, transparent 30%, rgba(255,255,255,0.1) 50%, transparent 70%)
          `,
          // Subtle paper texture
          filter: "contrast(1.1) brightness(1.05)",
          // Combined paper curl and text rotation effect
          transform: "perspective(100px) rotateX(2deg) rotateY(1deg) rotate(0.5deg)",
          // Natural paper feel
          border: "1px solid rgba(255,255,255,0.2)",
        }}
      >
        {text}
      </div>
    </motion.div>
  );
}

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

function buildRainParticleOptions() {
  return {
    startVelocity: 0,
    gravity: 0.7,
    ticks: 2000,
    spread: 20,
    scalar: 0.9,
    originY: -0.1,
    zIndex: 1000,
  };
}

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

function ConfettiButton({
  scheduleLandings,
  clockMs,
  onConfettiPressed,
}: {
  scheduleLandings: (items: LandingSpec[]) => void;
  clockMs: number;
  onConfettiPressed: () => void;
}) {
  const [count, setCount] = useState(0);
  const [isActive, setIsActive] = useState(false);
  const fire = useConfettiEngine();
  const COLORS = ["#FFD166", "#EF476F", "#06D6A0", "#118AB2", "#FF9F1C", "#9B5DE5"];

  // Activate button when "GO Confetti!" cue is reached
  useEffect(() => {
    const goConfettiCue = cueLines.find(c => c.text === "GO Confetti!");
    // Add 1.5 seconds delay to account for typing animation + user reading time
    const buttonTriggerTime = goConfettiCue.t + 1500;
    if (goConfettiCue && clockMs >= buttonTriggerTime && !isActive) {
      setIsActive(true);
    }
  }, [clockMs, isActive]);

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
    if ((window as any).stageManagerAnnounce) {
      (window as any).stageManagerAnnounce(msg);
    }
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
      fire({ particleCount: 300, spread: 160, origin: { y: 0.6 } });
      const specs = makeSpecs(80, { delayMin: 2000, delayMax: 4000 });
      scheduleLandings(specs);
      announce("Classic burst");
    },
    () => {
      startRain();
    },
    () => {
      fire({ particleCount: 200, angle: 60, spread: 55, origin: { x: 0, y: 0.6 } });
      fire({ particleCount: 200, angle: 120, spread: 55, origin: { x: 1, y: 0.6 } });
      const specs = makeSpecs(100, { delayMin: 2000, delayMax: 4000, xDist: "sides" });
      scheduleLandings(specs);
      announce("Side cannons");
    },
    () => {
      fire({
        particleCount: 400,
        spread: 160,
        colors: COLORS,
        origin: { y: 0.6 },
      });
      const specs = makeSpecs(120, { delayMin: 2000, delayMax: 5000 });
      scheduleLandings(specs);
      announce("Color chaos");
    },
    () => {
      fire({ particleCount: 1000, spread: 360, startVelocity: 40, origin: { y: 0.6 } });
      const specs = makeSpecs(200, { delayMin: 2000, delayMax: 6000 });
      scheduleLandings(specs);
      announce("MEGA EXPLOSION");
    },
  ];

  return (
    <motion.button
      onClick={() => {
        if (isActive) {
          effects[count % effects.length]();
          setCount((c) => c + 1);
          onConfettiPressed();
        }
      }}
      whileHover={isActive ? { scale: 1.05 } : {}}
      whileTap={isActive ? { scale: 0.95 } : {}}
      animate={isActive ? { 
        boxShadow: [
          "0 0 0 0 rgba(147, 51, 234, 0.7)",
          "0 0 0 10px rgba(147, 51, 234, 0)",
          "0 0 0 0 rgba(147, 51, 234, 0)"
        ]
      } : {}}
      transition={isActive ? { 
        boxShadow: { 
          duration: 1.5, 
          repeat: Infinity, 
          ease: "easeInOut" 
        } 
      } : {}}
      className={`px-6 sm:px-8 py-3 sm:py-4 rounded-xl text-base sm:text-lg font-semibold transition-all duration-200 shadow-lg min-h-[44px] button-mobile ${
        isActive 
          ? "bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 focus:outline-none focus:ring-4 focus:ring-purple-500/50 cursor-pointer" 
          : "bg-gray-600 text-gray-400 cursor-not-allowed"
      }`}
    >
      Trigger Confetti
    </motion.button>
  );
}

/* -------------------- STAGE MANAGER -------------------- */
function StageManager({ clockMs, announce, isMobile }: { clockMs: number; announce: (msg: string) => void; isMobile: boolean }) {
  const [allLogs, setAllLogs] = useState<string[]>([]);
  const [currentCueText, setCurrentCueText] = useState("");
  const [showCues, setShowCues] = useState(true);
  // Add ref for scrollable container
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  // AGGRESSIVE auto-scroll to bottom function - MULTIPLE METHODS
  const scrollToBottom = () => {
    if (scrollContainerRef.current) {
      const container = scrollContainerRef.current;
      
      // Method 1: Direct scrollTop
      container.scrollTop = container.scrollHeight;
      
      // Method 2: Force with requestAnimationFrame
      requestAnimationFrame(() => {
        container.scrollTop = container.scrollHeight;
      });
      
      // Method 3: Force with setTimeout
      setTimeout(() => {
        container.scrollTop = container.scrollHeight;
      }, 0);
      
      // Method 4: Force with longer timeout
      setTimeout(() => {
        container.scrollTop = container.scrollHeight;
      }, 100);
    }
  };

  // AGGRESSIVE auto-scroll when new logs are added - MULTIPLE TRIGGERS
  useEffect(() => {
    // Immediate scroll
    scrollToBottom();
    
    // Delayed scroll after animation
    setTimeout(scrollToBottom, 50);
    setTimeout(scrollToBottom, 100);
    setTimeout(scrollToBottom, 200);
    setTimeout(scrollToBottom, 500);
  }, [allLogs]);

  // FORCE scroll on every render - AGGRESSIVE
  useEffect(() => {
    const interval = setInterval(scrollToBottom, 500);
    return () => clearInterval(interval);
  }, []);

  // FORCE scroll when component mounts
  useEffect(() => {
    scrollToBottom();
  }, []);

  // FORCE scroll on window resize
  useEffect(() => {
    const handleResize = () => scrollToBottom();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  // Safari-specific fix: Force font sizes immediately and repeatedly
  useEffect(() => {
    const forceFontSizes = () => {
      const stageManager = document.querySelector('.stage-manager-mobile');
      if (stageManager) {
        const title = stageManager.querySelector('h3');
        const logs = stageManager.querySelectorAll('.text-slate-300');
        
        if (title) {
          title.style.fontSize = '32px';
          title.style.lineHeight = '1.1';
          title.style.fontWeight = '900';
          title.style.color = 'white';
          title.style.textShadow = '2px 2px 4px rgba(0,0,0,0.8)';
          title.style.setProperty('font-size', '32px', 'important');
        }
        
        logs.forEach(log => {
          log.style.fontSize = '24px';
          log.style.lineHeight = '1.2';
          log.style.fontWeight = '600';
          log.style.color = 'white';
          log.style.textShadow = '1px 1px 2px rgba(0,0,0,0.8)';
          log.style.setProperty('font-size', '24px', 'important');
        });
      }
    };

    // Force immediately
    forceFontSizes();
    
    // Force after short delay
    const timer1 = setTimeout(forceFontSizes, 100);
    
    // Force after animation completes
    const timer2 = setTimeout(forceFontSizes, 1000);
    
    // Force repeatedly to override Safari's caching
    const interval = setInterval(forceFontSizes, 2000);

    return () => {
      clearTimeout(timer1);
      clearTimeout(timer2);
      clearInterval(interval);
    };
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => setShowCues(false), 12000);
    return () => clearTimeout(timer);
  }, []);

  // Add announce function to global scope so ConfettiButton can use it
  useEffect(() => {
    (window as any).stageManagerAnnounce = (msg: string) => {
      const timestamp = new Date().toLocaleTimeString();
      setAllLogs((prev) => [...prev, `${timestamp}: ${msg}`]);
    };
  }, []);

  // Handle cue progression
  useEffect(() => {
    const currentCue = cueLines.find((c) => c.t <= clockMs && clockMs < c.t + 2000);
    if (currentCue && currentCue.text !== currentCueText) {
      setCurrentCueText(currentCue.text);
      // Add cue to logs when it first appears
      const timestamp = new Date().toLocaleTimeString();
      setAllLogs((prev) => {
        // Check if this cue is already in the logs to prevent duplicates
        const alreadyLogged = prev.some(log => log.includes(currentCue.text));
        if (!alreadyLogged) {
          return [...prev, `${timestamp}: ${currentCue.text}`];
        }
        return prev;
      });
    }
  }, [clockMs, currentCueText]);

  return (
        <motion.div
      initial={{ 
        opacity: 0, 
        x: 20,
        // Start with large, readable font sizes
        fontSize: '20px',
        lineHeight: '1.3'
      }}
      animate={{ 
        opacity: 1, 
        x: 0,
        // Maintain large, readable font sizes
        fontSize: '20px',
        lineHeight: '1.3'
      }}
      transition={{ delay: 0.5 }}
      className="fixed top-1 right-1 z-50 stage-manager-mobile"
      style={{ 
        width: '400px',
        padding: '20px',
        fontSize: '24px',
        lineHeight: '1.2',
        background: 'rgba(0,0,0,0.8)',
        border: '2px solid white',
        maxHeight: 'none',
        height: 'auto',
        overflow: 'visible'
      }}
    >
      <div
        style={{
          background: BRAND.glass,
          border: `1px solid ${BRAND.border}`,
          borderRadius: 6,
          padding: 4,
          backdropFilter: "blur(12px)",
          height: 'auto',
          maxHeight: 'none',
          minHeight: 'auto',
          overflow: 'visible'
        }}
      >
        <motion.div 
          className="flex items-center gap-3 mb-4"
          initial={{ fontSize: '32px', lineHeight: '1.1', fontWeight: '900' }}
          animate={{ fontSize: '32px', lineHeight: '1.1', fontWeight: '900' }}
        >
          <div className="w-4 h-4 bg-green-400 rounded-full animate-pulse" />
          <h3 className="font-black text-white" style={{ 
            fontSize: '32px', 
            lineHeight: '1.1', 
            fontWeight: '900',
            textShadow: '2px 2px 4px rgba(0,0,0,0.8)'
          }}>Stage Manager</h3>
        </motion.div>

        <div 
          ref={scrollContainerRef}
          className="space-y-2" 
          style={{ 
            minHeight: 'auto', 
            height: 'auto', 
            maxHeight: '60vh', 
            overflowY: 'auto',
            overflowX: 'hidden',
            scrollBehavior: 'smooth'
          }}
        >
          {/* Debug: Show log count */}
          <div style={{ fontSize: '12px', color: 'yellow', marginBottom: '10px' }}>
            Debug: {allLogs.length} logs
          </div>
          
          {/* FORCE SCROLL TO BOTTOM BUTTON */}
          <div style={{ textAlign: 'center', marginBottom: '10px' }}>
            <button 
              onClick={scrollToBottom}
              style={{
                background: 'rgba(255,255,255,0.2)',
                border: '1px solid white',
                color: 'white',
                padding: '4px 8px',
                fontSize: '10px',
                borderRadius: '4px',
                cursor: 'pointer'
              }}
            >
              ↓ Latest Cue
            </button>
          </div>
          {/* ALWAYS SHOW LAST 10 LOGS - FORCE VISIBILITY */}
          {allLogs.slice(-10).map((log, i) => (
            <motion.div
              key={`${log}-${i}`}
              initial={{ 
                opacity: 0, 
                y: 10,
                fontSize: '24px',
                lineHeight: '1.2',
                fontWeight: '600'
              }}
              animate={{ 
                opacity: 1, 
                y: 0,
                fontSize: '24px',
                lineHeight: '1.2',
                fontWeight: '600'
              }}
              transition={{ duration: 0.3 }}
              className="text-slate-300 font-mono leading-tight"
              style={{ 
                fontSize: '24px', 
                lineHeight: '1.2', 
                fontWeight: '600',
                color: 'white',
                textShadow: '1px 1px 2px rgba(0,0,0,0.8)',
                // FORCE latest cue to be visible
                backgroundColor: i === allLogs.slice(-10).length - 1 ? 'rgba(255,255,255,0.1)' : 'transparent',
                border: i === allLogs.slice(-10).length - 1 ? '1px solid rgba(255,255,255,0.3)' : 'none',
                borderRadius: i === allLogs.slice(-10).length - 1 ? '4px' : '0',
                padding: i === allLogs.slice(-10).length - 1 ? '4px' : '0'
              }}
            >
              {log}
            </motion.div>
            ))}
        </div>
      </div>
    </motion.div>
  );
}

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
          className="fixed top-16 sm:top-20 left-4 sm:left-6 z-50"
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
          className="fixed top-4 sm:top-6 left-4 sm:left-6 z-50"
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
          className="mt-6 sm:mt-8"
        >
          <motion.a
            href="mailto:corbin@nebulacreative.org"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className="inline-block px-6 sm:px-8 py-3 sm:py-4 rounded-lg text-base sm:text-lg font-medium bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 focus:outline-none focus:ring-4 focus:ring-emerald-500/50 transition-all duration-200 shadow-lg text-white min-h-[44px] button-mobile"
          >
            Contact Us
          </motion.a>
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
    const goLightsCue = cueLines.find(c => c.text === "Go Lights!");
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
    const goAudioCue = cueLines.find(c => c.text === "Go Audio!");
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
    const goVideoCue = cueLines.find(c => c.text === "Go Video!");
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
          className="text-center max-w-4xl w-full relative z-10"
        >
          <div className="mb-4 sm:mb-6 relative z-20">
            <img 
              src="/assets/Nebula Logo Color Text.png" 
              alt="Nebula Creative" 
              className="h-32 sm:h-40 md:h-48 lg:h-64 w-auto mx-auto relative z-30 logo-mobile"
            />
        </div>
          <p className="text-lg sm:text-xl md:text-2xl text-slate-300 mb-8 sm:mb-12 max-w-2xl mx-auto px-2 relative z-20">
            We make the show happen — on time, on budget, on brand.
          </p>
          
          <div className="relative z-20">
            <ConfettiButton scheduleLandings={scheduleLandings} clockMs={clockMs} onConfettiPressed={handleConfettiPressed} />
            <ContactButton show={showContactButton} />
          </div>
        </motion.div>

        <ConfettiPile pieces={pilePieces} heightPx={pileHeight} />
        
        {/* MOBILE ONLY - Single sticky note */}
        <Sticky 
          text={randomCleanup} 
          pos={{ right: 12, bottom: 40, rot: -3 }} 
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