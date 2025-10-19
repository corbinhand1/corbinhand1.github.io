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
            initial={{ opacity: 0, scale: 0.85, y: 30, rotateX: -15 }}
            animate={{ opacity: 1, scale: 1, y: 0, rotateX: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20, rotateX: 5 }}
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
            {/* Liquid Glass Floating Window */}
            <div className="relative w-80 sm:w-96 md:w-[420px] max-h-[500px] overflow-hidden">
              {/* Premium Glass Morphism Background */}
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
                <div className="relative z-10">
                {/* Window Header */}
                <motion.div 
                  className="flex items-center justify-between p-4 border-b border-white/10"
                  initial={{ opacity: 0, y: -10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.2, duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
                >
                  <h2 id="about-title" className="text-xl font-light text-white tracking-wide">
                    About Nebula Creative
                  </h2>
                  <motion.button
                    onClick={() => setIsOpen(false)}
                    className="w-8 h-8 rounded-full bg-white/5 hover:bg-white/15 border border-white/10 hover:border-white/20 transition-all duration-300 flex items-center justify-center group"
                    aria-label="Close about window"
                    initial={{ opacity: 0, scale: 0.8 }}
                    animate={{ opacity: 1, scale: 1 }}
                    transition={{ delay: 0.3, duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
                    whileHover={{ 
                      scale: 1.1, 
                      rotate: 90,
                      transition: { duration: 0.2, ease: [0.16, 1, 0.3, 1] }
                    }}
                    whileTap={{ scale: 0.9 }}
                  >
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      className="text-white group-hover:text-white/80 transition-colors duration-200"
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
                </motion.div>

                {/* Window Content */}
                <div className="p-6 space-y-6 max-h-[400px] overflow-y-auto">
                  {/* Main Content */}
                  <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.3, duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
                  >
                    <p className="text-sm leading-relaxed text-white/95 font-light">
                      Nebula Creative is led by <motion.span 
                        className="text-white font-medium"
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={{ delay: 0.5, duration: 0.5 }}
                      >Corbin Hand</motion.span> — 
                      a world-traveled stage manager, show caller, and production manager with over two decades 
                      in live entertainment.
                    </p>
                  </motion.div>

                  <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.4, duration: 0.7, ease: [0.16, 1, 0.3, 1] }}
                  >
                    <p className="text-sm leading-relaxed text-white/95 font-light">
                      From global concert tours to high-end corporate experiences, 
                      Nebula Creative delivers flawless execution where precision and timing define success.
                    </p>
                  </motion.div>

                  {/* Accent Line */}
                  <motion.div
                    className="h-px bg-gradient-to-r from-transparent via-white/40 to-transparent"
                    initial={{ scaleX: 0, opacity: 0 }}
                    animate={{ scaleX: 1, opacity: 1 }}
                    transition={{ delay: 0.5, duration: 1.2, ease: [0.16, 1, 0.3, 1] }}
                  />

                  {/* Location */}
                  <motion.div
                    initial={{ opacity: 0, y: 15 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.6, duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
                  >
                    <p className="text-xs text-white/80 font-light tracking-wider uppercase">
                      Based in Nashville — Operating Worldwide
                    </p>
                  </motion.div>

                  {/* Contact CTA */}
                  <motion.div
                    initial={{ opacity: 0, y: 20, scale: 0.9 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    transition={{ delay: 0.7, duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
                  >
                    <motion.a
                      href="mailto:corbin@nebulacreative.org"
                      className="inline-flex items-center px-5 py-3 bg-white/5 hover:bg-white/15 border border-white/20 hover:border-white/30 rounded-full text-white transition-all duration-300 group"
                      whileHover={{ 
                        scale: 1.05, 
                        y: -2,
                        transition: { duration: 0.2, ease: [0.16, 1, 0.3, 1] }
                      }}
                      whileTap={{ scale: 0.98 }}
                    >
                      <span className="text-sm font-medium tracking-wide">Contact</span>
                      <motion.svg
                        width="16"
                        height="16"
                        viewBox="0 0 24 24"
                        fill="none"
                        className="ml-2 text-white group-hover:text-white/90 transition-colors duration-200"
                        whileHover={{ rotate: 15 }}
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
                      </motion.svg>
                    </motion.a>
                  </motion.div>
                </div>
              </div>
            </div>            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
};

export default AboutEthosOverlay;
