import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useVideoStore } from '../../stores/videoStore';

interface VideoRollingIndicatorProps {
  className?: string;
}

/**
 * VideoRollingIndicator Component
 * Displays a persistent "VIDEO ROLLING" indicator when video is active
 * Updated to match the cyan color scheme from the motion storyboard
 */
export const VideoRollingIndicator: React.FC<VideoRollingIndicatorProps> = ({ 
  className = "fixed top-4 left-4 z-50"
}) => {
  const { isVideoRolling } = useVideoStore();

  return (
    <AnimatePresence>
      {isVideoRolling && (
        <motion.div
          className={className}
          initial={{ opacity: 0, scale: 0.8, y: -20, rotateX: -15 }}
          animate={{ opacity: 1, scale: 1, y: 0, rotateX: 0 }}
          exit={{ opacity: 0, scale: 0.9, y: -10, rotateX: 10 }}
          transition={{
            duration: 0.6,
            ease: [0.16, 1, 0.3, 1],
            scale: { duration: 0.5, ease: [0.16, 1, 0.3, 1] },
            rotateX: { duration: 0.5, ease: [0.16, 1, 0.3, 1] }
          }}
        >
          <div className="relative">
            {/* Premium Glass Morphism Bubble with Cyan Accent */}
            <div
              className="relative rounded-2xl shadow-2xl overflow-hidden max-w-[280px] sm:max-w-xs"
              style={{
                background: `
                  linear-gradient(135deg, rgba(32,164,255,0.15) 0%, rgba(20,130,204,0.25) 100%),
                  rgba(255,255,255,0.02)
                `,
                backdropFilter: 'blur(20px) saturate(180%)',
                border: '1px solid rgba(32, 164, 255, 0.2)',
                boxShadow: `
                  inset 0 1px 0 rgba(255, 255, 255, 0.1),
                  0 0 0 1px rgba(32, 164, 255, 0.1),
                  0 25px 50px -12px rgba(32, 164, 255, 0.25)
                `
              }}
            >
              {/* Multi-layer Glass Shimmer with Cyan Tint */}
              <div className="absolute inset-0 bg-gradient-to-br from-cyan-500/10 via-transparent to-cyan-500/5 rounded-2xl"></div>
              <div className="absolute inset-0 bg-gradient-to-tl from-transparent via-white/3 to-transparent rounded-2xl"></div>
              
              {/* Content */}
              <div className="relative z-10 px-3 sm:px-4 py-2 sm:py-3">
                <div className="font-light text-white text-xs sm:text-sm tracking-wide flex items-center gap-2">
                  <motion.div 
                    className="w-2 h-2 bg-cyan-400 rounded-full"
                    animate={{ 
                      scale: [1, 1.2, 1],
                      opacity: [0.7, 1, 0.7]
                    }}
                    transition={{ 
                      duration: 1.5, 
                      repeat: Infinity,
                      ease: "easeInOut"
                    }}
                    style={{
                      boxShadow: '0 0 8px #20A4FF'
                    }}
                  />
                  Video Rolling
                </div>
              </div>
            </div>
            
            {/* Glass Morphism Tail with Cyan Accent */}
            <div 
              className="absolute -bottom-2 left-4 w-0 h-0"
              style={{
                borderLeft: "8px solid transparent",
                borderRight: "8px solid transparent", 
                borderTop: "8px solid rgba(32, 164, 255, 0.2)"
              }}
            />
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default VideoRollingIndicator;