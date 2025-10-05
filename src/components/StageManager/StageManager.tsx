import React, { useEffect, useRef, useState } from 'react';
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
    <div className={`${STAGE_MANAGER.container} ${STAGE_MANAGER.mobile.width} sm:${STAGE_MANAGER.tablet.width} md:${STAGE_MANAGER.desktop.width} max-w-[calc(100vw-16px)] ${STAGE_MANAGER.mobile.padding} ${STAGE_MANAGER.mobile.fontSize}`}>
      {/* Header with status indicator */}
      <div className="flex items-center gap-1 mb-1.5 pb-1.5 border-b border-white/15">
        <div className="w-1 h-1 bg-green-400 rounded-full flex-shrink-0" />
        <div className={STAGE_MANAGER.title}>Stage Manager</div>
      </div>

      {/* Logs container */}
      <div ref={scrollContainerRef} className={STAGE_MANAGER.scroll}>
        {allLogs.slice(-10).map((log, i) => {
          const isLatest = i === allLogs.slice(-10).length - 1;
          return (
            <div
              key={`${log}-${i}`}
              className={`${STAGE_MANAGER.log} ${
                isLatest 
                  ? 'text-green-400 bg-green-400/15 border border-green-400/30' 
                  : 'text-slate-300 bg-white/5 border border-white/10'
              }`}
            >
              {log}
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default StageManager;
