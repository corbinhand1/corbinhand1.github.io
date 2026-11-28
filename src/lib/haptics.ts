/**
 * haptics — a buzz on button presses, on phones only.
 *
 * Android (Chrome etc.): the Vibration API, with different lengths per kind.
 * iPhone: Safari has no vibration API, but iOS 18+ plays a system haptic tick
 * when a native switch is toggled during a tap. We keep one hidden switch and
 * toggle it. (One fixed tick: no patterns on iOS.)
 * Must be called from inside the tap/click handler.
 */

type Kind = 'tap' | 'press' | 'thump' | 'heavy';

const PATTERNS: Record<Kind, number | number[]> = {
  tap: 8,                 // small UI buttons, sticky note, cover lift
  press: 16,              // GO
  thump: 35,              // LAUNCH
  heavy: [45, 35, 70],    // MEGA EXPLOSION / fire marshal lockout
};

const isTouch = () =>
  typeof window !== 'undefined' && window.matchMedia('(pointer: coarse)').matches;

let iosLabel: HTMLLabelElement | null = null;
function iosTick() {
  if (!iosLabel) {
    iosLabel = document.createElement('label');
    iosLabel.setAttribute('aria-hidden', 'true');
    iosLabel.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;opacity:0;pointer-events:none;';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.setAttribute('switch', '');
    input.tabIndex = -1;
    iosLabel.appendChild(input);
    document.body.appendChild(iosLabel);
  }
  iosLabel.click();
}

export function haptic(kind: Kind = 'tap') {
  if (!isTouch()) return;
  try {
    if (typeof navigator.vibrate === 'function') {
      navigator.vibrate(PATTERNS[kind]);
    } else {
      iosTick();
    }
  } catch {
    /* no haptics available */
  }
}
