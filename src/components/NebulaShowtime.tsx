import React, { useState, useEffect, useRef } from 'react';

const NebulaShowtime: React.FC = () => {
  const [allLogs, setAllLogs] = useState<string[]>([]);
  const scrollContainerRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    if (scrollContainerRef.current) {
      const container = scrollContainerRef.current;
      container.scrollTop = container.scrollHeight;
    }
  };

  useEffect(() => {
    // Add some test logs
    const logs = [
      "2:50:00 PM: Standby Lights.",
      "2:50:01 PM: Standby Video.", 
      "2:50:02 PM: Standby Audio.",
      "2:50:03 PM: GO Nebula Creative.",
      "2:50:04 PM: Cue 1 - Lights Up.",
      "2:50:05 PM: Cue 2 - Video Start.",
      "2:50:06 PM: Cue 3 - Audio Fade In.",
      "2:50:07 PM: Cue 4 - Confetti Ready.",
      "2:50:08 PM: Cue 5 - Standby for Next.",
      "2:50:09 PM: Cue 6 - Final Cue."
    ];
    setAllLogs(logs);
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [allLogs]);

  return (
    <div className="min-h-screen flex flex-col items-center justify-start px-4">
      {/* Main Content */}
      <div className="text-center max-w-4xl w-full relative z-10">
        <h1 className="text-6xl sm:text-8xl font-bold mb-6">
          <span className="text-white">NEBULA</span>
          <span className="text-blue-400"> CREATIVE</span>
        </h1>
        
        <p className="text-xl sm:text-2xl text-gray-300 mb-12 max-w-3xl mx-auto">
          We make the show happen — on time, on budget, on brand.
        </p>

        <div className="relative z-20">
          <button className="bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 text-white font-bold py-4 px-8 rounded-lg text-lg transition-all duration-300 transform hover:scale-105">
            Trigger Confetti
          </button>
        </div>
      </div>

      {/* Beautiful Stage Manager */}
      <div className="fixed top-1 right-1 z-50 stage-manager-mobile" style={{
        width: '400px',
        padding: '20px',
        fontSize: '24px',
        background: 'rgba(0,0,0,0.85)',
        border: '2px solid rgba(255,255,255,0.3)',
        borderRadius: '12px',
        maxHeight: '70vh',
        height: 'auto',
        overflow: 'hidden',
        backdropFilter: 'blur(10px)',
        boxShadow: '0 8px 32px rgba(0,0,0,0.3)'
      }}>
        {/* Stage Manager Header */}
        <div className="flex items-center gap-3 mb-4">
          <div className="w-3 h-3 bg-green-400 rounded-full animate-pulse"></div>
          <h3 style={{
            fontSize: '32px',
            fontWeight: '900',
            lineHeight: '1.1',
            color: 'white',
            textShadow: '2px 2px 4px rgba(0,0,0,0.8)'
          }}>Stage Manager</h3>
        </div>
        
        {/* Scrollable Content Container */}
        <div 
          ref={scrollContainerRef}
          className="stage-manager-scroll-container"
          style={{
            height: '300px',
            maxHeight: '300px',
            overflowY: 'auto',
            overflowX: 'hidden',
            scrollBehavior: 'smooth',
            paddingRight: '8px',
            display: 'flex',
            flexDirection: 'column',
            gap: '8px'
          }}
        >
          {allLogs.map((log, i) => (
            <div 
              key={i} 
              className="log-entry"
              style={{
                fontSize: '18px',
                lineHeight: '1.4',
                fontWeight: '500',
                color: 'white',
                textShadow: '1px 1px 2px rgba(0,0,0,0.8)',
                padding: '8px 12px',
                background: i === allLogs.length - 1 ? 'rgba(59, 130, 246, 0.2)' : 'rgba(255,255,255,0.05)',
                border: i === allLogs.length - 1 ? '1px solid rgba(59, 130, 246, 0.4)' : '1px solid transparent',
                borderRadius: '6px',
                transition: 'all 0.3s ease',
                borderLeft: '3px solid rgba(59, 130, 246, 0.6)'
              }}
            >
              {log}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default NebulaShowtime;
