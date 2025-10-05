/* 
  About/Ethos overlay — visually minimal, mobile-first, and accessible.
  - Desktop: gently fades in after 1.2s; sits bottom-left; hover/focus raises opacity.
  - Mobile: starts as a compact pill; tap/press expands to show the full blurb; tap close (×) returns to pill.
  - Remembers the user's choice (expanded/collapsed) for the session.
  - Respects reduced motion users.
  - No layout shift to your hero; it's an overlay with pointer-events isolated.

  Requirements:
    - React (Vite + React is fine)
    - TailwindCSS (recommended). If you're not using Tailwind, a plain CSS fallback is included below.

  Usage:
    1) Drop <AboutEthosOverlay /> near the end of your page (inside your app root so it can overlay the hero).
    2) Ensure the parent container has position: relative (Tailwind: "relative") OR rely on fixed positioning here.
    3) If you already have a very high z-index element, you can adjust z-[value] below.

  Text content is FINAL (no placeholders).
*/

import React from "react";

/** Small hook to respect reduced motion */
function usePrefersReducedMotion() {
  const [reduced, setReduced] = React.useState(false);
  React.useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const onChange = () => setReduced(mq.matches);
    onChange();
    mq.addEventListener?.("change", onChange);
    return () => mq.removeEventListener?.("change", onChange);
  }, []);
  return reduced;
}

export default function AboutEthosOverlay() {
  const prefersReducedMotion = usePrefersReducedMotion();

  // Session-persisted expand/collapse state
  const [expanded, setExpanded] = React.useState<boolean>(() => {
    const v = sessionStorage.getItem("about_ethos_expanded");
    return v === "1";
  });

  React.useEffect(() => {
    sessionStorage.setItem("about_ethos_expanded", expanded ? "1" : "0");
  }, [expanded]);

  // Delay initial reveal on first mount (desktop-like polish)
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => {
    if (prefersReducedMotion) {
      setMounted(true);
      return;
    }
    const t = setTimeout(() => setMounted(true), 1200);
    return () => clearTimeout(t);
  }, [prefersReducedMotion]);

  return (
    <div
      className={[
        // position & stacking
        "fixed left-4 bottom-4 z-[60]",
        // constrain width on larger screens
        "max-w-sm md:max-w-md",
        // initial appearance (fade-in)
        mounted ? "opacity-100" : "opacity-0",
        prefersReducedMotion ? "" : "transition-opacity duration-500 ease-out",
        // pointer handling (let only the card receive interactions)
        "pointer-events-none",
      ].join(" ")}
      aria-live="polite"
    >
      {/* Container that can accept pointer events */}
      <div className="pointer-events-auto">
        {/* Collapsed pill (mobile-first). Hidden when expanded */}
        <button
          type="button"
          onClick={() => setExpanded(true)}
          aria-expanded={expanded}
          aria-controls="about-ethos-panel"
          className={[
            expanded ? "hidden" : "flex",
            // layout
            "items-center gap-2",
            // visuals
            "rounded-full px-3 py-2",
            // Background with subtle glass effect, respects dark/light
            "backdrop-blur-md bg-black/35 dark:bg-black/40 text-white",
            "ring-1 ring-white/15 hover:ring-white/25",
            // typography
            "text-sm md:text-[0.95rem] leading-tight",
            // motion
            prefersReducedMotion ? "" : "transition-all duration-200",
            // subtle shadow
            "shadow-lg",
          ].join(" ")}
        >
          <span className="inline-block w-2 h-2 rounded-full bg-white/80" aria-hidden="true" />
          <span className="font-medium">About Nebula Creative</span>
        </button>

        {/* Expanded card */}
        <section
          id="about-ethos-panel"
          aria-label="About Nebula Creative"
          className={[
            expanded ? "opacity-100 translate-y-0" : "pointer-events-none opacity-0 translate-y-2",
            // position & sizing
            "mt-0",
            // card visuals
            "rounded-2xl p-4 md:p-5",
            "backdrop-blur-md bg-black/45 dark:bg-black/55 text-white",
            "ring-1 ring-white/15 hover:ring-white/25",
            "shadow-2xl",
            // motion
            prefersReducedMotion ? "" : "transition-all duration-250 ease-out",
          ].join(" ")}
        >
          {/* Header row */}
          <div className="flex items-start justify-between gap-4">
            <h2 className="text-base md:text-lg font-semibold tracking-wide">
              Nebula Creative
            </h2>
            <button
              type="button"
              onClick={() => setExpanded(false)}
              className={[
                "rounded-full p-1 -m-1",
                "hover:bg-white/10 focus:bg-white/10 focus:outline-none focus:ring-2 focus:ring-white/30",
                prefersReducedMotion ? "" : "transition-colors",
              ].join(" ")}
              aria-label="Close about panel"
              title="Close"
            >
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                role="img"
                aria-hidden="true"
                className="block"
              >
                <path
                  d="M18.3 5.7a1 1 0 0 0-1.4-1.4L12 9.17 7.1 4.3A1 1 0 1 0 5.7 5.7l4.88 4.9-4.88 4.88a1 1 0 1 0 1.4 1.42L12 12.99l4.9 4.91a1 1 0 0 0 1.4-1.42L13.41 10.6l4.89-4.9Z"
                  fill="currentColor"
                />
              </svg>
            </button>
          </div>

          {/* Ethos text — concise, cinematic, final */}
          <p className="mt-2 text-sm md:text-[0.95rem] leading-relaxed text-white/90">
            Led by <strong>Corbin Hand</strong>, Nebula Creative provides{" "}
            <strong>stage management</strong>, <strong>show calling</strong>,{" "}
            <strong>production management</strong>, and <strong>tour management</strong> for
            live <strong>music</strong> and <strong>corporate events</strong> worldwide. Two decades
            producing concerts, tours, and large-scale shows — delivered with calm precision, tight cueing,
            and on-brand execution.
          </p>

          {/* Micro footer actions (optional) */}
          <div className="mt-3 flex items-center gap-3">
            <a
              href="mailto:corbin@nebulacreative.org"
              className={[
                "inline-flex items-center rounded-full px-3 py-1.5",
                "bg-white/90 text-black hover:bg-white",
                "text-sm font-medium",
                prefersReducedMotion ? "" : "transition-colors",
              ].join(" ")}
            >
              Contact
            </a>
            <span className="text-xs text-white/60 select-none">Worldwide • Music & Corporate</span>
          </div>
        </section>
      </div>
    </div>
  );
}
