import React, { useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { CUE_LINES } from '../../config/timing';
import { STAGE_MANAGER } from '../../config/design';
import type { StageManagerProps, StageLog } from '../../types/design';

/**
 * StageManager Component
 * Displays real-time stage cues and logs
 * 
 * Props:
 * - clockMs: Current time in milliseconds
 * - announce: Function to announce new messages
 * - isMobile: Whether running on mobile device
 */
export const StageManager: React.FC<StageManagerProps> = ({ 
  clockMs, 
  announce, 
  isMobile 
}) => {
  const [allLogs, setAllLogs] = useState<string[]>([]);
  const [currentCueText, setCurrentCueText] = useState("");
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    if (scrollContainerRef.current) {
      scrollContainerRef.current.scrollTop = scrollContainerRef.current.scrollHeight;
    }
  };

  useEffect(() => scrollToBottom(), [allLogs]);

  // Set up global announce function
  useEffect(() => {
    (window as any).stageManagerAnnounce = (msg: string) => {
      const timestamp = new Date().toLocaleTimeString();
      setAllLogs((prev) => [...prev, `${timestamp}: ${msg}`]);
    };
  }, []);

  // Handle cue timing
  useEffect(() => {
    const currentCue = CUE_LINES.find((c) => c.t <= clockMs && clockMs < c.t + 2000);
    if (currentCue && currentCueText !== currentCue.text) {
      setCurrentCueText(currentCue.text);
      const timestamp = new Date().toLocaleTimeString();
      setAllLogs((prev) => {
        const alreadyLogged = prev.some(log => log.includes(currentCue.text));
        return alreadyLogged ? prev : [...prev, `${timestamp}: ${currentCue.text}`];
      });
    }
  }, [clockMs, currentCueText]);

  return (
    <motion.aside 
      className={`w-[200px] sm:w-[250px] md:w-80 lg:w-96 xl:w-[420px] max-w-[calc(100vw-16px)] fixed top-[60px] right-2 z-50 font-system`}
      role="complementary"
      aria-label="Stage Manager - Live Event Production Log"
      initial={{ opacity: 0, scale: 0.9, y: -20, rotateX: -10 }}
      animate={{ opacity: 1, scale: 1, y: 0, rotateX: 0 }}
      transition={{
        duration: 0.8,
        ease: [0.16, 1, 0.3, 1],
        scale: { duration: 0.6, ease: [0.16, 1, 0.3, 1] },
        rotateX: { duration: 0.7, ease: [0.16, 1, 0.3, 1] }
      }}
      whileHover={{
        scale: 1.02,
        y: -2,
        transition: { duration: 0.3, ease: [0.16, 1, 0.3, 1] }
      }}
    >
      {/* Premium Glass Morphism Container */}
      <div
        className="relative rounded-3xl shadow-2xl overflow-hidden"
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
          `
        }}
      >
        {/* Multi-layer Glass Shimmer */}
        <div className="absolute inset-0 bg-gradient-to-br from-white/10 via-transparent to-white/5 rounded-3xl"></div>
        <div className="absolute inset-0 bg-gradient-to-tl from-transparent via-white/3 to-transparent rounded-3xl"></div>
        
        {/* Content Layer */}
        <div className="relative z-10 p-3">
          {/* Header with Premium Status Indicator */}
          <motion.header 
            className="flex items-center gap-2 mb-3 pb-2 border-b border-white/10"
            initial={{ opacity: 0, y: -10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2, duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
          >
            <motion.div 
              className="relative w-3 h-3 rounded-full flex-shrink-0"
              aria-label="System online"
              role="status"
              initial={{ scale: 0, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ delay: 0.4, duration: 0.5, ease: [0.16, 1, 0.3, 1] }}
            >
              {/* Pulsing Status Indicator */}
              <div className="absolute inset-0 bg-green-400 rounded-full animate-pulse"></div>
              <div 
                className="absolute inset-0 bg-green-400 rounded-full"
                style={{
                  boxShadow: '0 0 8px rgba(34, 197, 94, 0.6), 0 0 16px rgba(34, 197, 94, 0.3)'
                }}
              ></div>
            </motion.div>
            
            <motion.h2 
              className="text-sm sm:text-base lg:text-lg font-light text-white tracking-wide m-0"
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.3, duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
            >
              Stage Manager
            </motion.h2>
          </motion.header>

          {/* Premium Logs Container */}
          <motion.div 
            ref={scrollContainerRef} 
            className="h-32 sm:h-36 md:h-40 lg:h-44 xl:h-48 overflow-y-auto overflow-x-hidden flex flex-col gap-1 rounded-2xl p-2.5"
            role="log"
            aria-live="polite"
            aria-label="Production cues and stage management logs"
            style={{
              background: 'rgba(255, 255, 255, 0.03)',
              backdropFilter: 'blur(10px)',
              border: '1px solid rgba(255, 255, 255, 0.05)'
            }}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4, duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
          >
            <AnimatePresence mode="popLayout">
              {allLogs.slice(-10).map((log, i) => {
                const isLatest = i === allLogs.slice(-10).length - 1;
                
                // Parse time and cue text
                const timeMatch = log.match(/^(\d{1,2}:\d{2}:\d{2}\s*[AP]M):\s*(.+)$/);
                const time = timeMatch ? timeMatch[1] : '';
                const cueText = timeMatch ? timeMatch[2] : log;
                
                return (
                  <motion.div
                    key={`${log}-${i}`}
                    className={`leading-none p-1.5 rounded-lg break-words font-mono flex items-center gap-2 ${
                      isLatest 
                        ? 'text-green-300 bg-green-400/10 border border-green-400/20' 
                        : 'text-white/80 bg-white/5 border border-white/10'
                    }`}
                    role="listitem"
                    aria-label={isLatest ? `Latest cue: ${log}` : `Previous cue: ${log}`}
                    initial={{ opacity: 0, scale: 0.95, y: 10 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    exit={{ opacity: 0, scale: 0.95, y: -10 }}
                    transition={{
                      duration: 0.4,
                      ease: [0.16, 1, 0.3, 1],
                      delay: isLatest ? 0 : 0.1
                    }}
                    whileHover={{
                      scale: 1.02,
                      y: -1,
                      transition: { duration: 0.2, ease: [0.16, 1, 0.3, 1] }
                    }}
                    style={{
                      boxShadow: isLatest 
                        ? '0 4px 12px rgba(34, 197, 94, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.1)'
                        : '0 2px 8px rgba(0, 0, 0, 0.1), inset 0 1px 0 rgba(255, 255, 255, 0.05)'
                    }}
                  >
                    {time && (
                      <span 
                        className="text-[5px] sm:text-[6px] lg:text-[7px] font-mono tracking-tight flex-shrink-0 opacity-70"
                        style={{ letterSpacing: '-0.5px' }}
                      >
                        {time}
                      </span>
                    )}
                    <span className="text-[9px] sm:text-[10px] lg:text-[11px] font-mono flex-1">
                      {cueText}
                    </span>
                  </motion.div>
                );
              })}
            </AnimatePresence>
          </motion.div>
        </div>
      </div>
    </motion.aside>
  );
};

export default StageManager;
