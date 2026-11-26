//
//  HTMLJavaScript.swift
//  Cue to Cue
//
//  Behavior for the LAN viewer: a WebSocket to the Mac (/ws) with HTTP
//  fallback, clocks interpolated locally, the Live/Next panel, the cue list,
//  per-device stack browsing, view options, and signing in to edit cells.
//
//  Server messages (LANWebSocketProtocol): snapshot, show_state,
//  timer_state, cue_patch, pong. HTTP: /cues, /stack/<id>, /show-state,
//  /timer-state, /auth/*, PUT /cues/<id>.
//

import Foundation

struct HTMLJavaScript {
    static let content = #"""
(() => {
'use strict';

const $ = (id) => document.getElementById(id);
const root = document.documentElement;
const PREFS_KEY = 'c2c.viewer.prefs';
const SHEET_KEY = 'c2c.viewer.lastSheet';
const AUTH_KEY = 'authToken';

const POLL_FAST_MS = 1000;
const POLL_SAFETY_MS = 8000;
const BROWSE_POLL_MS = 3000;
const CLOCK_TICK_MS = 200;
const WS_PING_MS = 10000;
const WS_STALE_MS = 25000;
const WS_BACKOFF_MAX_MS = 15000;
const OFFLINE_AFTER_FAILURES = 3;

// ---------- Preferences (this device only) ----------

const DEFAULT_PREFS = {
    theme: 'dark', size: 'm', clocks: true, nownext: true, follow: true,
    keywords: true, wake: false, hiddenColumns: [], browseStackId: null
};
const prefs = Object.assign({}, DEFAULT_PREFS, readJSON(PREFS_KEY, {}));

function readJSON(key, fallback) {
    try { const v = JSON.parse(localStorage.getItem(key)); return v ?? fallback; } catch (_) { return fallback; }
}
function savePrefs() {
    try { localStorage.setItem(PREFS_KEY, JSON.stringify(prefs)); } catch (_) {}
}
function applyLook() {
    let theme = prefs.theme;
    if (theme === 'auto') theme = matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
    root.dataset.theme = theme;
    root.dataset.size = prefs.size;
    root.dataset.clocks = prefs.clocks ? 'on' : 'off';
    root.dataset.nownext = prefs.nownext ? 'on' : 'off';
    root.dataset.keywords = prefs.keywords ? 'on' : 'off';
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = theme === 'light' ? '#f3f5f9' : '#0b0f17';
}

// ---------- State ----------

const S = {
    macSheet: null,          // the stack the Mac is running (WebSocket / /cues)
    browseSheet: null,       // a stack this device chose to browse (/stack/<id>)
    playback: { selected: -1, upNext: -1, stackId: null, stackName: null },
    clock: {
        countdownTime: 0, countdownRunning: false, countdownTarget: null,
        countUpTime: 0, countUpRunning: false, countUpTarget: null, receivedAt: 0
    },
    macClockOffsetMs: 0,     // Mac time minus this device's time
    ws: null, wsOpen: false, wsAttempt: 0, wsTimer: null, lastMsgAt: 0,
    dataVersion: -1, playbackVersion: -1,
    pollTimer: null, browseTimer: null, httpOK: false, failures: 0, lastDataAt: 0,
    fromCache: false,
    auth: { token: null, user: null, perms: [] },
    followPaused: false, programmaticScrollUntil: 0,
    editing: null, wakeLock: null, renderedKey: ''
};

// ---------- Small helpers ----------

function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function now() { return Date.now(); }
function macNow() { return new Date(Date.now() + S.macClockOffsetMs); }
function pad(n) { return String(n).padStart(2, '0'); }
const USES_12H = (() => {
    try { return new Intl.DateTimeFormat([], { hour: 'numeric' }).resolvedOptions().hour12 !== false; } catch (_) { return true; }
})();
function formatClock(date) {
    let h = date.getHours();
    const m = pad(date.getMinutes());
    const s = pad(date.getSeconds());
    if (!USES_12H) return { main: `${pad(h)}:${m}:${s}`, ampm: '' };
    const ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12 || 12;
    return { main: `${h}:${m}:${s}`, ampm };
}
function formatDuration(total) {
    total = Math.max(0, Math.floor(total || 0));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}
function formatTimeOfDay(date) {
    return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });
}
async function fetchJSON(url, options = {}, timeoutMs = 5000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetch(url, Object.assign({ cache: 'no-store', signal: controller.signal }, options));
        const text = await response.text();
        let body = null;
        try { body = text ? JSON.parse(text) : null; } catch (_) { body = null; }
        return { ok: response.ok, status: response.status, body };
    } finally {
        clearTimeout(timer);
    }
}

let toastTimer = null;
function toast(message, kind = 'info') {
    const el = $('toast');
    el.textContent = message;
    el.dataset.kind = kind;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, kind === 'error' ? 5000 : 3000);
}

// ---------- Which sheet is on screen ----------

function isBrowsing() { return !!prefs.browseStackId; }
function viewSheet() { return isBrowsing() ? S.browseSheet : S.macSheet; }

/// Column roles: the cue number and description get the prominent spots.
function columnRoles(columns) {
    const names = columns.map((c) => (c.name || '').trim());
    let num = names.findIndex((n) => /^(#|no\.?|num(ber)?|cue( ?#)?|q)$/i.test(n));
    if (num < 0 && names.length > 1 && names[0].length <= 3) num = 0;
    let desc = names.findIndex((n, i) => i !== num && /desc|cue text|action|what/i.test(n));
    if (desc < 0) {
        let widest = -1;
        columns.forEach((c, i) => {
            if (i === num) return;
            if (widest < 0 || (c.width || 0) > (columns[widest].width || 0)) widest = i;
        });
        desc = widest;
    }
    const depts = columns.map((_, i) => i).filter((i) => i !== num && i !== desc);
    return { num, desc, depts };
}

function keywordColor(cue, highlights) {
    if (!Array.isArray(highlights) || !highlights.length) return null;
    for (const value of cue.values || []) {
        if (!value) continue;
        const lower = value.toLowerCase();
        for (const h of highlights) {
            if (h.keyword && h.color && lower.includes(h.keyword.toLowerCase())) return '#' + String(h.color).replace(/^#/, '');
        }
    }
    return null;
}

function liveIndexFor(sheet) {
    if (!sheet || !S.playback.stackId || sheet.cueStackId !== S.playback.stackId) return -1;
    return S.playback.selected;
}
function nextIndexFor(sheet) {
    if (!sheet || !S.playback.stackId || sheet.cueStackId !== S.playback.stackId) return -1;
    if (S.playback.upNext >= 0) return S.playback.upNext;
    const cues = sheet.cues || [];
    for (let i = S.playback.selected + 1; i < cues.length; i++) {
        if (!cues[i].isStruckThrough) return i;
    }
    return -1;
}

// ---------- Rendering: header ----------

function renderHeader() {
    const sheet = viewSheet();
    const mac = S.macSheet;
    const name = sheet?.cueStackName || (S.fromCache ? 'Last cue sheet' : 'Connecting…');
    $('stackName').textContent = name.replace(/\n/g, ' ');
    const mode = $('stackMode');
    if (isBrowsing()) {
        mode.textContent = mac?.cueStackName ? `Browsing · Mac is on ${mac.cueStackName.replace(/\n/g, ' ')}` : 'Browsing on this device';
        mode.classList.add('browsing');
    } else {
        mode.textContent = 'Following the Mac';
        mode.classList.remove('browsing');
    }
    document.title = sheet?.cueStackName ? `${sheet.cueStackName.replace(/\n/g, ' ')} · Cue to Cue` : 'Cue to Cue · Live';
}

// ---------- Rendering: connection ----------

function connectionState() {
    if (S.wsOpen) return 'live';
    if (S.httpOK) return 'polling';
    if (S.failures >= OFFLINE_AFTER_FAILURES) return 'offline';
    return 'connecting';
}
function renderStatus() {
    const state = connectionState();
    const pill = $('statusPill');
    pill.dataset.state = state;
    const labels = { live: 'Live', polling: 'Connected', connecting: S.lastDataAt ? 'Reconnecting' : 'Connecting', offline: 'Offline' };
    $('statusText').textContent = labels[state];
    pill.title = state === 'live' ? 'Updating instantly from the Mac'
        : state === 'polling' ? 'Updating every second from the Mac'
        : state === 'offline' ? 'Can’t reach the Mac' : 'Connecting to the Mac';
    const offline = state === 'offline' || (S.fromCache && state !== 'live' && state !== 'polling');
    $('offlineBanner').hidden = !offline;
    if (offline) {
        $('offlineText').textContent = S.lastDataAt
            ? `Can’t reach the Mac. Showing the cue sheet from ${formatTimeOfDay(new Date(S.lastDataAt))}.`
            : 'Can’t reach the Mac. Check that this device is on the show network.';
    }
    $('cues').classList.toggle('stale', offline);
}

// ---------- Rendering: Live / Next ----------

function deptSummary(sheet, cue, roles) {
    return roles.depts
        .map((i) => ({ name: sheet.columns[i]?.name || '', value: (cue.values || [])[i] || '' }))
        .filter((d) => d.value.trim() && !prefs.hiddenColumns.includes(d.name));
}
function cardHTML(kind, sheet, index) {
    const cue = sheet?.cues?.[index];
    const chip = `<span class="chip ${kind}">${kind === 'live' ? 'LIVE' : 'NEXT'}</span>`;
    if (!cue) {
        const note = kind === 'live'
            ? (sheet ? 'Standing by. No cue is live yet.' : 'Waiting for the Mac…')
            : 'Nothing after this cue.';
        return `<div class="card-head">${chip}</div><div class="card-desc card-note">${esc(note)}</div>`;
    }
    const roles = columnRoles(sheet.columns || []);
    const num = roles.num >= 0 ? (cue.values[roles.num] || '') : '';
    const desc = roles.desc >= 0 ? (cue.values[roles.desc] || '') : '';
    const depts = deptSummary(sheet, cue, roles)
        .map((d) => `<span><b>${esc(d.name)}</b>${esc(d.value)}</span>`).join('');
    return `<div class="card-head">${chip}${num ? `<span class="card-num">${esc(num)}</span>` : ''}`
        + `${cue.timerValue ? `<span class="card-timer">${esc(cue.timerValue)}</span>` : ''}</div>`
        + `<div class="card-desc">${esc(desc || '(no description)')}</div>`
        + (depts ? `<div class="card-depts">${depts}</div>` : '');
}
function renderNowNext() {
    const mac = S.macSheet;
    const live = liveIndexFor(mac);
    const next = nextIndexFor(mac);
    const nowCard = $('nowCard');
    const nextCard = $('nextCard');
    let nowHTML = cardHTML('live', mac, live);
    if (isBrowsing() && mac) {
        nowHTML += `<button class="card-action" type="button" data-action="follow">Follow the Mac</button>`;
    }
    if (nowCard.dataset.html !== nowHTML) {
        nowCard.innerHTML = nowHTML;
        nowCard.dataset.html = nowHTML;
    }
    nowCard.classList.toggle('empty', !(mac?.cues?.[live]));
    const nextHTML = cardHTML('next', mac, next);
    if (nextCard.dataset.html !== nextHTML) {
        nextCard.innerHTML = nextHTML;
        nextCard.dataset.html = nextHTML;
    }
    nextCard.classList.toggle('empty', !(mac?.cues?.[next]));
}

// ---------- Rendering: cue list ----------

function renderTable() {
    const sheet = viewSheet();
    const body = $('cueBody');
    const empty = !sheet || !(sheet.cues || []).length;
    $('emptyState').hidden = !empty;
    $('cueTable').hidden = empty;
    if (empty) {
        body.innerHTML = '';
        $('cueHead').innerHTML = '';
        $('cueCols').innerHTML = '';
        S.renderedKey = '';
        return;
    }
    const columns = sheet.columns || [];
    const roles = columnRoles(columns);
    const order = [roles.num, roles.desc, ...roles.depts].filter((i) => i >= 0);
    const hidden = new Set(prefs.hiddenColumns);
    const hide = (i) => (hidden.has(columns[i]?.name) ? ' col-hidden' : '');

    // The Mac's column widths, as proportions of the screen (no sideways scrolling).
    const shown = order.filter((i) => !hidden.has(columns[i]?.name));
    const total = shown.reduce((sum, i) => sum + Math.max(50, columns[i].width || 120), 0) || 1;
    $('cueCols').innerHTML = `<col style="width:64px">`
        + order.map((i) => `<col class="${hide(i).trim()}" style="width:${(85 * Math.max(50, columns[i].width || 120) / total).toFixed(2)}%">`).join('')
        + `<col style="width:72px">`;
    $('cueHead').innerHTML = `<th scope="col"><span class="sr-only">State</span></th>`
        + order.map((i) => `<th scope="col" class="${hide(i).trim()}">${esc(columns[i].name)}</th>`).join('')
        + `<th scope="col">Timer</th>`;

    const rows = (sheet.cues || []).map((cue, index) => {
        const kw = keywordColor(cue, sheet.highlightColors);
        const cls = ['cue-row'];
        if (cue.isStruckThrough) cls.push('is-struck');
        if (kw) cls.push('has-kw');
        const cells = order.map((i) => {
            const value = (cue.values || [])[i] || '';
            const role = i === roles.num ? 'c-num' : i === roles.desc ? 'c-desc' : 'c-dept';
            const emptyCls = role === 'c-dept' && !value.trim() ? ' is-empty' : '';
            const label = role === 'c-dept' ? ` data-label="${esc(columns[i].name)}"` : '';
            return `<td class="${role}${emptyCls}${hide(i)}" data-col="${i}"${label}>${esc(value)}</td>`;
        }).join('');
        const timer = cue.timerValue || '';
        return `<tr class="${cls.join(' ')}" data-index="${index}" data-id="${esc(cue.id)}"${kw ? ` style="--kw:${esc(kw)}"` : ''}>`
            + `<td class="c-state"></td>${cells}<td class="c-timer${timer ? '' : ' is-empty'}">${esc(timer)}</td></tr>`;
    });
    body.innerHTML = rows.join('');
    S.renderedKey = `${sheet.cueStackId}:${sheet.dataVersion}`;
    applyRowStates();
    applyEditability();
}

function applyRowStates() {
    const sheet = viewSheet();
    const live = liveIndexFor(sheet);
    const next = nextIndexFor(sheet);
    const rows = $('cueBody').children;
    for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        const isLive = i === live;
        const isNext = !isLive && i === next;
        row.classList.toggle('is-live', isLive);
        row.classList.toggle('is-next', isNext);
        const stateCell = row.firstElementChild;
        const want = isLive ? '<span class="chip live">LIVE</span>' : isNext ? '<span class="chip next">NEXT</span>' : '';
        if (stateCell.innerHTML !== want) stateCell.innerHTML = want;
        if (isLive) row.setAttribute('aria-current', 'step'); else row.removeAttribute('aria-current');
    }
}

function renderAll() {
    renderHeader();
    renderStatus();
    renderNowNext();
    const sheet = viewSheet();
    const key = sheet ? `${sheet.cueStackId}:${sheet.dataVersion}` : '';
    if (key !== S.renderedKey || !key) renderTable(); else applyRowStates();
    followLive(false);
}

// ---------- Following the live cue ----------

function liveRow() {
    const live = liveIndexFor(viewSheet());
    return live >= 0 ? $('cueBody').children[live] : null;
}
function followLive(force) {
    const row = liveRow();
    if (!row) { $('jumpLive').hidden = true; return; }
    if (force || (prefs.follow && !S.followPaused)) {
        S.programmaticScrollUntil = now() + 900;
        const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
        row.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' });
        S.followPaused = false;
    }
    updateJumpButton();
}
/// Height of the pinned top bar + clocks, so table headers and scrolled-to
/// rows sit just below it.
function measurePinned() {
    const h = $('pinned').getBoundingClientRect().height;
    root.style.setProperty('--pinned-h', `${Math.round(h)}px`);
}
function updateJumpButton() {
    const row = liveRow();
    if (!row) { $('jumpLive').hidden = true; return; }
    const rect = row.getBoundingClientRect();
    const top = $('pinned').getBoundingClientRect().bottom;
    const visible = rect.bottom > top + 10 && rect.top < window.innerHeight - 20;
    if (visible && S.followPaused && now() > S.programmaticScrollUntil) S.followPaused = false;
    $('jumpLive').hidden = visible;
}
function userScrolled() {
    if (now() < S.programmaticScrollUntil) return;
    if (prefs.follow) S.followPaused = true;
}
let scrollRaf = 0;
window.addEventListener('scroll', () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => { scrollRaf = 0; updateJumpButton(); });
}, { passive: true });
['wheel', 'touchmove'].forEach((type) => window.addEventListener(type, userScrolled, { passive: true }));
window.addEventListener('keydown', (e) => {
    if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes(e.key) && !e.target.closest('input, textarea, dialog')) userScrolled();
});

// ---------- Clocks ----------

function syncClock(data) {
    const d = data || {};
    const c = S.clock;
    if (d.countdownTime !== undefined) c.countdownTime = d.countdownTime;
    if (d.countdownRunning !== undefined) {
        c.countdownRunning = d.countdownRunning;
        if (!d.countdownRunning) c.countdownTarget = null;
    }
    if (d.countdownTarget !== undefined) c.countdownTarget = d.countdownTarget;
    if (d.countUpTime !== undefined) c.countUpTime = d.countUpTime;
    if (d.countUpRunning !== undefined) {
        c.countUpRunning = d.countUpRunning;
        if (!d.countUpRunning) c.countUpTarget = null;
    }
    if (d.countUpTarget !== undefined) c.countUpTarget = d.countUpTarget;
    // /timer-state carries the Mac's clock as `timestamp` (ms since 1970), so
    // time of day and countdown targets match the Mac even if this device's
    // clock is off. Ignore anything that isn't a plausible current time.
    if (typeof d.timestamp === 'number' && d.timestamp > 1.5e12) S.macClockOffsetMs = d.timestamp - Date.now();
    c.receivedAt = now();
    renderClocks();
}
function remaining(base, running, target) {
    if (!running) return base;
    if (typeof target === 'number') return Math.max(0, Math.ceil(target - (Date.now() + S.macClockOffsetMs) / 1000));
    return Math.max(0, Math.ceil(base - (now() - S.clock.receivedAt) / 1000));
}
function playlistTarget() {
    const list = S.macSheet?.countdownPlaylist;
    if (!list || !list.isActive || !Array.isArray(list.entries)) return null;
    return list.entries[list.currentIndex] || null;
}
/// Sets text and tells CSS how many characters to fit in the tile.
function setClockText(el, text, extraChars = 0) {
    if (el.textContent !== text || el.dataset.extra !== String(extraChars)) {
        el.style.setProperty('--chars', String(Math.max(5, text.length + extraChars)));
        el.dataset.extra = String(extraChars);
    }
}
function renderClocks() {
    const t = formatClock(macNow());
    const timeEl = $('clockTime');
    const timeHTML = `${t.main}${t.ampm ? `<span class="ampm">${t.ampm}</span>` : ''}`;
    if (timeEl.innerHTML !== timeHTML) {
        timeEl.innerHTML = timeHTML;
        timeEl.style.setProperty('--chars', String(t.main.length + (t.ampm ? 1 : 0)));
    }
    const dateText = macNow().toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
    if ($('todayDate').textContent !== dateText) $('todayDate').textContent = dateText;

    const c = S.clock;
    const count = remaining(c.countdownTime, c.countdownRunning, c.countdownTarget);
    const countText = formatDuration(count);
    setClockText($('clockCount'), countText);
    $('clockCount').textContent = countText;
    const countBox = $('countClock');
    countBox.dataset.run = c.countdownRunning ? 'running' : (count > 0 ? 'paused' : 'idle');
    countBox.dataset.urgency = c.countdownRunning && count === 0 ? 'zero' : (c.countdownRunning && count <= 60 ? 'soon' : '');
    $('countMeta').textContent = c.countdownRunning ? 'Running' : (count > 0 ? 'Paused' : '');

    const entry = playlistTarget();
    const toBox = $('toClock');
    const toRemaining = remaining(c.countUpTime, c.countUpRunning, c.countUpTarget);
    const toText = c.countUpRunning ? formatDuration(toRemaining) : '--:--';
    setClockText($('clockTo'), toText);
    $('clockTo').textContent = toText;
    toBox.dataset.run = c.countUpRunning ? 'running' : 'idle';
    toBox.dataset.urgency = c.countUpRunning && toRemaining <= 60 ? (toRemaining === 0 ? 'zero' : 'soon') : '';
    const toLabel = entry?.timeString ? `To ${entry.timeString.replace(/:00$/, '')}` : 'Count to Time';
    if ($('toLabel').textContent !== toLabel) $('toLabel').textContent = toLabel;
    const toMeta = entry?.label || '';
    if ($('toMeta').textContent !== toMeta) $('toMeta').textContent = toMeta;
}

// ---------- Data from the Mac ----------

let cacheTimer = null;
function rememberSheet(sheet) {
    clearTimeout(cacheTimer);
    cacheTimer = setTimeout(() => {
        try { localStorage.setItem(SHEET_KEY, JSON.stringify({ at: S.lastDataAt, sheet })); } catch (_) {}
    }, 1500);
}

function applyMacSheet(sheet) {
    if (!sheet || !Array.isArray(sheet.cues)) return;
    S.macSheet = sheet;
    S.lastDataAt = now();
    S.fromCache = false;
    if (isBrowsing() && sheet.cueStackId === prefs.browseStackId) S.browseSheet = sheet;
    rememberSheet(sheet);
    if (isBrowsing()) scheduleBrowseFetch(150);
    renderAll();
}

function applyShowState(p) {
    S.playback = {
        selected: typeof p.selectedCueIndex === 'number' ? p.selectedCueIndex : -1,
        upNext: typeof p.upNextCueIndex === 'number' ? p.upNextCueIndex : -1,
        stackId: p.cueStackId || null,
        stackName: p.cueStackName || null
    };
    renderNowNext();
    applyRowStates();
    followLive(false);
}

function applyCuePatch(patch) {
    if (S.editing && S.editing.cueId === patch.cueId && S.editing.col === patch.columnIndex) return;
    for (const sheet of [S.macSheet, S.browseSheet]) {
        const cue = sheet?.cues?.find((c) => c.id === patch.cueId);
        if (cue && patch.columnIndex >= 0 && patch.columnIndex < cue.values.length) cue.values[patch.columnIndex] = patch.newValue;
    }
    const sheet = viewSheet();
    const index = sheet?.cues?.findIndex((c) => c.id === patch.cueId) ?? -1;
    const row = index >= 0 ? $('cueBody').children[index] : null;
    const cell = row?.querySelector(`td[data-col="${patch.columnIndex}"]`);
    if (cell) {
        cell.textContent = patch.newValue;
        if (cell.classList.contains('c-dept')) cell.classList.toggle('is-empty', !patch.newValue.trim());
        const kw = keywordColor(sheet.cues[index], sheet.highlightColors);
        row.classList.toggle('has-kw', !!kw);
        if (kw) row.style.setProperty('--kw', kw); else row.style.removeProperty('--kw');
    }
    renderNowNext();
}

// WebSocket: instant updates. The page also polls over HTTP, every second
// while the socket is down and every 8 s as a safety net while it is up.
function connectSocket() {
    if (S.ws && (S.ws.readyState === WebSocket.OPEN || S.ws.readyState === WebSocket.CONNECTING)) return;
    let socket;
    try {
        socket = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws`);
    } catch (_) {
        scheduleReconnect();
        return;
    }
    S.ws = socket;
    socket.onopen = () => {
        if (S.ws !== socket) return;
        S.wsOpen = true;
        S.wsAttempt = 0;
        S.failures = 0;
        S.lastMsgAt = now();
        // A restarted Mac app starts its version counters again; accept whatever comes first.
        S.dataVersion = -1;
        S.playbackVersion = -1;
        renderStatus();
        fetchTimer();
        schedulePoll(POLL_SAFETY_MS);
    };
    socket.onmessage = (event) => {
        if (S.ws !== socket) return;
        S.lastMsgAt = now();
        let message;
        try { message = JSON.parse(event.data); } catch (_) { return; }
        handleMessage(message);
    };
    socket.onclose = () => {
        if (S.ws !== socket) return;
        S.ws = null;
        S.wsOpen = false;
        renderStatus();
        scheduleReconnect();
        schedulePoll(POLL_FAST_MS);
    };
    socket.onerror = () => {};
}
function handleMessage(m) {
    if (!m || !m.type) return;
    switch (m.type) {
        case 'snapshot':
            if (typeof m.version === 'number') {
                if (m.version < S.dataVersion) return;
                S.dataVersion = m.version;
            }
            applyMacSheet(m.data);
            break;
        case 'show_state':
            if (typeof m.version === 'number') {
                if (m.version < S.playbackVersion) return;
                S.playbackVersion = m.version;
            }
            if (m.data) applyShowState(m.data);
            break;
        case 'timer_state':
            syncClock(m.data);
            break;
        case 'cue_patch':
            if (m.data) applyCuePatch(m.data);
            if (isBrowsing()) scheduleBrowseFetch(400);
            break;
        default:
            break;
    }
}
function scheduleReconnect() {
    clearTimeout(S.wsTimer);
    const delay = Math.min(1000 * Math.pow(2, S.wsAttempt), WS_BACKOFF_MAX_MS);
    S.wsAttempt += 1;
    S.wsTimer = setTimeout(connectSocket, delay);
}
function reconnectNow() {
    clearTimeout(S.wsTimer);
    S.wsAttempt = 0;
    connectSocket();
}
function dropSocket() {
    const old = S.ws;
    S.ws = null;
    S.wsOpen = false;
    if (old) {
        old.onopen = old.onmessage = old.onclose = old.onerror = null;
        try { old.close(); } catch (_) {}
    }
    renderStatus();
    schedulePoll(POLL_FAST_MS);
    reconnectNow();
}
function pingSocket() {
    if (!S.ws || S.ws.readyState !== WebSocket.OPEN) return;
    // Nothing for 25 s means the link is dead (Mac asleep, Wi-Fi dropped)
    // even if the browser still reports it open.
    if (S.lastMsgAt && now() - S.lastMsgAt > WS_STALE_MS) { dropSocket(); return; }
    try { S.ws.send(JSON.stringify({ type: 'ping', version: S.dataVersion })); } catch (_) {}
}

function schedulePoll(delay) {
    clearTimeout(S.pollTimer);
    S.pollTimer = setTimeout(async () => {
        await poll();
        schedulePoll(S.wsOpen ? POLL_SAFETY_MS : POLL_FAST_MS);
    }, delay);
}
let polling = false;
async function poll() {
    if (polling || document.visibilityState === 'hidden') return;
    polling = true;
    try {
        const sheet = await fetchJSON('/cues');
        if (!sheet.ok || !sheet.body) throw new Error('cues');
        S.httpOK = true;
        S.failures = 0;
        if (!S.wsOpen) {
            const [show, timer] = await Promise.all([fetchJSON('/show-state', {}, 3000), fetchJSON('/timer-state', {}, 3000)]);
            if (show.ok && show.body) applyShowState(show.body);
            if (timer.ok && timer.body) syncClock(timer.body);
        }
        const fresh = !S.macSheet || S.macSheet.dataVersion !== sheet.body.dataVersion || S.macSheet.cueStackId !== sheet.body.cueStackId;
        if (fresh && !S.wsOpen) applyMacSheet(sheet.body);
        else if (!S.macSheet) applyMacSheet(sheet.body);
        else { S.lastDataAt = now(); renderStatus(); }
    } catch (_) {
        S.httpOK = false;
        S.failures += 1;
        renderStatus();
    } finally {
        polling = false;
    }
}
async function fetchTimer() {
    try {
        const r = await fetchJSON('/timer-state', {}, 3000);
        if (r.ok && r.body) syncClock(r.body);
    } catch (_) {}
}

// Browsing another stack on this device.
function scheduleBrowseFetch(delay) {
    clearTimeout(S.browseTimer);
    if (!isBrowsing()) return;
    S.browseTimer = setTimeout(fetchBrowse, delay);
}
async function fetchBrowse() {
    if (!isBrowsing()) return;
    const id = prefs.browseStackId;
    try {
        const r = await fetchJSON(`/stack/${encodeURIComponent(id)}`);
        if (r.status === 404) {
            prefs.browseStackId = null;
            savePrefs();
            S.browseSheet = null;
            toast('That cue stack was removed on the Mac. Following the Mac again.');
            renderAll();
            return;
        }
        if (r.ok && r.body && prefs.browseStackId === id) {
            const changed = !S.browseSheet || S.browseSheet.dataVersion !== r.body.dataVersion || S.browseSheet.cueStackId !== r.body.cueStackId;
            S.browseSheet = r.body;
            if (changed) renderAll();
        }
    } catch (_) {
        // Connection state is tracked by the main poll.
    } finally {
        scheduleBrowseFetch(BROWSE_POLL_MS);
    }
}
function setBrowse(id) {
    prefs.browseStackId = id || null;
    savePrefs();
    S.browseSheet = null;
    S.renderedKey = '';
    S.followPaused = false;
    renderAll();
    if (isBrowsing()) fetchBrowse();
    window.scrollTo({ top: 0 });
}

function wake() {
    if (S.ws && S.ws.readyState === WebSocket.OPEN) { pingSocket(); poll(); }
    else reconnectNow();
    fetchTimer();
    if (isBrowsing()) fetchBrowse();
    requestWakeLock();
}

// ---------- Sheets (dialogs) ----------

function openSheet(dialog) {
    if (!dialog.open) dialog.showModal();
}
function closeSheet(dialog) {
    if (dialog.open) dialog.close();
}
document.querySelectorAll('dialog.sheet').forEach((dialog) => {
    dialog.addEventListener('click', (e) => {
        if (e.target === dialog || e.target.closest('[data-close]')) closeSheet(dialog);
    });
});

// Stack picker
function renderStackList() {
    const list = $('stackList');
    const stacks = S.macSheet?.availableCueStacks || [];
    const macName = (S.macSheet?.cueStackName || '').replace(/\n/g, ' ');
    const item = (id, title, sub, checked) =>
        `<button class="list-item" type="button" role="radio" aria-checked="${checked}" data-stack="${esc(id)}">`
        + `<span class="grow">${esc(title)}${sub ? `<span class="sub">${esc(sub)}</span>` : ''}</span>`
        + `<svg class="icon check" aria-hidden="true"><use href="#i-check"/></svg></button>`;
    let html = item('', 'Follow the Mac', macName ? `Now on ${macName}` : 'Shows whatever stack the Mac is running', !isBrowsing());
    html += stacks.filter((s) => s.id).map((s) => item(
        s.id,
        (s.name || 'Untitled').replace(/\n/g, ' '),
        `${s.cueCount ?? ''}${s.cueCount != null ? ' cues' : ''}${s.id === S.macSheet?.cueStackId ? ' · on the Mac now' : ''}`,
        prefs.browseStackId === s.id
    )).join('');
    list.innerHTML = html;
}
$('stackButton').addEventListener('click', () => { renderStackList(); openSheet($('stackSheet')); });
$('stackList').addEventListener('click', (e) => {
    const button = e.target.closest('[data-stack]');
    if (!button) return;
    closeSheet($('stackSheet'));
    setBrowse(button.dataset.stack);
});
$('nowCard').addEventListener('click', (e) => {
    if (e.target.closest('[data-action="follow"]')) setBrowse(null);
});

// View options
function renderViewSheet() {
    document.querySelectorAll('#sizeControl button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.size === prefs.size)));
    document.querySelectorAll('#themeControl button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.theme === prefs.theme)));
    $('optClocks').checked = prefs.clocks;
    $('optNowNext').checked = prefs.nownext;
    $('optFollow').checked = prefs.follow;
    $('optKeywords').checked = prefs.keywords;
    $('optWake').checked = prefs.wake;
    // Browsers only allow wake locks on secure (https) pages.
    $('wakeRow').hidden = !('wakeLock' in navigator && window.isSecureContext);
    const columns = viewSheet()?.columns || [];
    const hidden = new Set(prefs.hiddenColumns);
    $('columnList').innerHTML = columns.length
        ? columns.map((c, i) => `<label class="toggle-row"><span class="grow">${esc(c.name || `Column ${i + 1}`)}</span>`
            + `<span class="switch"><input type="checkbox" data-column="${esc(c.name)}" ${hidden.has(c.name) ? '' : 'checked'}><span></span></span></label>`).join('')
        : '<div class="toggle-row"><span class="grow help" style="margin:0">Columns appear once the cue sheet loads.</span></div>';
}
$('viewButton').addEventListener('click', () => { renderViewSheet(); openSheet($('viewSheet')); });
$('sizeControl').addEventListener('click', (e) => {
    const b = e.target.closest('[data-size]');
    if (!b) return;
    prefs.size = b.dataset.size; savePrefs(); applyLook(); renderViewSheet();
});
$('themeControl').addEventListener('click', (e) => {
    const b = e.target.closest('[data-theme]');
    if (!b) return;
    prefs.theme = b.dataset.theme; savePrefs(); applyLook(); renderViewSheet();
});
matchMedia('(prefers-color-scheme: light)').addEventListener?.('change', () => { if (prefs.theme === 'auto') applyLook(); });
[['optClocks', 'clocks'], ['optNowNext', 'nownext'], ['optKeywords', 'keywords']].forEach(([id, key]) => {
    $(id).addEventListener('change', (e) => { prefs[key] = e.target.checked; savePrefs(); applyLook(); });
});
$('optFollow').addEventListener('change', (e) => {
    prefs.follow = e.target.checked; savePrefs();
    S.followPaused = false;
    if (prefs.follow) followLive(true);
});
$('optWake').addEventListener('change', (e) => {
    prefs.wake = e.target.checked; savePrefs();
    if (prefs.wake) requestWakeLock(); else releaseWakeLock();
});
$('columnList').addEventListener('change', (e) => {
    const input = e.target.closest('[data-column]');
    if (!input) return;
    const name = input.dataset.column;
    const set = new Set(prefs.hiddenColumns);
    if (input.checked) set.delete(name); else set.add(name);
    prefs.hiddenColumns = [...set];
    savePrefs();
    S.renderedKey = '';
    renderAll();
});
$('jumpLive').addEventListener('click', () => { S.followPaused = false; followLive(true); });

// Keep the screen on (where the browser allows it).
async function requestWakeLock() {
    if (!prefs.wake || !('wakeLock' in navigator) || document.visibilityState !== 'visible' || S.wakeLock) return;
    try {
        S.wakeLock = await navigator.wakeLock.request('screen');
        S.wakeLock.addEventListener('release', () => { S.wakeLock = null; });
    } catch (_) {
        S.wakeLock = null;
    }
}
function releaseWakeLock() {
    try { S.wakeLock?.release(); } catch (_) {}
    S.wakeLock = null;
}

// ---------- Signing in and editing ----------

function authHeaders(extra) {
    return Object.assign({ Authorization: `Bearer ${S.auth.token}` }, extra || {});
}
function setSignedOut() {
    try { localStorage.removeItem(AUTH_KEY); } catch (_) {}
    S.auth = { token: null, user: null, perms: [] };
    renderAccount();
    applyEditability();
}
async function loadAccount() {
    if (!S.auth.token) return;
    try {
        const [me, perms] = await Promise.all([
            fetchJSON('/auth/me', { headers: authHeaders() }),
            fetchJSON('/auth/permissions', { headers: authHeaders() })
        ]);
        if (me.status === 401 || perms.status === 401) { setSignedOut(); return; }
        if (me.ok && me.body) S.auth.user = me.body;
        if (perms.ok && Array.isArray(perms.body)) S.auth.perms = perms.body;
    } catch (_) {
        // Keep the token on network errors; try again on reconnect.
    }
    renderAccount();
    applyEditability();
}
function renderAccount() {
    const signedIn = !!(S.auth.token && S.auth.user);
    const button = $('accountButton');
    button.classList.toggle('signed-in', signedIn);
    button.setAttribute('aria-label', signedIn ? `Signed in as ${S.auth.user.username}` : 'Sign in to edit');
    $('loginForm').hidden = signedIn;
    $('accountInfo').hidden = !signedIn;
    $('accountSheetTitle').textContent = signedIn ? 'Account' : 'Sign In to Edit';
    if (signedIn) {
        const name = S.auth.user.username || '';
        $('accountName').textContent = name;
        $('accountInitial').textContent = (name[0] || '?').toUpperCase();
        $('accountRole').textContent = S.auth.user.isAdmin ? 'Admin · can edit every column' : 'Can edit the columns allowed in Users & Permissions';
    }
    root.dataset.editing = signedIn ? 'on' : 'off';
}
function canEdit(columnIndex) {
    const sheet = viewSheet();
    if (!S.auth.token || !S.auth.user || !sheet) return false;
    if (S.auth.user.isAdmin) return true;
    const column = sheet.columns?.[columnIndex];
    if (!column) return false;
    const permission = S.auth.perms.find((p) => p.cueStackId === sheet.cueStackId);
    if (!permission) return false;
    return (permission.allowedColumns || []).includes(column.name)
        || (permission.allowedColumnIndices || []).includes(columnIndex);
}
function applyEditability() {
    const signedIn = !!(S.auth.token && S.auth.user);
    $('cueBody').querySelectorAll('td[data-col]').forEach((td) => {
        const editable = signedIn && canEdit(Number(td.dataset.col));
        td.classList.toggle('can-edit', editable);
        if (editable) td.setAttribute('tabindex', '0'); else td.removeAttribute('tabindex');
    });
}

$('accountButton').addEventListener('click', () => {
    renderAccount();
    $('loginError').hidden = true;
    openSheet($('accountSheet'));
    if (!S.auth.user) setTimeout(() => $('loginUser').focus(), 50);
});
$('togglePass').addEventListener('click', () => {
    const input = $('loginPass');
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    $('togglePass').textContent = show ? 'Hide' : 'Show';
    $('togglePass').setAttribute('aria-pressed', String(show));
});
$('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = $('loginUser').value.trim();
    const password = $('loginPass').value;
    const error = $('loginError');
    if (!username || !password) {
        error.textContent = 'Enter your username and password.';
        error.hidden = false;
        return;
    }
    const submit = $('loginSubmit');
    submit.disabled = true;
    submit.textContent = 'Signing In…';
    try {
        const r = await fetchJSON('/auth/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        }, 8000);
        if (r.ok && r.body?.success && r.body.token) {
            S.auth.token = r.body.token;
            S.auth.user = r.body.user || { username };
            try { localStorage.setItem(AUTH_KEY, S.auth.token); } catch (_) {}
            $('loginForm').reset();
            await loadAccount();
            closeSheet($('accountSheet'));
            toast(`Signed in as ${S.auth.user.username}`, 'success');
        } else {
            error.textContent = r.status === 401 ? 'That username or password isn’t right.'
                : r.status === 429 ? 'Too many attempts. Wait a minute, then try again.'
                : (r.body?.message || 'Couldn’t sign in. Try again.');
            error.hidden = false;
        }
    } catch (_) {
        error.textContent = 'Can’t reach the Mac. Check that this device is on the show network.';
        error.hidden = false;
    } finally {
        submit.disabled = false;
        submit.textContent = 'Sign In';
    }
});
$('signOut').addEventListener('click', async () => {
    const token = S.auth.token;
    setSignedOut();
    closeSheet($('accountSheet'));
    toast('Signed out');
    try { await fetch('/auth/logout', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }); } catch (_) {}
});

function openEditor(td) {
    const row = td.closest('tr');
    const sheet = viewSheet();
    const index = Number(row.dataset.index);
    const col = Number(td.dataset.col);
    const cue = sheet?.cues?.[index];
    if (!cue) return;
    const roles = columnRoles(sheet.columns || []);
    const number = roles.num >= 0 ? cue.values[roles.num] : '';
    S.editing = { cueId: cue.id, col, original: cue.values[col] || '' };
    $('editSheetTitle').textContent = `Edit ${sheet.columns[col]?.name || 'Cell'}`;
    $('editLabel').textContent = sheet.columns[col]?.name || 'Value';
    $('editContext').textContent = `${number ? `Cue ${number}` : `Row ${index + 1}`} · ${(sheet.cueStackName || '').replace(/\n/g, ' ')}`;
    $('editValue').value = S.editing.original;
    $('editError').hidden = true;
    openSheet($('editSheet'));
    setTimeout(() => { const v = $('editValue'); v.focus(); v.select(); }, 50);
}
$('cueBody').addEventListener('click', (e) => {
    const td = e.target.closest('td[data-col]');
    if (!td) return;
    if (td.classList.contains('can-edit')) { openEditor(td); return; }
    if (S.auth.user && !canEdit(Number(td.dataset.col))) toast('You can’t edit this column. Ask the show caller for access.');
});
$('cueBody').addEventListener('keydown', (e) => {
    const td = e.target.closest('td.can-edit');
    if (td && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); openEditor(td); }
});
$('editValue').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('editForm').requestSubmit(); }
});
$('editSheet').addEventListener('close', () => { S.editing = null; });
$('editForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const edit = S.editing;
    if (!edit) return;
    const value = $('editValue').value.replace(/\s+$/, '');
    if (value === edit.original) { closeSheet($('editSheet')); return; }
    const save = $('editSave');
    save.disabled = true;
    save.textContent = 'Saving…';
    try {
        const r = await fetchJSON(`/cues/${encodeURIComponent(edit.cueId)}`, {
            method: 'PUT',
            headers: authHeaders({ 'Content-Type': 'application/json' }),
            body: JSON.stringify({ cueId: edit.cueId, columnIndex: edit.col, newValue: value })
        }, 8000);
        if (r.ok) {
            closeSheet($('editSheet'));
            applyCuePatch({ cueId: edit.cueId, columnIndex: edit.col, newValue: value });
            toast('Saved. Everyone sees the change now.', 'success');
        } else {
            const message = r.status === 401 ? 'Your sign-in expired. Sign in again.'
                : r.status === 403 ? 'You don’t have permission to edit this column.'
                : r.status === 404 ? 'That cue was removed on the Mac.'
                : (r.body?.message || 'Couldn’t save. Try again.');
            $('editError').textContent = message;
            $('editError').hidden = false;
            if (r.status === 401) setSignedOut();
        }
    } catch (_) {
        $('editError').textContent = 'Can’t reach the Mac. Your change wasn’t saved.';
        $('editError').hidden = false;
    } finally {
        save.disabled = false;
        save.textContent = 'Save';
    }
});

// ---------- Start ----------

function retireOldOfflineLayer() {
    // Earlier viewers installed a service worker that could keep serving an
    // old copy of this page. Remove it and its caches.
    try {
        navigator.serviceWorker?.getRegistrations?.().then((regs) => regs.forEach((r) => r.unregister())).catch(() => {});
        window.caches?.keys?.().then((keys) => keys.forEach((k) => caches.delete(k))).catch(() => {});
    } catch (_) {}
}

function start() {
    applyLook();
    retireOldOfflineLayer();
    S.auth.token = (() => { try { return localStorage.getItem(AUTH_KEY); } catch (_) { return null; } })();
    renderAccount();

    const cached = readJSON(SHEET_KEY, null);
    if (cached?.sheet?.cues) {
        S.macSheet = cached.sheet;
        S.lastDataAt = cached.at || 0;
        S.fromCache = true;
    }
    renderAll();
    renderClocks();

    connectSocket();
    poll().then(() => schedulePoll(S.wsOpen ? POLL_SAFETY_MS : POLL_FAST_MS));
    fetchTimer();
    if (isBrowsing()) fetchBrowse();
    loadAccount();
    requestWakeLock();

    setInterval(renderClocks, CLOCK_TICK_MS);
    setInterval(pingSocket, WS_PING_MS);
    setInterval(fetchTimer, 60000);
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') wake(); });
    window.addEventListener('online', wake);
    window.addEventListener('pageshow', (e) => { if (e.persisted) wake(); });
    window.addEventListener('resize', () => { updateJumpButton(); measurePinned(); }, { passive: true });
    measurePinned();
}

start();
})();
"""#
}
