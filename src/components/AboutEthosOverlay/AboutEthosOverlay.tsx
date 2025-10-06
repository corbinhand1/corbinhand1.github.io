import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';

/**
 * AboutEthosOverlay Component
 * $1M Design - Small floating window in bottom-left corner
 * 
 * Design Philosophy:
 * - Luxury floating window (not full-screen)
 * - Stays in bottom-left corner
 * - Unobtrusive but stunning
 * - Cinematic micro-interactions
 * - Premium materials and finishes
 */
export const AboutEthosOverlay: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);

  // Handle escape key
  useEffect(() => {
    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        setIsOpen(false);
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen]);

  return (
    <>
      {/* About Button - Fixed Bottom Left */}
      <motion.button
        initial={{ opacity: 0, scale: 0.8 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ 
          delay: 1.2, 
          duration: 0.8, 
          ease: [0.4, 0, 0.2, 1] 
        }}
        onClick={() => setIsOpen(true)}
        className="fixed bottom-6 left-6 z-[9998] group sm:bottom-6 sm:left-6 md:bottom-8 md:left-8"
        aria-label="About Nebula Creative"
        aria-expanded={isOpen}
        aria-controls="about-overlay"
        type="button"
      >
        {/* Subtle Glow Ring */}
        <motion.div
          className="absolute inset-0 rounded-full bg-gradient-to-r from-blue-400/30 to-purple-400/30 blur-md"
          animate={{
            scale: [1, 1.05, 1],
            opacity: [0.2, 0.4, 0.2],
          }}
          transition={{
            duration: 4,
            repeat: Infinity,
            ease: "easeInOut"
          }}
        />
        
        {/* Main Button */}
        <div className="relative w-14 h-14 rounded-full bg-black/20 backdrop-blur-xl border border-white/10 group-hover:border-white/30 transition-all duration-500 flex items-center justify-center">
          {/* About Icon */}
          <svg
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            className="text-white/70 group-hover:text-white transition-colors duration-300"
          >
            <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="1.2" />
            <path d="M12 16v-4" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
            <circle cx="12" cy="8" r="1" fill="currentColor" />
          </svg>
        </div>
      </motion.button>

      {/* Floating Window Overlay */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            id="about-overlay"
            role="dialog"
            aria-modal="true"
            aria-labelledby="about-title"
            className="fixed bottom-6 left-6 z-[9999] sm:bottom-6 sm:left-6 md:bottom-8 md:left-8"
            initial={{ opacity: 0, scale: 0.8, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.8, y: 20 }}
            transition={{ duration: 0.4, ease: [0.4, 0, 0.2, 1] }}
          >
            {/* Luxury Floating Window */}
            <div className="relative w-80 sm:w-96 md:w-[420px] max-h-[500px] overflow-hidden">
              {/* Subtle Backdrop Glow */}
              <motion.div
                className="absolute inset-0 bg-gradient-to-br from-blue-400/10 via-purple-400/5 to-transparent rounded-3xl blur-xl"
                animate={{
                  opacity: [0.3, 0.6, 0.3],
                }}
                transition={{
                  duration: 3,
                  repeat: Infinity,
                  ease: "easeInOut"
                }}
              />

              {/* Main Window - Dark Liquid Glass */}
              <div className="relative backdrop-blur-xl bg-black/40 border border-white/20 rounded-3xl shadow-2xl overflow-hidden">
                {/* Dark Liquid Glass Texture Layers */}
                <div className="absolute inset-0 bg-gradient-to-br from-black/30 via-black/20 to-transparent rounded-3xl" />
                <div className="absolute inset-0 bg-gradient-to-tl from-transparent via-black/15 to-black/25 rounded-3xl" />
                <div className="absolute inset-0 bg-gradient-radial from-black/20 via-transparent to-transparent rounded-3xl" />
                <div className="absolute inset-0 bg-gradient-to-r from-transparent via-black/10 to-transparent rounded-3xl" />
                <div className="absolute inset-0 bg-gradient-to-b from-transparent via-black/10 to-transparent rounded-3xl" />
                
                {/* Subtle White Highlights */}
                <div className="absolute inset-0 bg-gradient-to-br from-white/5 via-transparent to-transparent rounded-3xl" />
                <div className="absolute inset-0 bg-gradient-to-tl from-transparent via-white/3 to-white/8 rounded-3xl" />
                
                {/* Animated Shimmer Effect - Darker */}
                <motion.div
                  className="absolute inset-0 bg-gradient-to-r from-transparent via-white/8 to-transparent rounded-3xl"
                  animate={{
                    x: ['-100%', '100%'],
                  }}
                  transition={{
                    duration: 3,
                    repeat: Infinity,
                    repeatDelay: 2,
                    ease: "easeInOut"
                  }}
                />
                
                {/* Content Layer */}
                <div className="relative z-10">
                {/* Window Header */}
                <div className="flex items-center justify-between p-4 border-b border-white/20">
                  <h2 id="about-title" className="text-lg font-light text-white tracking-wide">
                    About Nebula Creative
                  </h2>
                  <motion.button
                    onClick={() => setIsOpen(false)}
                    className="w-8 h-8 rounded-full bg-white/10 hover:bg-white/20 transition-all duration-300 flex items-center justify-center group"
                    aria-label="Close about window"
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                  >
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      className="text-white/80 group-hover:text-white transition-colors duration-200"
                    >
                      <path
                        d="M18 6L6 18M6 6l12 12"
                        stroke="currentColor"
                        strokeWidth="1.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                  </motion.button>
                </div>

                {/* Window Content */}
                <div className="p-6 space-y-6 max-h-[400px] overflow-y-auto">
                  {/* Main Content */}
                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.1, duration: 0.4 }}
                  >
                    <p className="text-sm leading-relaxed text-white/90 font-light">
                      Nebula Creative is led by <span className="text-white font-medium">Corbin Hand</span> — 
                      a world-traveled stage manager, show caller, and production manager with over two decades 
                      in live entertainment.
                    </p>
                  </motion.div>

                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.2, duration: 0.4 }}
                  >
                    <p className="text-sm leading-relaxed text-white/90 font-light">
                      From global concert tours to high-end corporate experiences, 
                      Nebula Creative delivers flawless execution where precision and timing define success.
                    </p>
                  </motion.div>

                  {/* Accent Line */}
                  <motion.div
                    className="h-px bg-gradient-to-r from-transparent via-blue-400/30 to-transparent"
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ delay: 0.3, duration: 0.8, ease: [0.4, 0, 0.2, 1] }}
                  />

                  {/* Location */}
                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.4, duration: 0.4 }}
                  >
                    <p className="text-xs text-white/70 font-light tracking-wide uppercase">
                      Based in Nashville — Operating Worldwide
                    </p>
                  </motion.div>

                  {/* Contact CTA */}
                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.5, duration: 0.4 }}
                  >
                    <a
                      href="mailto:corbin@nebulacreative.org"
                      className="inline-flex items-center px-4 py-2 bg-white/10 hover:bg-white/20 border border-white/30 hover:border-white/50 rounded-full text-white transition-all duration-300 group backdrop-blur-sm"
                    >
                      <span className="text-xs font-medium tracking-wide">Contact</span>
                      <svg
                        width="14"
                        height="14"
                        viewBox="0 0 24 24"
                        fill="none"
                        className="ml-2 text-white/80 group-hover:text-white transition-colors duration-200"
                      >
                        <path
                          d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"
                          stroke="currentColor"
                          strokeWidth="1.5"
                          fill="none"
                        />
                        <path
                          d="M22 6l-10 7L2 6"
                          stroke="currentColor"
                          strokeWidth="1.5"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        />
                      </svg>
                    </a>
                  </motion.div>
                </div>
                </div>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
};

export default AboutEthosOverlay;
