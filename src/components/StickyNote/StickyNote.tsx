import React from 'react';
import { motion } from 'framer-motion';
import { BRAND, STICKY_NOTE } from '../../config/design';
import type { StickyNoteProps } from '../../types/design';

/**
 * StickyNote Component
 * Displays a handwritten sticky note with realistic paper effects
 * 
 * Props:
 * - text: Text content to display on the sticky note
 * - pos: Position object with right, bottom, and optional rotation
 * - className: Additional CSS classes
 */
export const StickyNote: React.FC<{
  text: string;
  pos: { right: number; bottom: number; rot?: number };
  className?: string;
}> = ({ text, pos, className = "" }) => {
  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 220, damping: 18 }}
      style={{ 
        position: "fixed", 
        zIndex: 40, 
        pointerEvents: "none",
        right: pos.right, 
        bottom: pos.bottom, 
        transform: `rotate(${pos.rot ?? -2}deg)` 
      }}
      className={`sticky-note-mobile ${className}`}
    >
      <div
        className={`${STICKY_NOTE.font} sticky-note-content`}
        style={{
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
          fontWeight: 400,
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
          transform: `perspective(100px) rotateX(2deg) rotateY(1deg) rotate(${(pos.rot ?? -2) + 0.5}deg)`,
          // Natural paper feel
          border: "1px solid rgba(255,255,255,0.2)",
        }}
      >
        {text}
      </div>
    </motion.div>
  );
};

export default StickyNote;
