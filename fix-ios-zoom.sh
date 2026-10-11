#!/bin/bash
# Fix iOS auto-zoom on keyboard input for Godot web export
# Run after each export: ./fix-ios-zoom.sh
# Jeremy 2026-10-03: patch BOTH locations — crons and manual builds
# have used different dirs, and the fix was silently missing from uploads.
#
# Design notes (2026-10-03):
# - 16px (not 50px): iOS Safari only zooms when the focused input's font is
#   UNDER 16px. 16px is the documented threshold; 50px looked broken anywhere
#   the input is visible and gained us nothing.
# - NO touchend double-tap preventDefault: maximum-scale=1.0 + user-scalable=no
#   already kills double-tap zoom on modern iOS, and preventDefault() on
#   touchend suppresses synthesized click events, which breaks focus/taps on
#   mobile browsers (Android included). It was pure risk, no benefit.
# - Backspace is forwarded to the engine like Enter (see below): safety net for
#   the iOS backspace-desync bug (upstream godotengine/godot#72969 class).
for HTML in "$HOME/workspace/exports/web/index.html" "$HOME/workspace/godot-cursing-gnomes/exports/web/index.html"; do
if [ ! -f "$HTML" ]; then continue; fi
echo "Patching: $HTML"
export HTML

# 1. Add maximum-scale=1.0 to viewport (prevents iOS auto-zoom)
sed -i 's/content="width=device-width, user-scalable=no, initial-scale=1.0"/content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0"/' "$HTML"

# 1b. viewport-fit=cover: let the canvas extend edge-to-edge under the
# notch / Dynamic Island (Jeremy 2026-10-04: "background isn't taking up the
# whole screen"). Without this, WebKit letterboxes the page and the menu bg
# can't bleed full-screen. Safe-area padding is handled in-game (the menu
# ScrollContainer), so only art goes under the notch — never UI content.
# Idempotent: after the first run the pattern no longer matches.
sed -i 's/maximum-scale=1.0"/maximum-scale=1.0, viewport-fit=cover"/' "$HTML"

# 2. Inject anti-zoom JS before </body>
# Forces Godot's VK input to 17px font (iOS won't zoom on 16px+) and
# prevents pinch zoom. Deliberately does NOT touch touchend/click.
python3 << 'PYEOF'
import os
html_path = os.environ.get("HTML", "/home/hatch/workspace/exports/web/index.html")
with open(html_path, 'r') as f:
    content = f.read()

# Skip if already patched
# Self-healing: strip any previously injected ios-zoom-fix block first, so
# re-running the script after editing it migrates old patches instead of
# leaving stale code behind.
import re
old_block = re.compile(
    r"<script>\s*\n// ios-zoom-fix:.*?</script>", re.DOTALL)
stripped, n = old_block.subn("", content)
if n:
    print("Removed %d stale ios-zoom-fix block(s)" % n)
    content = stripped
if 'ios-zoom-fix' in content:
    print("Already patched, skipping")
else:
    fix_js = '''
<script>
// ios-zoom-fix: prevent iOS Safari auto-zoom on virtual keyboard.
// iOS zooms when a focused input's font-size is under 17px, so we force 16px.
// iOS 10+ ignores maximum-scale=1.0 (accessibility), so we use
// touch-action: manipulation to prevent double-tap zoom at the touch level.
// Jeremy 2026-10-06: #canvas gets touch-action: none so Safari NEVER hijacks
// a touch-drag as a page pan. Without it, the html/body pan-x pan-y above
// lets Safari claim vertical drags, fire touchcancel at the canvas, and kill
// Godot's ScrollContainer drag mid-gesture — taps worked but NO list in the
// phone (messages, contacts, everything) could be drag-scrolled.
// focus and synthesized clicks on mobile browsers.
(function() {
    // Force 17px font on any input Godot creates (iOS won't zoom on 16px+)
    const style = document.createElement('style');
    style.textContent = 'input, textarea, div.ime, [contenteditable="true"] { font-size: 17px !important; touch-action: manipulation; } html, body { touch-action: pan-x pan-y; } #canvas { touch-action: none !important; }';
    document.head.appendChild(style);

    // Watch for Godot's VK input and force 16px
    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(m) {
            m.addedNodes.forEach(function(node) {
                if (node.tagName === 'INPUT' || node.tagName === 'TEXTAREA') {
                    node.style.fontSize = '17px';
                }
            });
        });
    });
    observer.observe(document.body, { childList: true, subtree: true });

    // Catch IME div and any other focusable (GodotIME uses a 1px div!)
    document.addEventListener('focusin', function(e) {
        var t = e.target;
        if (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' ||
            t.classList.contains('ime') || t.contentEditable === 'true') {
            t.style.fontSize = '17px';
        }
    });

    // Prevent pinch zoom (iOS-specific gesture events; harmless elsewhere)
    document.addEventListener('gesturestart', function(e) { e.preventDefault(); });
    document.addEventListener('gesturechange', function(e) { e.preventDefault(); });
})();
</script>
</body>'''
    content = content.replace('</body>', fix_js)
    with open(html_path, 'w') as f:
        f.write(content)
    print("iOS zoom fix applied")
PYEOF

# 3. Patch index.js: bake 17px fontSize into Godot's VK input creation
# (export overwrites this, so re-apply every time), and forward Backspace
# keydown to the engine like Enter. Backspace forwarding is a safety net for
# the iOS backspace-desync bug: GodotInput.onKeyEvent calls preventDefault(),
# so when the input-event path works there is no double deletion; when it is
# broken, the keydown forward still deletes. On iOS the virtual keyboard
# often fires no keydown at all (input/beforeinput only), making this a
# harmless no-op there while helping Android/desktop.
python3 << 'PYEOF'
import os
_js_path = os.path.join(os.path.dirname(os.environ.get("HTML", "/home/hatch/workspace/exports/web/index.html")), "index.js")
with open(_js_path, 'r') as f:
    js = f.read()

# Normalize: an older version of this script used 50px. 16px is the real
# iOS threshold; downgrade any existing 50px patches idempotently.
if 'fontSize="50px"' in js:
    js = js.replace('fontSize="50px"', 'fontSize="17px"')
    print("Normalized 50px -> 16px")

old = 'elem.style.border="0px";elem.style.outline="none";'
new = 'elem.style.border="0px";elem.style.outline="none";elem.style.fontSize="17px";'
if old in js and 'fontSize="17px"' not in js[js.find(old):js.find(old)+120]:
    js = js.replace(old, new)
old2 = 'elem.style.display="block";elem.focus();'
new2 = 'elem.style.display="block";elem.style.fontSize="17px";elem.focus();'
if old2 in js:
    js = js.replace(old2, new2)
# GodotIME div uses 1px font — patch to 16px (iOS zooms on <16px)
if 'ime.style.fontSize="1px"' in js:
    js = js.replace('ime.style.fontSize="1px"', 'ime.style.fontSize="17px"')
# Forward Backspace keydown to the engine, mirroring the existing Enter path.
old3 = 'if(pEvent.key!=="Enter"){return}'
new3 = 'if(pEvent.key!=="Enter"&&pEvent.key!=="Backspace"){return}'
if old3 in js and 'Backspace' not in js[js.find(old3):js.find(old3)+80]:
    js = js.replace(old3, new3)
    print("Backspace keydown forwarding added")
# Silence the unhandled getRegistration() rejection (file:// and some
# webviews reject; the boot tracer would otherwise print a scary-but-harmless
# "PROMISE REJECTED" line on the loader). No-op when it resolves.
old_sw = 'serviceWorker.getRegistration().then(GodotPWA.updateState.bind(null,cb))'
new_sw = 'serviceWorker.getRegistration().then(GodotPWA.updateState.bind(null,cb),function(){})'
if old_sw in js:
    seg = js[js.find(old_sw):js.find(old_sw)+len(old_sw)+16]
    if ',function(){})' not in seg:
        js = js.replace(old_sw, new_sw, 1)
        print("serviceWorker rejection handler added")
with open(_js_path, 'w') as f:
    f.write(js)
print("JS fontSize patch applied")
PYEOF

# 4. Prevent canvas rescale when iOS keyboard opens/closes.
# When the VK input shows, lock the canvas CSS size; restore on hide.
python3 << 'PYEOF'
import os
html_path = os.environ.get("HTML", "/home/hatch/workspace/exports/web/index.html")
with open(html_path, 'r') as f:
    content = f.read()

if 'vk-canvas-lock' in content:
    print("Canvas lock already present")
else:
    lock_js = '''
<script>
// vk-canvas-lock: keep canvas size stable when iOS keyboard opens/closes.
// Godot's adaptive resize shrinks the canvas when the keyboard appears,
// which looks like a zoom that never restores.
(function() {
    var canvas = null;
    var lockedW = null, lockedH = null;
    function getCanvas() {
        if (!canvas) canvas = document.getElementById('canvas');
        return canvas;
    }
    // Watch for Godot's VK input becoming visible/hidden.
    var obs = new MutationObserver(function(muts) {
        muts.forEach(function(m) {
            if (m.type !== 'attributes' || m.attributeName !== 'style') return;
            var el = m.target;
            if (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') return;
            var c = getCanvas();
            if (!c) return;
            if (el.style.display === 'block' && lockedW === null) {
                // Keyboard opening: lock canvas to current size.
                var r = c.getBoundingClientRect();
                lockedW = r.width; lockedH = r.height;
                c.style.width = lockedW + 'px';
                c.style.height = lockedH + 'px';
            } else if (el.style.display === 'none' && lockedW !== null) {
                // Keyboard closed: release the lock, let Godot resize.
                c.style.width = '';
                c.style.height = '';
                lockedW = null; lockedH = null;
            }
        });
    });
    // Start observing once body exists.
    function start() {
        if (document.body) {
            obs.observe(document.body, { attributes: true, subtree: true, attributeFilter: ['style'] });
        } else {
            setTimeout(start, 100);
        }
    }
    start();
})();
</script>
</body>'''
    content = content.replace('</body>', lock_js)
    with open(html_path, 'w') as f:
        f.write(content)
    print("Canvas lock added")
PYEOF

# 5. thermal-dpr-cap: cap the devicePixelRatio the engine sees at 2 on
# high-DPR phones (Jeremy 2026-10-07 thermal report: iPhone 17 renders the
# Godot canvas at DPR 3 = ~3.2M physical px/frame of fragment work while
# holding 59fps — pure heat with no frame drop for adaptive quality to
# react to). Same CSS layout, same game pixels, ~55% less fragment shading;
# pixel art on a 458 PPI panel is visually identical at DPR 2. The HTML
# original scaled DPR with the graphics tier; the Godot port lost that knob
# (see graphics_tiers.gd) — this restores the high-tier behavior in the shell.
# The shim MUST run before <script src="index.js">: the engine reads
# window.devicePixelRatio when sizing the canvas at boot. try/catch: if a
# browser ever makes the property non-configurable we silently keep native
# DPR (no-op, never breaks boot) — the index.js patch below is the fallback.
python3 << 'PYEOF'
import os, re
html_path = os.environ.get("HTML", "/home/hatch/workspace/exports/web/index.html")
with open(html_path, 'r') as f:
    content = f.read()

# Self-healing: strip stale thermal-dpr-cap blocks first.
old_block = re.compile(r"<script>\s*\n// thermal-dpr-cap:.*?</script>", re.DOTALL)
stripped, n = old_block.subn("", content)
if n:
    print("Removed %d stale thermal-dpr-cap block(s)" % n)
    content = stripped
if 'thermal-dpr-cap' in content:
    print("DPR cap already present")
elif '<script src="index.js">' not in content:
    print("WARN: index.js script tag not found, DPR shim skipped")
else:
    dpr_js = '''
<script>
// thermal-dpr-cap: cap engine-visible devicePixelRatio at 2 (see
// fix-ios-zoom.sh section 5). Installed before index.js on purpose.
(function() {
    try {
        var nativeDPR = window.devicePixelRatio || 1;
        if (nativeDPR > 2) {
            Object.defineProperty(window, 'devicePixelRatio', {
                configurable: true,
                get: function() { return 2; }
            });
        }
    } catch (e) { /* keep native DPR */ }
})();
</script>
<script src="index.js">'''
    content = content.replace('<script src="index.js">', dpr_js, 1)
    with open(html_path, 'w') as f:
        f.write(content)
    print("thermal-dpr-cap shim injected")

# Fallback: cap inside the engine's own getPixelRatio (deterministic even if
# a browser refuses the defineProperty above). Conditional: if the minified
# pattern ever changes with an engine upgrade, this warns and skips.
_js_path = os.path.join(os.path.dirname(html_path), "index.js")
with open(_js_path, 'r') as f:
    js = f.read()
anchor = "GodotDisplayScreen.hidpi?window.devicePixelRatio||1:1"
capped = "GodotDisplayScreen.hidpi?Math.min(2,window.devicePixelRatio||1):1"
if capped in js:
    print("index.js DPR cap already present")
elif anchor in js:
    js = js.replace(anchor, capped, 1)
    with open(_js_path, 'w') as f:
        f.write(js)
    print("index.js getPixelRatio capped at 2")
else:
    print("WARN: getPixelRatio anchor not found in index.js, shim only")
PYEOF
# 6. cg-loader: branded web loading screen (Jeremy 2026-10-08 wake
# rapid-iteration). The stock Godot loader is a gray bar on black — Jeremy
# stares at it on every iPhone launch while the ~200MB pck downloads.
# Injects a "CURSING GNOMES" gold title, the company motto, and rotating
# gameplay tips into the engine's own #status overlay. SAFE BY
# CONSTRUCTION: the engine REMOVES #status from the DOM when the game
# boots (setStatusMode('hidden') -> statusOverlay.remove()), so the brand
# layer can never get stuck covering the game; the tips rotator is a
# try/catch IIFE that self-clears when #status disappears. Tips mirror
# MainMenu.MENU_TIPS (scripts/ui/main_menu.gd) — keep in sync when that
# list changes. ASCII ONLY (iPhone tofu rule). Title sits below the
# Dynamic Island, tip above the home bar via safe-area env().
python3 << 'PYEOF'
import os, re
html_path = os.environ.get("HTML", "/home/hatch/workspace/exports/web/index.html")
with open(html_path, 'r') as f:
    content = f.read()

# Self-healing: strip stale cg-loader blocks first (CSS, HTML, JS).
# Patterns consume one surrounding newline each side so strip+re-inject
# is byte-identical (no blank-line accumulation across runs).
for pat in [r"<style>\n/\* cg-loader:.*?\*/\s*</style>\n?",
            r"\n?<!-- cg-loader:.*?<!-- /cg-loader -->",
            r"\n?<script>\n// cg-loader:.*?\n// /cg-loader\n</script>\n?"]:
    stripped, n = re.compile(pat, re.DOTALL).subn("", content)
    if n:
        print("Removed %d stale cg-loader block(s)" % n)
        content = stripped

if 'cg-loader-title' in content:
    print("cg-loader already present")
elif '<div id="status">' not in content:
    print("WARN: #status overlay not found, cg-loader skipped")
else:
    css = '''<style>
/* cg-loader: branded loading screen (fix-ios-zoom.sh section 6). */
#cg-loader-title {
    position: absolute;
    top: calc(env(safe-area-inset-top, 0px) + 5%);
    left: 0; right: 0;
    text-align: center;
    font-family: Georgia, 'Times New Roman', serif;
    font-size: clamp(30px, 8vw, 68px);
    font-weight: bold;
    letter-spacing: 0.14em;
    color: #ffd75e;
    text-shadow: 0 2px 0 #5a3c00, 0 0 26px rgba(255, 215, 94, 0.35);
    pointer-events: none;
    z-index: 2;
}
#cg-loader-motto {
    position: absolute;
    top: calc(env(safe-area-inset-top, 0px) + 5% + clamp(44px, 10vw, 88px));
    left: 0; right: 0;
    text-align: center;
    font-family: Georgia, 'Times New Roman', serif;
    font-style: italic;
    font-size: clamp(12px, 3vw, 20px);
    color: #c9a227;
    opacity: 0.9;
    pointer-events: none;
    z-index: 2;
}
#cg-loader-tip {
    position: absolute;
    bottom: calc(env(safe-area-inset-bottom, 0px) + 3%);
    left: 5%; right: 5%;
    text-align: center;
    font-family: 'Noto Sans', 'Droid Sans', Arial, sans-serif;
    font-size: clamp(12px, 3.2vw, 18px);
    line-height: 1.35;
    color: #d8c48f;
    text-shadow: 0 1px 2px #000;
    pointer-events: none;
    z-index: 2;
}
#cg-loader-tip b { color: #ffd75e; }
/* /cg-loader */
</style>'''
    content = content.replace('</head>', css + '\n</head>', 1)

    brand = '''<!-- cg-loader: brand overlay (fix-ios-zoom.sh section 6) -->
<div id="cg-loader-title">CURSING GNOMES</div>
<div id="cg-loader-motto">No microtransactions. No bullshit.</div>
<div id="cg-loader-tip"></div>
<!-- /cg-loader -->'''
    content = re.sub(r'(<img id="status-splash"[^>]*>)',
                     r'\1\n' + brand, content, count=1)

    tips_js = '''
<script>
// cg-loader: rotating loading-screen tips (fix-ios-zoom.sh section 6).
// Tips mirror MainMenu.MENU_TIPS (scripts/ui/main_menu.gd). ASCII only.
// Self-clearing: the engine removes #status from the DOM on boot.
(function () {
    try {
        var TIPS = [
            "Tap the crown button to snap the camera back to your capitol. (Jeremy's idea)",
            "Beware the Stinky Gizmundo. It smells worse than it fights. (Jeremy's idea)",
            "Deny a build petition and your advisers will not ask again for 3 days.",
            "Open the Realm menu to slow time to 0.25x turtle speed and savor the battle.",
            "Losing a war? Your War Advisor pleads in Messenger. Tap Accept or Deny.",
            "Talk to your cabinet in Messenger. Try: build 3 farms.",
            "Monasteries are the true prize of war. Hold one and the land is yours.",
            "Idle fighters spend their own coins on weapon upgrades at the smith.",
            "Starving? Rival factions yank workers onto berry duty. Your adviser only warns you.",
            "The Gazette Chronicle keeps every story. The toast is just the headline.",
            "Tap outside any popup to close it.",
            "Peace is signed in the diplomacy tab. The tabs are big now. No accidental wars.",
            "A doom prophet preaching in your town? March a soldier at him. He will flee.",
            "A gig gnome circling your town and skimming delivery fees? March a soldier at him. He will mark your order 'delivered' and speed off."
        ];
        var last = -1;
        function show() {
            var el = document.getElementById("cg-loader-tip");
            if (!el) { clearInterval(timer); return; }
            var i = Math.floor(Math.random() * TIPS.length);
            if (TIPS.length > 1) {
                while (i === last) { i = Math.floor(Math.random() * TIPS.length); }
            }
            last = i;
            el.innerHTML = "<b>TIP:</b> " + TIPS[i];
        }
        var timer = setInterval(show, 4000);
        show();
    } catch (e) { /* loader stays static; never break boot */ }
})();
// /cg-loader
</script>
</body>'''
    content = content.replace('</body>', tips_js, 1)
    with open(html_path, 'w') as f:
        f.write(content)
    print("cg-loader branded loading screen injected")
PYEOF

# 7. cg-bootlog: boot tracer + on-screen failure reporter (Jeremy 2026-10-08:
# "doesn't even load in" with zero diagnostics). A bulletproof IIFE that runs
# BEFORE index.js and:
#   - captures window.onerror + unhandledrejection and prints the message ON
#     the loading screen (today a boot exception is invisible), plus a
#     localStorage ring buffer, so a relaunch after a kill shows last words;
#   - wraps window.fetch for *.pck and shows live "142/206 MB" progress in
#     the loader (Jeremy stares at a dead gray bar during the ~200MB pull);
#   - mirrors the engine's own #status-notice text into the log.
# Every probe is try/catch-guarded and feature-checked; on any doubt the
# original fetch/response passes through untouched. The engine removes #status
# on boot, which hides the log. ASCII only (iPhone tofu rule).
python3 << 'PYEOF'
import os, re
html_path = os.environ.get("HTML", "/home/hatch/workspace/exports/web/index.html")
with open(html_path, 'r') as f:
    content = f.read()

# Self-healing: strip stale cg-bootlog blocks first.
old_block = re.compile(r"<script>\s*\n// cg-bootlog:.*?</script>", re.DOTALL)
stripped, n = old_block.subn("", content)
if n:
    print("Removed %d stale cg-bootlog block(s)" % n)
    content = stripped

if 'cg-bootlog' in content:
    print("cg-bootlog already present")
elif '<script src="index.js">' not in content:
    print("WARN: index.js script tag not found, cg-bootlog skipped")
else:
    bootlog_js = '''
<script>
// cg-bootlog: boot tracer + on-screen failure reporter (fix-ios-zoom.sh section 7).
(function () {
    try {
        var LS = 'cg_bootlog_v1';
        var logEl = null, lastLive = 0;
        function findEl() {
            if (!logEl) {
                logEl = document.getElementById('cg-bootlog');
                if (!logEl) {
                    var host = document.getElementById('status') || document.body;
                    if (!host) return null;
                    logEl = document.createElement('div');
                    logEl.id = 'cg-bootlog';
                    logEl.setAttribute('style', 'position:absolute;left:5%;right:5%;bottom:calc(env(safe-area-inset-bottom,0px) + 12%);text-align:center;font-family:ui-monospace,Menlo,monospace;font-size:11px;line-height:1.5;color:#9fd48a;text-shadow:0 1px 2px #000;pointer-events:none;z-index:3;white-space:pre-wrap;word-break:break-word;');
                    host.appendChild(logEl);
                }
            }
            return logEl;
        }
        function persist(msg) {
            try {
                var arr = JSON.parse(localStorage.getItem(LS) || '[]');
                arr.push(new Date().toISOString().slice(11, 19) + ' ' + msg);
                while (arr.length > 40) arr.shift();
                localStorage.setItem(LS, JSON.stringify(arr));
            } catch (e) { /* private mode etc */ }
        }
        function live(msg) {
            try {
                var now = Date.now();
                if (now - lastLive < 400 && msg.indexOf('MB') !== -1) return;
                lastLive = now;
                var e = findEl();
                if (!e) return;
                var lines = (e.textContent || '').split('\\n');
                lines.push(msg);
                while (lines.length > 6) lines.shift();
                e.textContent = lines.join('\\n');
            } catch (e2) {}
        }
        function say(msg) { persist(msg); live(msg); }
        try {
            var prev = JSON.parse(localStorage.getItem(LS) || '[]');
            if (prev.length) live('last boot ended at: ' + prev[prev.length - 1]);
        } catch (e) {}
        say('shell ready, tracer armed');
        window.addEventListener('error', function (ev) {
            var m = ev.message || (ev.error && (ev.error.stack || ev.error.message)) || 'unknown error';
            say('JS ERROR: ' + String(m).slice(0, 180));
        });
        window.addEventListener('unhandledrejection', function (ev) {
            var r = ev.reason;
            var m = (r && (r.message || r.stack)) || String(r);
            say('PROMISE REJECTED: ' + String(m).slice(0, 180));
        });
        function armDom() {
            try {
                var notice = document.getElementById('status-notice');
                if (notice && window.MutationObserver) {
                    new MutationObserver(function () {
                        var t = (notice.textContent || '').trim().split('\\n')[0];
                        if (t) say('engine: ' + t.slice(0, 140));
                    }).observe(notice, { childList: true, subtree: true, characterData: true });
                }
                var st = document.getElementById('status');
                if (st && window.MutationObserver && document.body) {
                    new MutationObserver(function () {
                        if (!document.getElementById('status')) {
                            var e = document.getElementById('cg-bootlog');
                            if (e) e.style.display = 'none';
                        }
                    }).observe(document.body, { childList: true });
                }
            } catch (e) {}
        }
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', armDom);
        } else { armDom(); }
        try {
            var origFetch = window.fetch;
            var canStream = (typeof ReadableStream !== 'undefined') && (typeof Response !== 'undefined');
            if (origFetch && canStream) {
                window.fetch = function (url, opts) {
                    var s = (typeof url === 'string') ? url : ((url && url.url) || '');
                    if (s.toLowerCase().indexOf('.pck') === -1) {
                        return origFetch.apply(this, arguments);
                    }
                    var name = s.split('/').pop().split('?')[0] || 'game.pck';
                    say('downloading ' + name + ' ...');
                    return origFetch.apply(this, arguments).then(function (resp) {
                        if (resp.status !== 200 || !resp.body || !resp.body.getReader) return resp;
                        var total = parseInt(resp.headers.get('content-length') || '0', 10) || 0;
                        var reader;
                        try { reader = resp.body.getReader(); }
                        catch (e) { return resp; }
                        var loaded = 0;
                        var stream = new ReadableStream({
                            start: function (ctrl) {
                                function pump() {
                                    return reader.read().then(function (r) {
                                        if (r.done) {
                                            say(name + ' done (' + (loaded / 1048576).toFixed(0) + ' MB)');
                                            ctrl.close(); return;
                                        }
                                        loaded += r.value.byteLength;
                                        live(name + ' ' + (loaded / 1048576).toFixed(0) + (total > 0 ? '/' + (total / 1048576).toFixed(0) : '') + ' MB');
                                        ctrl.enqueue(r.value);
                                        return pump();
                                    }, function (err) {
                                        say('download failed: ' + String(err).slice(0, 120));
                                        ctrl.error(err);
                                    });
                                }
                                return pump();
                            }
                        });
                        return new Response(stream, { status: resp.status, statusText: resp.statusText, headers: resp.headers });
                    }, function (err) {
                        say('download failed: ' + String(err).slice(0, 120));
                        throw err;
                    });
                };
            }
        } catch (e) {}
        // Watchdog (2026-10-11): a stuck boot must never go silent again.
        try {
            var pck = { started: false, done: false, loaded: 0, lastMove: 0, doneAt: 0, stallSaid: false, nostartSaid: false };
            window.__cgPck = pck;
            var _say = say;
            // Hook progress: wrap live() calls for .pck MB lines is complex, so
            // instead patch via the fetch wrapper above is not accessible here;
            // we track via a MutationObserver-free poll of the log element.
            setInterval(function () {
                try {
                    var el = document.getElementById('cg-bootlog');
                    var txt = el ? (el.textContent || '') : '';
                    var now = Date.now();
                    if (!pck.started && txt.indexOf('downloading ') !== -1 && txt.indexOf('.pck') !== -1) {
                        pck.started = true; pck.lastMove = now;
                    }
                    if (pck.started && !pck.done) {
                        var m = txt.match(/(\\d+) MB/g);
                        if (m && m.length) {
                            var mb = parseInt(m[m.length - 1], 10);
                            if (mb !== pck.loaded) { pck.loaded = mb; pck.lastMove = now; }
                        }
                        if (txt.indexOf('done (') !== -1 && txt.indexOf('MB)') !== -1) {
                            pck.done = true; pck.doneAt = now;
                        }
                        if (!pck.stallSaid && now - pck.lastMove > 30000) {
                            pck.stallSaid = true;
                            _say('download STALLED at ~' + pck.loaded + ' MB for 30s — the game file may be missing or incomplete; delete and re-import the build');
                        }
                    }
                    if (pck.done && !pck.nostartSaid && now - pck.doneAt > 30000) {
                        var statusGone = !document.getElementById('status');
                        var canvas = document.querySelector('canvas');
                        if (!statusGone || !canvas) {
                            pck.nostartSaid = true;
                            _say('pck done but engine did not start within 30s — likely a webview/engine issue, screenshot this');
                        }
                    }
                } catch (e2) {}
            }, 5000);
        } catch (e) {}
    } catch (e) { /* never break boot */ }
})();
</script>
<script src="index.js">'''
    content = content.replace('<script src="index.js">', bootlog_js, 1)
    with open(html_path, 'w') as f:
        f.write(content)
    print("cg-bootlog tracer injected")
PYEOF
done
echo "All locations patched"
