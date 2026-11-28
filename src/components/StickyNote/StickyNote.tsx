import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { BRAND, STICKY_NOTE } from '../../config/design';

/**
 * StickyNote — a handwritten note in the corner. Click/tap it to act on it.
 * The outer wrapper is positioned by CSS (.sticky-note-mobile uses !important
 * rules), so all motion happens on the inner layer.
 */
export const StickyNote: React.FC<{
  text: string;
  noteKey: number | string;
  onActivate: () => void;
  hint?: string;
  rot?: number;
}> = ({ text, noteKey, onActivate, hint, rot = 8 }) => {
  return (
    <div
      className="sticky-note-mobile"
      role="button"
      tabIndex={0}
      aria-label={`Sticky note: ${text}. ${hint ?? ''}`}
      title={hint}
      onClick={onActivate}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          e.stopPropagation();
          onActivate();
        }
      }}
      style={{ position: 'fixed', zIndex: 40, pointerEvents: 'auto', cursor: 'pointer', outline: 'none' }}
    >
      <AnimatePresence mode="popLayout">
        <motion.div
          key={noteKey}
          initial={{ opacity: 0, y: 30, rotate: rot + 12, scale: 0.9 }}
          animate={{ opacity: 1, y: 0, rotate: rot, scale: 1 }}
          exit={{ opacity: 0, y: -60, x: 40, rotate: rot + 40, scale: 0.85, transition: { duration: 0.35, ease: 'easeIn' } }}
          whileHover={{ rotate: rot - 3, scale: 1.05, y: -3 }}
          whileTap={{ scale: 0.95 }}
          transition={{ type: 'spring', stiffness: 260, damping: 18 }}
          style={{ transformOrigin: '50% 0%' }}
        >
          <div
            className={`${STICKY_NOTE.font} sticky-note-content`}
            style={{
              backgroundColor: '#FFF59D',
              color: BRAND.ink,
              boxShadow: `
                0 1px 3px rgba(0,0,0,0.12),
                0 1px 2px rgba(0,0,0,0.24),
                0 4px 8px rgba(0,0,0,0.15),
                0 8px 16px rgba(0,0,0,0.1),
                inset 0 1px 0 rgba(255,255,255,0.3)
              `,
              borderRadius: 4,
              fontWeight: 400,
              letterSpacing: 0.2,
              textShadow: '0.5px 0.5px 0px rgba(0,0,0,0.1)',
              backgroundImage: `
                radial-gradient(circle at 20% 30%, rgba(255,255,255,0.1) 0%, transparent 50%),
                radial-gradient(circle at 80% 70%, rgba(255,255,255,0.05) 0%, transparent 50%),
                linear-gradient(45deg, transparent 30%, rgba(255,255,255,0.1) 50%, transparent 70%)
              `,
              filter: 'contrast(1.1) brightness(1.05)',
              transform: 'perspective(100px) rotateX(2deg) rotateY(1deg)',
              border: '1px solid rgba(255,255,255,0.2)',
              position: 'relative',
            }}
          >
            {text}
            {hint && (
              <span
                className="absolute right-1.5 bottom-1 text-[0.7em] opacity-50 select-none"
                aria-hidden
              >
                {hint === 'Sweep it up' ? '🧹 tap' : 'tap'}
              </span>
            )}
          </div>
        </motion.div>
      </AnimatePresence>
    </div>
  );
};

export default StickyNote;
