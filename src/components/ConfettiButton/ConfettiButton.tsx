import React, { useEffect, useState, useMemo } from 'react';
import confetti from 'canvas-confetti';
import { CUE_LINES } from '../../config/timing';
import { CONFETTI_BUTTON } from '../../config/design';
import type { ConfettiButtonProps, ConfettiEffect } from '../../types/design';

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
    if (anyConf.create)
      return anyConf.create(undefined, { resize: true, useWorker: true, zIndex: 1000 });
    return confetti;
  }, []);
}

// Rain particle options builder
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

/**
 * ConfettiButton Component
 * Cycles through different confetti effects when clicked
 * 
 * Props:
 * - scheduleLandings: Function to schedule confetti landings
 * - clockMs: Current time in milliseconds
 * - onConfettiPressed: Callback when button is pressed
 */
export const ConfettiButton: React.FC<{
  scheduleLandings: (items: LandingSpec[]) => void;
  clockMs: number;
  onConfettiPressed: () => void;
}> = ({ scheduleLandings, clockMs, onConfettiPressed }) => {
  const [count, setCount] = useState(0);
  const [isActive, setIsActive] = useState(false);
  const fire = useConfettiEngine();
  const COLORS = ["#FFD166", "#EF476F", "#06D6A0", "#118AB2", "#FF9F1C", "#9B5DE5"];

  // Activate button when "GO Confetti!" cue is reached
  useEffect(() => {
    const goConfettiCue = CUE_LINES.find(c => c.text === "GO Confetti!");
    // Add 1.5 seconds delay to account for typing animation + user reading time
    const buttonTriggerTime = goConfettiCue!.t + 1500;
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
    <button
      onClick={() => {
        if (isActive) {
          effects[count % effects.length]();
          setCount((c) => c + 1);
          onConfettiPressed();
        }
      }}
      className={`${CONFETTI_BUTTON.mobile} ${
        isActive 
          ? `${CONFETTI_BUTTON.base} bg-gradient-to-r from-purple-500 to-blue-600 text-white cursor-pointer` 
          : CONFETTI_BUTTON.inactive
      }`}
      disabled={!isActive}
    >
      Trigger Confetti
    </button>
  );
};

export default ConfettiButton;
