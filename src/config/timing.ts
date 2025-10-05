/**
 * Animation and Timing Configuration
 * Centralized timing values for consistent animations
 */

export const CUE_LINES = [
  { t: 0, text: "Standby Lights." },
  { t: 900, text: "Standby Video." },
  { t: 1800, text: "Standby Audio." },
  { t: 2800, text: "Standby Confetti." },
  { t: 4000, text: "Go Lights!" },
  { t: 5800, text: "Go Video!" },
  { t: 7600, text: "Go Audio!" },
  { t: 9000, text: "GO Confetti!" },
] as const;

export const STAGE_MANAGER_TIMING = {
  logRetention: 10000, // How long logs stay visible (ms)
  cueDelay: 100, // Delay before showing cue (ms)
} as const;

export const CONFETTI_TIMING = {
  duration: 3000, // How long confetti falls (ms)
  cleanupDelay: 5000, // When to clean up confetti pieces (ms)
  buttonCooldown: 1000, // Cooldown between button presses (ms)
} as const;

export const STICKY_NOTE_TIMING = {
  fadeIn: 500,
  fadeOut: 300,
  displayDuration: 3000,
} as const;
