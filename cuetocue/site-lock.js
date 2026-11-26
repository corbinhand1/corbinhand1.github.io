/**
 * Site lock for the Cue to Cue viewer.
 *
 * The site is public (GitHub Pages), so the Mac app encrypts the show files
 * with the viewer password before publishing them. This file asks for the
 * password, turns it into the key, and decrypts files as they're loaded.
 * Format: see WebsiteEncryption.swift in the Mac app.
 *
 *   site-key.json      { version, kdf: "PBKDF2-SHA256", iterations, salt, check }
 *   encrypted files    { "encrypted": { version, iv, data } }   AES-256-GCM
 *
 * The derived key (not the password) is remembered on this device for
 * 12 hours, until "Lock" is pressed, or until the password is changed.
 */
(function () {
    const KEY_FILE = 'site-key.json';
    const STORAGE_KEY = 'cuetocue_site_key';
    const REMEMBER_MS = 12 * 60 * 60 * 1000;
    const CHECK_TEXT = 'cuetocue-site-key-v1';

    class SiteLockError extends Error {}

    function fromBase64(text) {
        const binary = atob(text);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        return bytes;
    }

    function toBase64(buffer) {
        let binary = '';
        new Uint8Array(buffer).forEach(b => { binary += String.fromCharCode(b); });
        return btoa(binary);
    }

    async function decryptEnvelope(envelope, key) {
        const plain = await crypto.subtle.decrypt(
            { name: 'AES-GCM', iv: fromBase64(envelope.iv) }, key, fromBase64(envelope.data));
        return new TextDecoder().decode(plain);
    }

    async function deriveKey(password, siteKey) {
        const material = await crypto.subtle.importKey(
            'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
        const bits = await crypto.subtle.deriveBits(
            { name: 'PBKDF2', hash: 'SHA-256', salt: fromBase64(siteKey.salt), iterations: siteKey.iterations },
            material, 256);
        return bits;
    }

    async function importRawKey(raw) {
        return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['decrypt']);
    }

    async function keyOpensSite(key, siteKey) {
        try {
            return (await decryptEnvelope(siteKey.check, key)) === CHECK_TEXT;
        } catch (e) {
            return false;
        }
    }

    function forgetKey() {
        try { localStorage.removeItem(STORAGE_KEY); } catch (e) { /* storage unavailable */ }
    }

    class SiteLock {
        constructor() {
            this.key = null;
            this.siteKey = null;
            this.onUnlock = null;
        }

        /** Ask for the password if needed, then call onUnlock(). */
        async init(onUnlock) {
            this.onUnlock = onUnlock;
            try {
                const response = await fetch(`${KEY_FILE}?v=${Date.now()}`, { cache: 'no-store' });
                if (response.status === 404) {
                    // Nothing has been published with a password yet.
                    this.unlocked();
                    return;
                }
                if (!response.ok) throw new Error(`site-key.json: ${response.status}`);
                this.siteKey = await response.json();
            } catch (error) {
                this.showPrompt('Can’t reach the website. Check your connection and reload.', true);
                return;
            }
            if (!window.crypto || !crypto.subtle) {
                this.showPrompt('This browser can’t open the encrypted show files. Open the page over https in a current browser.', true);
                return;
            }
            if (await this.restoreRememberedKey()) {
                this.unlocked();
                return;
            }
            this.showPrompt();
        }

        async restoreRememberedKey() {
            try {
                const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
                if (!saved || saved.salt !== this.siteKey.salt || Date.now() > saved.expires) return false;
                const key = await importRawKey(fromBase64(saved.key));
                if (!(await keyOpensSite(key, this.siteKey))) return false;
                this.key = key;
                return true;
            } catch (e) {
                return false;
            }
        }

        async tryPassword(password) {
            const raw = await deriveKey(password, this.siteKey);
            const key = await importRawKey(raw);
            if (!(await keyOpensSite(key, this.siteKey))) return false;
            this.key = key;
            try {
                localStorage.setItem(STORAGE_KEY, JSON.stringify({
                    salt: this.siteKey.salt, key: toBase64(raw), expires: Date.now() + REMEMBER_MS
                }));
            } catch (e) { /* storage unavailable: ask again next visit */ }
            return true;
        }

        /** Fetch a JSON file, decrypting it if it's encrypted. Returns null on 404. */
        async fetchJSON(path) {
            const separator = path.includes('?') ? '&' : '?';
            const response = await fetch(`${path}${separator}v=${Date.now()}`, { cache: 'no-store' });
            if (response.status === 404) return null;
            if (!response.ok) throw new Error(`${path}: ${response.status}`);
            const body = await response.json();
            if (!body || !body.encrypted || typeof body.encrypted !== "object") return body;
            if (!this.key) throw new SiteLockError('locked');
            try {
                return JSON.parse(await decryptEnvelope(body.encrypted, this.key));
            } catch (e) {
                // Usually means the password was changed since this device unlocked.
                throw new SiteLockError('key no longer opens the site');
            }
        }

        /** The password changed (or the key stopped working): ask again. */
        relock() {
            forgetKey();
            location.reload();
        }

        lock() {
            forgetKey();
            location.reload();
        }

        unlocked() {
            const overlay = document.getElementById('passwordOverlay');
            if (overlay) overlay.remove();
            const main = document.getElementById('mainContent');
            if (main) main.style.display = 'block';
            if (this.onUnlock) this.onUnlock();
        }

        showPrompt(message, blocked) {
            addStyles();
            document.body.insertAdjacentHTML('afterbegin', `
                <div id="passwordOverlay" class="password-overlay">
                    <form class="password-prompt" id="passwordForm" autocomplete="on">
                        <div class="password-header">
                            <h2>Cue to Cue Viewer</h2>
                            <p>Enter the show password</p>
                        </div>
                        <div class="password-form">
                            <input type="text" name="username" value="cuetocue" autocomplete="username" hidden>
                            <input type="password" id="passwordInput" placeholder="Password" autocomplete="current-password" ${blocked ? 'disabled' : ''}>
                            <label class="password-toggle">
                                <input type="checkbox" id="showPasswordToggle"> Show password
                            </label>
                            <button id="passwordSubmit" type="submit" ${blocked ? 'disabled' : ''}>Open</button>
                        </div>
                        <div id="passwordError" class="error-message" role="alert"></div>
                        <div class="password-footer"><small>This device stays unlocked for 12 hours.</small></div>
                    </form>
                </div>`);
            const input = document.getElementById('passwordInput');
            const button = document.getElementById('passwordSubmit');
            const error = document.getElementById('passwordError');
            if (message) error.textContent = message;
            document.getElementById('showPasswordToggle').addEventListener('change', e => {
                input.type = e.target.checked ? 'text' : 'password';
            });
            document.getElementById('passwordForm').addEventListener('submit', async e => {
                e.preventDefault();
                const password = input.value;
                if (!password) { error.textContent = 'Enter the password.'; return; }
                button.disabled = true;
                button.textContent = 'Opening…';
                error.textContent = '';
                let ok = false;
                try { ok = await this.tryPassword(password); } catch (err) { ok = false; }
                if (ok) {
                    this.unlocked();
                } else {
                    error.textContent = 'That password didn’t work.';
                    button.disabled = false;
                    button.textContent = 'Open';
                    input.select();
                }
            });
            if (!blocked) setTimeout(() => input.focus(), 50);
        }
    }

    function addStyles() {
        if (document.getElementById('passwordStyles')) return;
        document.head.insertAdjacentHTML('beforeend', `<style id="passwordStyles">
            .password-overlay { position: fixed; inset: 0; background: rgba(18,18,18,0.98); display: flex;
                align-items: center; justify-content: center; z-index: 10000;
                font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
            .password-prompt { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1);
                border-radius: 16px; padding: 40px; max-width: 400px; width: 90%; text-align: center;
                box-shadow: 0 8px 32px rgba(0,0,0,0.3); }
            .password-header h2 { color: #fff; font-size: 1.8rem; font-weight: 600; margin: 0 0 8px; }
            .password-header p { color: #b0b0b0; font-size: 1rem; margin: 0 0 30px; }
            .password-form { display: flex; flex-direction: column; gap: 16px; margin-bottom: 20px; }
            .password-form input[type=password], .password-form input[type=text] { padding: 16px;
                border: 1px solid rgba(255,255,255,0.2); border-radius: 8px; background: rgba(255,255,255,0.05);
                color: #fff; font-size: 16px; font-family: inherit; }
            .password-form input:focus { outline: none; border-color: #4CAF50; box-shadow: 0 0 0 2px rgba(76,175,80,0.2); }
            .password-form button { padding: 16px; background: #4CAF50; color: #fff; border: none; border-radius: 8px;
                font-size: 16px; font-weight: 600; cursor: pointer; font-family: inherit; }
            .password-form button:disabled { background: #555; cursor: default; }
            .password-toggle { display: flex; align-items: center; gap: 8px; color: #b0b0b0; font-size: 0.9rem;
                cursor: pointer; user-select: none; }
            .error-message { color: #ff6b6b; font-size: 14px; min-height: 20px; }
            .password-footer small { color: #777; font-size: 12px; }
            @media (max-width: 480px) { .password-prompt { padding: 30px 20px; } .password-header h2 { font-size: 1.5rem; } }
        </style>`);
    }

    window.SiteLock = SiteLock;
    window.SiteLockError = SiteLockError;
})();
