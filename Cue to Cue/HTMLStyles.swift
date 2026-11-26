//
//  HTMLStyles.swift
//  Cue to Cue
//
//  Styles for the LAN viewer (the page phones, tablets and laptops open at
//  http://<mac>:8080). Mobile first: cue cards on phones, a table from 760 px.
//  Colors match the Mac app: green LIVE, yellow NEXT, seven-segment clocks.
//

import Foundation

struct HTMLStyles {
    static let content = #"""
@font-face {
    font-family: "Digital7";
    src: url("/digital-7-mono.ttf") format("truetype");
    font-display: swap;
}

:root {
    color-scheme: dark;
    --bg: #0b0f17;
    --surface: #131a26;
    --surface-2: #1a2232;
    --surface-3: #232d40;
    --line: rgba(148, 163, 184, 0.16);
    --line-strong: rgba(148, 163, 184, 0.32);
    --text: #f1f5f9;
    --text-2: #a9b4c6;
    --text-3: #8591a5;
    --accent: #0a84ff;
    --live: #30d158;
    --live-ink: #04210d;
    --next: #ffd60a;
    --next-ink: #2a2300;
    --warn: #ff9f0a;
    --danger: #ff453a;
    --clock-time: #4da3ff;
    --clock-count: #ff6b57;
    --clock-to: #ff8f6b;
    --live-row: rgba(48, 209, 88, 0.16);
    --next-row: rgba(255, 214, 10, 0.08);
    --shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
    --radius: 14px;
    --radius-sm: 10px;
    --fs: 16px;
    --safe-top: env(safe-area-inset-top, 0px);
    --safe-bottom: env(safe-area-inset-bottom, 0px);
    --safe-left: env(safe-area-inset-left, 0px);
    --safe-right: env(safe-area-inset-right, 0px);
    --ease: cubic-bezier(0.2, 0.8, 0.2, 1);
}

:root[data-theme="light"] {
    color-scheme: light;
    --bg: #f3f5f9;
    --surface: #ffffff;
    --surface-2: #eef1f6;
    --surface-3: #e3e8f0;
    --line: rgba(15, 23, 42, 0.12);
    --line-strong: rgba(15, 23, 42, 0.24);
    --text: #0f172a;
    --text-2: #3e4a5f;
    --text-3: #5b667a;
    --accent: #0062cc;
    --live: #1a9c3f;
    --live-ink: #ffffff;
    --next: #a77a00;
    --next-ink: #ffffff;
    --warn: #b25e00;
    --danger: #c9271d;
    --clock-time: #0062cc;
    --clock-count: #c63d2b;
    --clock-to: #b0442c;
    --live-row: rgba(26, 156, 63, 0.14);
    --next-row: rgba(167, 122, 0, 0.10);
    --shadow: 0 12px 32px rgba(15, 23, 42, 0.18);
}

:root[data-size="s"] { --fs: 14px; }
:root[data-size="m"] { --fs: 16px; }
:root[data-size="l"] { --fs: 19px; }
:root[data-size="xl"] { --fs: 22px; }

* { box-sizing: border-box; }

html {
    -webkit-text-size-adjust: 100%;
    text-size-adjust: 100%;
    background: var(--bg);
}

body {
    margin: 0;
    min-height: 100dvh;
    background: var(--bg);
    color: var(--text);
    font: 400 var(--fs)/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
    -webkit-tap-highlight-color: transparent;
}

button, input, select, textarea { font: inherit; color: inherit; }
button { cursor: pointer; touch-action: manipulation; }
:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; border-radius: 8px; }
.sr-only {
    position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
    overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0;
}
svg.icon { width: 20px; height: 20px; flex: none; stroke: currentColor; fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }

/* ---------- Top bar ---------- */

/* Top bar and clocks stay pinned while the cue list scrolls. */
.pinned {
    position: sticky;
    top: 0;
    z-index: 20;
    padding-bottom: 10px;
    background: color-mix(in srgb, var(--bg) 90%, transparent);
    -webkit-backdrop-filter: saturate(160%) blur(14px);
    backdrop-filter: saturate(160%) blur(14px);
    border-bottom: 1px solid var(--line);
}
:root[data-clocks="off"] .pinned { padding-bottom: 0; }

.topbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: calc(8px + var(--safe-top)) calc(12px + var(--safe-right)) 6px calc(12px + var(--safe-left));
}

.stack-button {
    flex: 1 1 auto;
    min-width: 0;
    min-height: 44px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 4px 10px 4px 6px;
    border: 0;
    border-radius: var(--radius-sm);
    background: transparent;
    text-align: left;
}
.stack-button:hover { background: var(--surface-2); }
.stack-button .titles { min-width: 0; display: flex; flex-direction: column; }
.stack-name {
    font-size: 1.05em;
    font-weight: 700;
    letter-spacing: -0.01em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.stack-mode { font-size: 0.78em; color: var(--text-2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.stack-mode.browsing { color: var(--warn); }
.stack-button .chev { color: var(--text-3); }

.status-pill {
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 7px;
    min-height: 32px;
    padding: 4px 11px;
    border-radius: 999px;
    background: var(--surface-2);
    border: 1px solid var(--line);
    font-size: 0.78em;
    font-weight: 600;
    white-space: nowrap;
}
.status-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--text-3); flex: none; }
.status-pill[data-state="live"] .status-dot { background: var(--live); box-shadow: 0 0 0 3px color-mix(in srgb, var(--live) 25%, transparent); }
.status-pill[data-state="polling"] .status-dot { background: var(--live); }
.status-pill[data-state="connecting"] .status-dot { background: var(--warn); animation: pulse 1.2s ease-in-out infinite; }
.status-pill[data-state="offline"] { color: var(--danger); border-color: color-mix(in srgb, var(--danger) 40%, transparent); }
.status-pill[data-state="offline"] .status-dot { background: var(--danger); }
@keyframes pulse { 50% { opacity: 0.35; } }

.icon-button {
    flex: none;
    display: inline-grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border: 0;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--text-2);
}
.icon-button:hover { background: var(--surface-2); color: var(--text); }
.icon-button[aria-pressed="true"], .icon-button.signed-in { color: var(--accent); }

/* ---------- Clocks ---------- */

.clocks {
    display: grid;
    /* Time of day has ~9 characters to the countdowns' 5, so it gets a wider
       tile and all three clocks end up with the same digit size. */
    grid-template-columns: minmax(0, 1.6fr) minmax(0, 1fr) minmax(0, 1fr);
    gap: 8px;
    padding: 4px calc(12px + var(--safe-right)) 0 calc(12px + var(--safe-left));
}
.clock {
    min-width: 0;
    container-type: inline-size;
    overflow: hidden;
    padding: 10px 12px 12px;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: var(--radius);
}
.clock-label {
    display: flex;
    justify-content: space-between;
    gap: 6px;
    font-size: 0.68em;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--text-2);
    white-space: nowrap;
    overflow: hidden;
}
.clock-label .meta { font-weight: 600; letter-spacing: 0.02em; text-transform: none; color: var(--text-3); overflow: hidden; text-overflow: ellipsis; }
.clock-value {
    margin-top: 2px;
    font-family: "Digital7", ui-monospace, "SF Mono", Menlo, monospace;
    font-variant-numeric: tabular-nums;
    /* Fill the tile: --chars is set from the text shown (JS). */
    font-size: clamp(1.05rem, calc(100cqi / (var(--chars, 8) * 0.5)), 3.6rem);
    line-height: 1;
    letter-spacing: 0.02em;
    white-space: nowrap;
}
.clock-time .clock-value { color: var(--clock-time); }
.clock-count .clock-value { color: var(--clock-count); }
.clock-to .clock-value { color: var(--clock-to); }
.clock-value .ampm { font-size: 0.42em; margin-left: 0.15em; }
.clock[data-run="paused"] .clock-value, .clock[data-run="idle"] .clock-value { opacity: 0.55; }
.clock[data-urgency="soon"] .clock-value { color: var(--warn); }
.clock[data-urgency="zero"] .clock-value { color: var(--danger); }
.clock[data-urgency="zero"] { border-color: color-mix(in srgb, var(--danger) 55%, transparent); }

/* ---------- Now / Next ---------- */

.nownext {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 8px;
    padding: 10px calc(12px + var(--safe-right)) 0 calc(12px + var(--safe-left));
}
.cue-card {
    position: relative;
    min-width: 0;
    padding: 12px 14px 12px 18px;
    border-radius: var(--radius);
    background: var(--surface);
    border: 1px solid var(--line);
    overflow: hidden;
}
.cue-card::before {
    content: "";
    position: absolute;
    inset: 0 auto 0 0;
    width: 5px;
    background: var(--text-3);
}
.cue-card.live { background: linear-gradient(90deg, var(--live-row), transparent 70%), var(--surface); }
.cue-card.live::before { background: var(--live); }
.cue-card.next::before { background: var(--next); }
.cue-card.empty { opacity: 0.8; }
.card-head { display: flex; align-items: center; gap: 8px; margin-bottom: 4px; }
.chip {
    white-space: nowrap;
    display: inline-flex;
    align-items: center;
    min-height: 20px;
    padding: 1px 7px;
    border-radius: 6px;
    font-size: 0.66em;
    font-weight: 800;
    letter-spacing: 0.06em;
}
.chip.live { background: var(--live); color: var(--live-ink); }
.chip.next { background: var(--next); color: var(--next-ink); }
.card-num { font-weight: 700; color: var(--text-2); font-variant-numeric: tabular-nums; }
.card-timer { margin-left: auto; font-weight: 700; color: var(--clock-count); font-variant-numeric: tabular-nums; }
.card-desc { font-size: 1.12em; font-weight: 650; line-height: 1.3; overflow-wrap: anywhere; }
.cue-card.next .card-desc { font-size: 1em; font-weight: 600; }
.card-depts { display: flex; flex-wrap: wrap; gap: 4px 12px; margin-top: 6px; font-size: 0.82em; color: var(--text-2); }
.card-depts b { color: var(--text-3); font-weight: 600; margin-right: 4px; }
.card-note { color: var(--text-2); }
.card-action {
    margin-top: 8px;
    min-height: 36px;
    padding: 6px 12px;
    border-radius: 9px;
    border: 1px solid var(--line-strong);
    background: var(--surface-2);
    font-weight: 600;
}

/* ---------- Offline banner ---------- */

.banner {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 10px calc(12px + var(--safe-right)) 0 calc(12px + var(--safe-left));
    padding: 10px 14px;
    border-radius: var(--radius-sm);
    border: 1px solid color-mix(in srgb, var(--danger) 45%, transparent);
    background: color-mix(in srgb, var(--danger) 12%, var(--surface));
    font-size: 0.88em;
}
.banner[hidden] { display: none; }

/* ---------- Cue list ---------- */

.cues {
    padding: 10px calc(12px + var(--safe-right)) calc(96px + var(--safe-bottom)) calc(12px + var(--safe-left));
}
.cues.stale .cue-table { opacity: 0.72; }

/* Phones: each cue is a card (the table becomes plain blocks). */
.cue-table { display: block; width: 100%; }
.cue-table colgroup, .cue-table thead { display: none; }
.cue-table tbody { display: grid; gap: 6px; }
.cue-row {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: baseline;
    gap: 2px 10px;
    padding: 11px 12px 11px 16px;
    position: relative;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: var(--radius-sm);
    scroll-margin: calc(var(--pinned-h, 140px) + 8px) 0 100px;
}
.cue-row::before {
    content: "";
    position: absolute;
    inset: 8px auto 8px 0;
    width: 4px;
    border-radius: 0 3px 3px 0;
    background: transparent;
}
.cue-row td { padding: 0; min-width: 0; overflow-wrap: anywhere; }
.cue-row .c-state { grid-column: 3; grid-row: 1; justify-self: end; }
.cue-row .c-num { grid-column: 1; grid-row: 1; font-weight: 700; color: var(--text-2); font-variant-numeric: tabular-nums; }
.cue-row .c-num:empty { display: none; }
.cue-row .c-desc { grid-column: 2; grid-row: 1; font-weight: 600; }
.cue-row .c-num:empty + .c-desc { grid-column: 1 / 3; }
.cue-row .c-dept {
    grid-column: 1 / -1;
    font-size: 0.84em;
    color: var(--text-2);
}
.cue-row .c-dept::before {
    content: attr(data-label);
    margin-right: 6px;
    color: var(--text-3);
    font-weight: 600;
}
.cue-row .c-dept.is-empty, .cue-row .c-timer.is-empty { display: none; }
.cue-row .c-timer {
    grid-column: 1 / -1;
    font-size: 0.84em;
    font-weight: 700;
    color: var(--clock-count);
    font-variant-numeric: tabular-nums;
}
.cue-row .c-timer::before { content: "Timer "; color: var(--text-3); font-weight: 600; }

.cue-row.is-live { background: linear-gradient(90deg, var(--live-row), var(--surface) 75%); border-color: color-mix(in srgb, var(--live) 45%, transparent); }
.cue-row.is-live::before { background: var(--live); }
.cue-row.is-next::before { background: var(--next); }
.cue-row.is-next { background: linear-gradient(90deg, var(--next-row), var(--surface) 70%); }
.cue-row.is-struck td { text-decoration: line-through; color: var(--text-3) !important; }
.cue-row.is-struck { opacity: 0.6; }
.cue-row.has-kw td:not(.c-state) { color: var(--kw); }
:root[data-theme="light"] .cue-row.has-kw td:not(.c-state) { color: color-mix(in srgb, var(--kw) 62%, black); }
:root[data-keywords="off"] .cue-row.has-kw td:not(.c-state) { color: inherit; }
.col-hidden { display: none !important; }

td.can-edit { cursor: text; border-radius: 6px; }
td.can-edit:hover { background: var(--surface-3); }
:root[data-editing="on"] td.can-edit { text-decoration: underline dotted var(--text-3); text-underline-offset: 4px; }

.empty-state {
    margin: 32px auto;
    max-width: 420px;
    text-align: center;
    color: var(--text-2);
}
.empty-state h2 { margin: 0 0 6px; color: var(--text); font-size: 1.1em; }

/* Side-by-side Live/Next from tablet width; cards in two columns until the table takes over. */
@media (min-width: 700px) {
    .nownext { grid-template-columns: minmax(0, 1.35fr) minmax(0, 1fr); }
}
@media (min-width: 700px) and (max-width: 1023px) {
    .cue-table tbody { grid-template-columns: repeat(2, minmax(0, 1fr)); align-items: start; }
}

/* Table layout on landscape tablets and laptops */
@media (min-width: 1024px) {
    .cues { padding-bottom: calc(80px + var(--safe-bottom)); }
    .table-wrap {
        border: 1px solid var(--line);
        border-radius: var(--radius);
        background: var(--surface);
    }
    .cue-table th:first-child { border-top-left-radius: var(--radius); }
    .cue-table th:last-child { border-top-right-radius: var(--radius); }
    /* Auto layout: the Mac's widths are hints, and no column gets narrower
       than its longest word (nothing breaks mid-word). */
    .cue-table { display: table; border-collapse: separate; border-spacing: 0; table-layout: auto; width: 100%; }
    .cue-table colgroup { display: table-column-group; }
    .cue-table thead { display: table-header-group; }
    .cue-table tbody { display: table-row-group; }
    .cue-table th {
        position: sticky;
        top: var(--pinned-h, 0px);
        z-index: 1;
        padding: 10px 10px;
        text-align: left;
        font-size: 0.68em;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--text-2);
        background: var(--surface-2);
        border-bottom: 1px solid var(--line-strong);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .cue-row {
        display: table-row;
        padding: 0;
        border: 0;
        border-radius: 0;
        background: transparent;
    }
    .cue-row::before { display: none; }
    .cue-row td {
        display: table-cell;
        overflow-wrap: normal;
        word-break: normal;
        padding: 10px 10px;
        vertical-align: top;
        border-bottom: 1px solid var(--line);
        font-size: 1em;
        color: var(--text);
    }
    .cue-row .c-dept::before, .cue-row .c-timer::before { content: none; }
    .cue-row .c-dept.is-empty, .cue-row .c-timer.is-empty { display: table-cell; }
    .cue-row .c-dept, .cue-row .c-timer { font-size: 1em; }
    .cue-row .c-num { color: var(--text); white-space: nowrap; }
    .cue-row .c-timer { white-space: nowrap; }
    .cue-row .c-num:empty { display: table-cell; }
    .cue-row .c-state { padding-left: 12px; box-shadow: inset 4px 0 0 transparent; }
    .cue-row.is-live td { background: var(--live-row); font-weight: 650; }
    .cue-row.is-live .c-state { box-shadow: inset 4px 0 0 var(--live); }
    .cue-row.is-next td { background: var(--next-row); }
    .cue-row.is-next .c-state { box-shadow: inset 4px 0 0 var(--next); }
    .cue-row.is-live, .cue-row.is-next { background: transparent; }
    .cue-row:last-child td { border-bottom: 0; }
}

/* ---------- Floating "back to live" ---------- */

.jump-live {
    position: fixed;
    left: 50%;
    bottom: calc(18px + var(--safe-bottom));
    z-index: 15;
    transform: translateX(-50%);
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-height: 48px;
    padding: 10px 18px;
    border: 0;
    border-radius: 999px;
    background: var(--live);
    color: var(--live-ink);
    font-weight: 700;
    box-shadow: var(--shadow);
    transition: transform 0.2s var(--ease), opacity 0.2s var(--ease);
}
.jump-live[hidden] { display: inline-flex; opacity: 0; pointer-events: none; transform: translate(-50%, 16px); }

/* ---------- Sheets (dialogs) ---------- */

dialog.sheet {
    width: min(560px, 100vw);
    max-width: 100vw;
    max-height: min(86dvh, 760px);
    margin: auto auto 0;
    padding: 0;
    border: 1px solid var(--line);
    border-radius: 20px 20px 0 0;
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow);
    overflow: hidden;
}
dialog.sheet[open] { display: flex; flex-direction: column; animation: sheet-in 0.26s var(--ease); }
dialog.sheet::backdrop { background: rgba(3, 6, 12, 0.55); }
@keyframes sheet-in { from { transform: translateY(24px); opacity: 0; } }
@media (min-width: 620px) {
    dialog.sheet { margin: auto; border-radius: 20px; }
}
.sheet-head {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 10px 10px 20px;
    border-bottom: 1px solid var(--line);
}
.sheet-head h2 { margin: 0; flex: 1; font-size: 1.1em; }
.sheet-body { padding: 14px 20px calc(20px + var(--safe-bottom)); overflow-y: auto; overscroll-behavior: contain; }
.sheet-foot {
    display: flex;
    justify-content: flex-end;
    gap: 10px;
    padding: 12px 20px calc(14px + var(--safe-bottom));
    border-top: 1px solid var(--line);
}
.group-label {
    margin: 18px 0 8px;
    font-size: 0.72em;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--text-2);
}
.group-label:first-child { margin-top: 2px; }
.help { margin: 6px 0 0; font-size: 0.82em; color: var(--text-2); }

.list { display: grid; gap: 2px; border-radius: var(--radius-sm); overflow: hidden; background: var(--line); border: 1px solid var(--line); }
.list-item {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 50px;
    padding: 10px 14px;
    background: var(--surface-2);
    border: 0;
    width: 100%;
    text-align: left;
}
.list-item:hover { background: var(--surface-3); }
.list-item .grow { flex: 1; min-width: 0; }
.list-item .sub { display: block; font-size: 0.8em; color: var(--text-2); }
.list-item .check { color: var(--accent); visibility: hidden; }
.list-item[aria-checked="true"] .check { visibility: visible; }
.list-item[aria-checked="true"] { font-weight: 650; }

.segmented {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    gap: 4px;
    padding: 4px;
    border-radius: 12px;
    background: var(--surface-2);
    border: 1px solid var(--line);
}
.segmented button {
    min-height: 40px;
    border: 0;
    border-radius: 9px;
    background: transparent;
    font-weight: 600;
    color: var(--text-2);
}
.segmented button[aria-pressed="true"] { background: var(--surface); color: var(--text); box-shadow: 0 1px 4px rgba(0, 0, 0, 0.25); }

.toggle-row {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 50px;
    padding: 8px 14px;
    background: var(--surface-2);
}
.toggle-row .grow { flex: 1; min-width: 0; }
.toggle-row .sub { display: block; font-size: 0.8em; color: var(--text-2); }
.switch { position: relative; flex: none; width: 51px; height: 31px; }
.switch input { position: absolute; inset: 0; opacity: 0; margin: 0; cursor: pointer; }
.switch span {
    position: absolute;
    inset: 0;
    border-radius: 999px;
    background: var(--surface-3);
    border: 1px solid var(--line-strong);
    transition: background 0.2s var(--ease);
    pointer-events: none;
}
.switch span::after {
    content: "";
    position: absolute;
    top: 2px;
    left: 2px;
    width: 25px;
    height: 25px;
    border-radius: 50%;
    background: #fff;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
    transition: transform 0.2s var(--ease);
}
.switch input:checked + span { background: var(--live); border-color: transparent; }
.switch input:checked + span::after { transform: translateX(20px); }
.switch input:focus-visible + span { outline: 3px solid var(--accent); outline-offset: 2px; }

.field { display: grid; gap: 6px; margin-bottom: 14px; }
.field label { font-size: 0.85em; font-weight: 600; color: var(--text-2); }
.field input, .field textarea {
    width: 100%;
    min-height: 46px;
    padding: 10px 12px;
    border-radius: 10px;
    border: 1px solid var(--line-strong);
    background: var(--bg);
    font-size: max(16px, 1em);
}
.field textarea { min-height: 96px; resize: vertical; line-height: 1.4; }
.input-with-button { position: relative; }
.input-with-button input { padding-right: 76px; }
.input-with-button button {
    position: absolute;
    right: 6px;
    top: 50%;
    transform: translateY(-50%);
    min-height: 34px;
    padding: 4px 10px;
    border: 0;
    border-radius: 8px;
    background: var(--surface-3);
    font-size: 0.82em;
    font-weight: 600;
}
.form-error {
    margin: 0 0 12px;
    padding: 10px 12px;
    border-radius: 10px;
    background: color-mix(in srgb, var(--danger) 14%, var(--surface));
    border: 1px solid color-mix(in srgb, var(--danger) 40%, transparent);
    font-size: 0.88em;
}
.form-error[hidden] { display: none; }

.btn {
    min-height: 44px;
    padding: 10px 18px;
    border-radius: 11px;
    border: 1px solid var(--line-strong);
    background: var(--surface-2);
    font-weight: 650;
}
.btn.primary { background: var(--accent); border-color: transparent; color: #fff; }
.btn:disabled { opacity: 0.5; cursor: default; }
.btn.danger-text { color: var(--danger); }

.account-card {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border-radius: var(--radius-sm);
    background: var(--surface-2);
    border: 1px solid var(--line);
}
.avatar {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--accent) 25%, var(--surface-3));
    font-weight: 800;
}

/* ---------- Toast ---------- */

.toast {
    position: fixed;
    left: 50%;
    top: calc(68px + var(--safe-top));
    z-index: 50;
    transform: translateX(-50%);
    max-width: min(92vw, 440px);
    padding: 10px 16px;
    border-radius: 12px;
    background: var(--surface-3);
    border: 1px solid var(--line-strong);
    box-shadow: var(--shadow);
    font-size: 0.9em;
    font-weight: 600;
    transition: opacity 0.2s var(--ease), transform 0.2s var(--ease);
}
.toast[hidden] { display: block; opacity: 0; pointer-events: none; transform: translate(-50%, -8px); }
.toast[data-kind="error"] { border-color: color-mix(in srgb, var(--danger) 60%, transparent); }
.toast[data-kind="success"] { border-color: color-mix(in srgb, var(--live) 60%, transparent); }

/* ---------- Layout options ---------- */

:root[data-clocks="off"] .clocks { display: none; }
:root[data-nownext="off"] .nownext { display: none; }

@media (max-width: 420px) {
    .clocks { gap: 6px; }
    .clock { padding: 8px 9px 10px; }
    .clock-label .meta { display: none; }
    .clock-label { letter-spacing: 0.03em; font-size: 0.64em; }
    .status-pill .status-text { display: none; }
    .status-pill { padding: 4px 9px; }
}

@media (orientation: landscape) and (max-height: 500px) {
    .clock-value { max-height: 2.4rem; }
    .nownext { grid-template-columns: minmax(0, 1.35fr) minmax(0, 1fr); }
}

@media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { animation: none !important; transition: none !important; scroll-behavior: auto !important; }
}

@media print {
    .topbar, .clocks, .nownext, .jump-live, .banner { display: none !important; }
}
"""#
}
