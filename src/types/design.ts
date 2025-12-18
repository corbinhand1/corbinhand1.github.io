/**
 * TypeScript Types for Nebula Creative Components
 * Provides type safety and better autocomplete
 */

export interface StageManagerProps {
  clockMs: number;
  announce: (msg: string) => void;
  isMobile: boolean;
}

export interface ConfettiButtonProps {
  onEffectChange: (effect: ConfettiEffect) => void;
  currentEffect: ConfettiEffect;
  disabled?: boolean;
}

export interface StickyNoteProps {
  text: string;
  position?: 'bottom-right' | 'bottom-left' | 'top-right' | 'top-left';
  delay?: number;
}

export type ConfettiEffect = 'rain' | 'burst' | 'spiral' | 'fountain' | 'stars';

export interface PilePiece {
  x: number;
  y: number;
  vx: number;
  vy: number;
  color: string;
  shape: 'circle' | 'square' | 'star';
  size: number;
  rotation: number;
  rotationSpeed: number;
}

export interface CueLine {
  t: number;
  text: string;
}

export interface StageLog {
  timestamp: string;
  message: string;
}

export interface BrandColors {
  bgA: string;
  bgB: string;
  postit: string;
  ink: string;
  glass: string;
  border: string;
  glow: string;
}
