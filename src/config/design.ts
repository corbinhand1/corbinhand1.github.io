/**
 * Nebula Creative Design System
 * Centralized design tokens for easy editing and consistency
 */

export const BRAND = {
  bgA: "#0a0f15",
  bgB: "#0e1421", 
  postit: "#FFEB3B",
  ink: "#111111",
  glass: "rgba(255,255,255,0.06)",
  border: "rgba(255,255,255,0.12)",
  glow: "rgba(148, 197, 255, 0.25)",
} as const;

export const STAGE_MANAGER = {
  mobile: {
    width: 'w-stage-mobile',
    fontSize: 'text-mobile-xs',
    padding: 'p-mobile-sm',
  },
  tablet: {
    width: 'w-stage-tablet', 
    fontSize: 'text-mobile-sm',
    padding: 'p-mobile-md',
  },
  desktop: {
    width: 'w-stage-desktop',
    fontSize: 'text-mobile-base', 
    padding: 'p-mobile-lg',
  },
  container: 'stage-manager-mobile fixed top-16 right-2 z-50 bg-glass border border-glass backdrop-blur-glass rounded-2xl shadow-2xl font-system',
  title: 'text-mobile-sm font-semibold text-white m-0 leading-tight',
  log: 'text-mobile-xs leading-snug p-1 rounded text-slate-300 break-words',
  scroll: 'h-32 sm:h-36 md:h-40 overflow-y-auto overflow-x-hidden flex flex-col gap-1 bg-glass-light backdrop-blur-sm rounded-xl p-2',
} as const;

export const CONFETTI_BUTTON = {
  base: 'px-6 py-3 bg-gradient-to-r from-blue-500 to-purple-600 text-white font-medium rounded-lg shadow-lg hover:shadow-xl transition-all duration-300 transform hover:scale-105 active:scale-95',
  mobile: 'min-h-48px px-5 py-3 text-mobile-base font-semibold',
  inactive: 'px-6 py-3 bg-gray-600 text-gray-400 cursor-not-allowed font-medium rounded-lg shadow-lg transition-all duration-300',
  effects: {
    rain: { name: 'Rain', color: 'from-blue-400 to-blue-600' },
    burst: { name: 'Burst', color: 'from-red-400 to-red-600' },
    spiral: { name: 'Spiral', color: 'from-green-400 to-green-600' },
    fountain: { name: 'Fountain', color: 'from-purple-400 to-purple-600' },
    stars: { name: 'Stars', color: 'from-yellow-400 to-yellow-600' },
  },
} as const;

export const STICKY_NOTE = {
  mobile: {
    width: 'w-100px',
    height: 'h-100px', 
    fontSize: 'text-xs',
    padding: 'p-2',
    position: 'fixed bottom-20 right-2',
  },
  tablet: {
    width: 'w-120px',
    height: 'h-120px',
    fontSize: 'text-xs',
    padding: 'p-2.5',
    position: 'fixed bottom-24 right-3',
  },
  desktop: {
    width: 'w-140px',
    height: 'h-140px',
    fontSize: 'text-sm',
    padding: 'p-3',
    position: 'fixed bottom-28 right-4',
  },
  large: {
    width: 'w-160px',
    height: 'h-160px',
    fontSize: 'text-sm',
    padding: 'p-3.5',
    position: 'fixed bottom-32 right-5',
  },
  font: 'font-handwritten',
  colors: {
    background: '#FFEB3B',
    text: '#111111',
  },
} as const;

export const ANIMATIONS = {
  duration: {
    fast: 300,
    normal: 500,
    slow: 1000,
  },
  easing: {
    easeOut: 'cubic-bezier(0.25, 0.46, 0.45, 0.94)',
    easeInOut: 'cubic-bezier(0.42, 0, 0.58, 1)',
  },
} as const;

export const BREAKPOINTS = {
  mobile: 'max-width: 767px',
  tablet: 'min-width: 768px and max-width: 1023px', 
  desktop: 'min-width: 1024px',
} as const;
