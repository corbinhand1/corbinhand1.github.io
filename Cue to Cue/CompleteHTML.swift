//
//  CompleteHTML.swift
//  Cue to Cue
//
//  The LAN viewer page served at http://<mac>:8080/. Styles live in
//  HTMLStyles, behavior in HTMLJavaScript.
//

import Foundation

struct CompleteHTML {
    static let content = #"""
<!DOCTYPE html>
<html lang="en" data-theme="dark" data-size="m">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="theme-color" content="#0b0f17">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="Cue to Cue">
    <title>Cue to Cue · Live</title>
    <script>
        // Apply saved look before first paint (no flash).
        try {
            var p = JSON.parse(localStorage.getItem('c2c.viewer.prefs') || '{}');
            var t = p.theme || 'dark';
            if (t === 'auto') t = matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
            document.documentElement.dataset.theme = t;
            document.documentElement.dataset.size = p.size || 'm';
            document.documentElement.dataset.clocks = p.clocks === false ? 'off' : 'on';
            document.documentElement.dataset.nownext = p.nownext === false ? 'off' : 'on';
            document.documentElement.dataset.keywords = p.keywords === false ? 'off' : 'on';
        } catch (e) {}
    </script>
    <style>
\#(HTMLStyles.content)
    </style>
</head>
<body>
    <svg width="0" height="0" style="position:absolute" aria-hidden="true">
        <symbol id="i-chevron" viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></symbol>
        <symbol id="i-sliders" viewBox="0 0 24 24"><path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/></symbol>
        <symbol id="i-user" viewBox="0 0 24 24"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></symbol>
        <symbol id="i-close" viewBox="0 0 24 24"><path d="M18 6 6 18M6 6l12 12"/></symbol>
        <symbol id="i-check" viewBox="0 0 24 24"><path d="M20 6 9 17l-5-5"/></symbol>
        <symbol id="i-target" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/></symbol>
        <symbol id="i-wifi-off" viewBox="0 0 24 24"><path d="M12 20h.01M8.5 16.4a5 5 0 0 1 7 0M2 8.8a15 15 0 0 1 4.2-2.6M10.7 5.1A15 15 0 0 1 22 8.8M5 12.9a10 10 0 0 1 5.2-2.7M19 12.9a10 10 0 0 0-2.1-1.6M2 2l20 20"/></symbol>
    </svg>

    <div class="pinned" id="pinned">
    <header class="topbar">
        <button class="stack-button" id="stackButton" type="button" aria-haspopup="dialog" aria-controls="stackSheet">
            <span class="titles">
                <span class="stack-name" id="stackName">Connecting…</span>
                <span class="stack-mode" id="stackMode">Following the Mac</span>
            </span>
            <svg class="icon chev" aria-hidden="true"><use href="#i-chevron"/></svg>
        </button>
        <div class="status-pill" id="statusPill" data-state="connecting" role="status" aria-live="polite">
            <span class="status-dot" aria-hidden="true"></span>
            <span class="status-text" id="statusText">Connecting</span>
        </div>
        <button class="icon-button" id="viewButton" type="button" aria-label="View options" aria-haspopup="dialog">
            <svg class="icon" aria-hidden="true"><use href="#i-sliders"/></svg>
        </button>
        <button class="icon-button" id="accountButton" type="button" aria-label="Sign in to edit" aria-haspopup="dialog">
            <svg class="icon" aria-hidden="true"><use href="#i-user"/></svg>
        </button>
    </header>

    <section class="clocks" aria-label="Clocks">
        <div class="clock clock-time">
            <div class="clock-label"><span>Time of Day</span><span class="meta" id="todayDate"></span></div>
            <div class="clock-value" id="clockTime">--:--:--</div>
        </div>
        <div class="clock clock-count" id="countClock" data-run="idle">
            <div class="clock-label"><span>Countdown</span><span class="meta" id="countMeta"></span></div>
            <div class="clock-value" id="clockCount">00:00</div>
        </div>
        <div class="clock clock-to" id="toClock" data-run="idle">
            <div class="clock-label"><span id="toLabel">Count to Time</span><span class="meta" id="toMeta"></span></div>
            <div class="clock-value" id="clockTo">--:--</div>
        </div>
    </section>
    </div>

    <section class="nownext" id="nowNext" aria-label="Live and next cue">
        <article class="cue-card live empty" id="nowCard" aria-live="polite" aria-atomic="true"></article>
        <article class="cue-card next empty" id="nextCard"></article>
    </section>

    <div class="banner" id="offlineBanner" role="status" hidden>
        <svg class="icon" aria-hidden="true"><use href="#i-wifi-off"/></svg>
        <span id="offlineText">Can’t reach the Mac. Showing the last cue sheet received.</span>
    </div>

    <main class="cues" id="cues" aria-label="Cue list">
        <div class="table-wrap">
            <table class="cue-table" id="cueTable">
                <colgroup id="cueCols"></colgroup>
                <thead><tr id="cueHead"></tr></thead>
                <tbody id="cueBody"></tbody>
            </table>
        </div>
        <div class="empty-state" id="emptyState" hidden>
            <h2>Waiting for the show</h2>
            <p>The cue sheet appears here as soon as the Mac sends it.</p>
        </div>
    </main>

    <button class="jump-live" id="jumpLive" type="button" hidden>
        <svg class="icon" aria-hidden="true"><use href="#i-target"/></svg>
        Back to live cue
    </button>

    <div class="toast" id="toast" role="status" aria-live="polite" hidden></div>

    <!-- Choose a cue stack -->
    <dialog class="sheet" id="stackSheet" aria-labelledby="stackSheetTitle">
        <div class="sheet-head">
            <h2 id="stackSheetTitle">Cue Stack</h2>
            <button class="icon-button" type="button" data-close aria-label="Close"><svg class="icon" aria-hidden="true"><use href="#i-close"/></svg></button>
        </div>
        <div class="sheet-body">
            <div class="list" id="stackList" role="radiogroup" aria-label="Cue stacks"></div>
            <p class="help">Choosing a stack changes only this device. Other viewers and the Mac aren’t affected.</p>
        </div>
    </dialog>

    <!-- View options -->
    <dialog class="sheet" id="viewSheet" aria-labelledby="viewSheetTitle">
        <div class="sheet-head">
            <h2 id="viewSheetTitle">View</h2>
            <button class="icon-button" type="button" data-close aria-label="Close"><svg class="icon" aria-hidden="true"><use href="#i-close"/></svg></button>
        </div>
        <div class="sheet-body">
            <div class="group-label" id="sizeLabel">Text Size</div>
            <div class="segmented" id="sizeControl" role="group" aria-labelledby="sizeLabel">
                <button type="button" data-size="s">S</button>
                <button type="button" data-size="m">M</button>
                <button type="button" data-size="l">L</button>
                <button type="button" data-size="xl">XL</button>
            </div>

            <div class="group-label" id="themeLabel">Appearance</div>
            <div class="segmented" id="themeControl" role="group" aria-labelledby="themeLabel">
                <button type="button" data-theme="dark">Dark</button>
                <button type="button" data-theme="light">Light</button>
                <button type="button" data-theme="auto">Auto</button>
            </div>

            <div class="group-label">Show</div>
            <div class="list">
                <label class="toggle-row"><span class="grow">Clocks</span><span class="switch"><input type="checkbox" id="optClocks"><span></span></span></label>
                <label class="toggle-row"><span class="grow">Live &amp; Next panel</span><span class="switch"><input type="checkbox" id="optNowNext"><span></span></span></label>
                <label class="toggle-row"><span class="grow">Follow the live cue<span class="sub">Scrolls the list as cues are called</span></span><span class="switch"><input type="checkbox" id="optFollow"><span></span></span></label>
                <label class="toggle-row"><span class="grow">Keyword colors<span class="sub">Colors set in the Mac’s Highlights settings</span></span><span class="switch"><input type="checkbox" id="optKeywords"><span></span></span></label>
                <label class="toggle-row" id="wakeRow" hidden><span class="grow">Keep screen awake</span><span class="switch"><input type="checkbox" id="optWake"><span></span></span></label>
            </div>

            <div class="group-label">Columns</div>
            <div class="list" id="columnList"></div>
            <p class="help">Hidden columns are remembered on this device for every stack.</p>
        </div>
    </dialog>

    <!-- Sign in / account -->
    <dialog class="sheet" id="accountSheet" aria-labelledby="accountSheetTitle">
        <div class="sheet-head">
            <h2 id="accountSheetTitle">Sign In to Edit</h2>
            <button class="icon-button" type="button" data-close aria-label="Close"><svg class="icon" aria-hidden="true"><use href="#i-close"/></svg></button>
        </div>
        <form class="sheet-body" id="loginForm" novalidate>
            <p class="help" style="margin:0 0 14px">Anyone can watch. Sign in with an account from the Mac’s Users &amp; Permissions to edit the columns you’re allowed to.</p>
            <p class="form-error" id="loginError" role="alert" hidden></p>
            <div class="field">
                <label for="loginUser">Username</label>
                <input id="loginUser" name="username" autocomplete="username" autocapitalize="none" autocorrect="off" spellcheck="false" required>
            </div>
            <div class="field">
                <label for="loginPass">Password</label>
                <div class="input-with-button">
                    <input id="loginPass" name="password" type="password" autocomplete="current-password" required>
                    <button type="button" id="togglePass" aria-controls="loginPass" aria-pressed="false">Show</button>
                </div>
            </div>
            <button class="btn primary" id="loginSubmit" type="submit" style="width:100%">Sign In</button>
        </form>
        <div class="sheet-body" id="accountInfo" hidden>
            <div class="account-card">
                <div class="avatar" id="accountInitial" aria-hidden="true">?</div>
                <div class="grow">
                    <div id="accountName" style="font-weight:700"></div>
                    <div class="help" id="accountRole" style="margin:0"></div>
                </div>
            </div>
            <p class="help">Tap a cell you’re allowed to edit (dotted underline) to change it. Changes appear on the Mac and every viewer.</p>
            <div style="display:flex;justify-content:flex-end;margin-top:16px">
                <button class="btn danger-text" id="signOut" type="button">Sign Out</button>
            </div>
        </div>
    </dialog>

    <!-- Edit one cell -->
    <dialog class="sheet" id="editSheet" aria-labelledby="editSheetTitle">
        <form method="dialog" id="editForm" style="display:contents">
            <div class="sheet-head">
                <h2 id="editSheetTitle">Edit</h2>
                <button class="icon-button" type="button" data-close aria-label="Cancel"><svg class="icon" aria-hidden="true"><use href="#i-close"/></svg></button>
            </div>
            <div class="sheet-body">
                <p class="help" id="editContext" style="margin:0 0 12px"></p>
                <div class="field">
                    <label for="editValue" id="editLabel">Value</label>
                    <textarea id="editValue" rows="3"></textarea>
                </div>
                <p class="form-error" id="editError" role="alert" hidden></p>
            </div>
            <div class="sheet-foot">
                <button class="btn" type="button" data-close>Cancel</button>
                <button class="btn primary" id="editSave" type="submit">Save</button>
            </div>
        </form>
    </dialog>

    <script>
\#(HTMLJavaScript.content)
    </script>
</body>
</html>
"""#
}
