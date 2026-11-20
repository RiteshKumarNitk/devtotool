/// Built-in extensions, injected at document start (before page scripts) in
/// every frame: tracker/ad blocking, element hiding, force dark mode and
/// cookie-banner hiding. `__CONFIG__` is replaced with a JSON object.
///
/// Raw Dart string: no Dart interpolation; JavaScript needs no escaping.
const String extensionsCoreJs = r'''
(function (CFG) {
    if (window.__dbg_ext) return;
    window.__dbg_ext = true;

    var isTop = window.top === window;
    var host = (location.hostname || '').toLowerCase().replace(/^www\./, '');

    function send(type, data) {
        try {
            if (window.DebugBridge && window.DebugBridge.postMessage) {
                window.DebugBridge.postMessage(JSON.stringify({ type: type, data: data, timestamp: Date.now() }));
            }
        } catch (e) { }
    }

    // Per-site override lookup: exact host, then parent domains.
    function siteSetting(key, fallback) {
        var h = host;
        while (h) {
            var o = CFG.sites && CFG.sites[h];
            if (o && typeof o[key] === 'boolean') return o[key];
            var dot = h.indexOf('.');
            if (dot < 0) break;
            h = h.substring(dot + 1);
        }
        return fallback;
    }
    // The top page's host decides for its iframes too (ads live in iframes).
    try { if (!isTop && window.top.location.hostname) host = window.top.location.hostname.toLowerCase().replace(/^www\./, ''); } catch (e) { }

    function addStyle(css, id) {
        var s = document.createElement('style');
        if (id) s.id = id;
        s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
        return s;
    }

    // ------------------------------------------------------------ blocker
    var blockerOn = CFG.blocker && siteSetting('blocker', true);
    if (blockerOn) {
        var domains = {};
        (CFG.blockDomains || []).forEach(function (d) { domains[d] = true; });
        var pageIsTracker = matchDomain(host);
        var pending = 0, pendingDomains = {}, timer = null;

        function matchDomain(h) {
            h = (h || '').toLowerCase();
            while (h) {
                if (domains[h]) return h;
                var dot = h.indexOf('.');
                if (dot < 0) return null;
                h = h.substring(dot + 1);
            }
            return null;
        }
        function blocked(url) {
            if (pageIsTracker || !url) return false;
            var u;
            try { u = new URL(String(url), location.href); } catch (e) { return false; }
            if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
            var d = matchDomain(u.hostname);
            if (!d) return false;
            pending++;
            pendingDomains[d] = (pendingDomains[d] || 0) + 1;
            if (!timer) timer = setTimeout(function () {
                send('blocked', { n: pending, domains: pendingDomains });
                pending = 0; pendingDomains = {}; timer = null;
            }, 400);
            return true;
        }
        window.__dbg_isBlocked = blocked;

        var realFetch = window.fetch;
        if (realFetch) window.fetch = function (input, init) {
            var url = input && input.url ? input.url : input;
            if (blocked(url)) return Promise.reject(new TypeError('Blocked by Debug Browser'));
            return realFetch.apply(this, arguments);
        };
        var xo = XMLHttpRequest.prototype.open, xs = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function (m, url) { this.__dbgBlocked = blocked(url); return xo.apply(this, arguments); };
        XMLHttpRequest.prototype.send = function () {
            if (this.__dbgBlocked) {
                var x = this;
                setTimeout(function () { x.dispatchEvent(new Event('error')); x.dispatchEvent(new Event('loadend')); }, 0);
                return;
            }
            return xs.apply(this, arguments);
        };
        if (navigator.sendBeacon) {
            var beacon = navigator.sendBeacon.bind(navigator);
            navigator.sendBeacon = function (url) { return blocked(url) ? true : beacon.apply(null, arguments); };
        }

        // src on script / iframe / img, via property and setAttribute.
        function failLater(el) { setTimeout(function () { try { el.dispatchEvent(new Event('error')); } catch (e) { } }, 0); }
        [HTMLScriptElement, HTMLIFrameElement, HTMLImageElement].forEach(function (Ctor) {
            var desc = Object.getOwnPropertyDescriptor(Ctor.prototype, 'src');
            if (!desc || !desc.set) return;
            Object.defineProperty(Ctor.prototype, 'src', {
                configurable: true, enumerable: desc.enumerable,
                get: desc.get,
                set: function (v) { if (blocked(v)) { failLater(this); return; } desc.set.call(this, v); }
            });
        });
        var setAttr = Element.prototype.setAttribute;
        Element.prototype.setAttribute = function (name, value) {
            if (String(name).toLowerCase() === 'src' && /^(SCRIPT|IFRAME|IMG)$/.test(this.tagName) && blocked(value)) {
                failLater(this);
                return;
            }
            return setAttr.apply(this, arguments);
        };

        // Parser-inserted elements: best effort before they run/load.
        new MutationObserver(function (records) {
            records.forEach(function (r) {
                r.addedNodes && r.addedNodes.forEach(function (n) {
                    if (n.nodeType !== 1) return;
                    var tag = n.tagName;
                    if ((tag === 'SCRIPT' || tag === 'IFRAME' || tag === 'IMG') && n.getAttribute('src') && blocked(n.getAttribute('src'))) {
                        if (tag === 'SCRIPT') n.type = 'javascript/blocked';
                        n.removeAttribute('src');
                        if (tag !== 'SCRIPT') n.style.setProperty('display', 'none', 'important');
                    }
                });
            });
        }).observe(document.documentElement, { childList: true, subtree: true });

        // Element hiding for common ad slots.
        if (CFG.cosmetic) addStyle([
            'ins.adsbygoogle', '.adsbygoogle', '[id^="google_ads_iframe"]', '[id^="div-gpt-ad"]',
            '[data-ad-slot]', '[data-google-query-id]', 'iframe[src*="doubleclick.net"]',
            'iframe[src*="googlesyndication.com"]', '.trc_rbox_container', '.OUTBRAIN', '[id^="taboola-"]',
            'amp-ad', 'amp-embed[type="taboola"]'
        ].join(',') + '{display:none!important}', '__dbg_cosmetic');
    }

    // ------------------------------------------- pop-ups and click-jacking
    // Chrome-like rule: a page may only open a new window when the user just
    // tapped a real link to that site. Invisible full-screen layers that
    // steal the first tap are removed. Runs in every frame (ad iframes call
    // window.open too).
    var popupsOn = CFG.popups && siteSetting('popups', true);
    var lastGesture = 0, lastTarget = null;
    ['pointerdown', 'touchstart', 'mousedown', 'keydown', 'click'].forEach(function (type) {
        window.addEventListener(type, function (e) { lastGesture = Date.now(); lastTarget = e.target; }, true);
    });
    function hostOf(u) { try { return new URL(u, location.href).hostname.replace(/^www\./, ''); } catch (e) { return ''; } }
    function sameSite(a, b) { return !!a && !!b && (a === b || a.slice(-b.length - 1) === '.' + b || b.slice(-a.length - 1) === '.' + a); }
    var pageHost = (location.hostname || '').replace(/^www\./, '');

    function visuallyEmpty(n, cs) {
        if (/^(IFRAME|VIDEO|CANVAS|IMG|EMBED|OBJECT)$/.test(n.tagName)) return false;
        if (n.querySelector('iframe,video,canvas,embed,object')) return false; // players stay
        if ((n.innerText || n.textContent || '').trim().length > 3) return false;
        var opacity = parseFloat(cs.opacity);
        if (n.querySelector('img,svg,picture') && !(opacity < 0.15)) return false;
        var bg = cs.backgroundColor || '';
        var transparent = bg === 'transparent' || /rgba\([^)]*,\s*0(\.0+)?\)$/.test(bg);
        return transparent || opacity < 0.15;
    }
    /** The invisible click-jacking layer containing el, or null. */
    function overlayOf(el) {
        var vw = window.innerWidth, vh = window.innerHeight;
        for (var n = el; n && n.nodeType === 1 && n !== document.body && n !== document.documentElement; n = n.parentElement) {
            var cs = getComputedStyle(n);
            if (cs.position !== 'fixed' && cs.position !== 'absolute') continue;
            var r = n.getBoundingClientRect();
            if (r.width * r.height < vw * vh * 0.5) continue;
            if (!visuallyEmpty(n, cs)) continue;
            var link = n.closest('a[href]') || n.querySelector('a[href]');
            var foreignLink = link && !sameSite(hostOf(link.href), pageHost);
            var onTop = (parseInt(cs.zIndex, 10) || 0) >= 999;
            if (foreignLink || onTop) return n;
        }
        return null;
    }
    function reportBlocked(kind, n) {
        var d = {}; d[kind] = n || 1;
        send('blocked', { n: n || 1, domains: d });
    }
    function allowPopup(url) {
        if (!popupsOn) return true;
        if (Date.now() - lastGesture > 1000) return false;          // not from a tap
        var target = hostOf(url);
        if (sameSite(target, pageHost)) return true;                // own site (e.g. sign-in)
        var a = lastTarget && lastTarget.closest ? lastTarget.closest('a[href]') : null;
        if (a && !overlayOf(a) && sameSite(hostOf(a.href), target)) return true; // tapped a real link to it
        return false;                                                // tap elsewhere -> pop-under
    }
    function blockPopup(url) {
        reportBlocked('pop-ups');
        try { send('popup_blocked', { href: new URL(url, location.href).href }); } catch (e) { }
    }
    window.__dbg_allowPopup = allowPopup;
    window.__dbg_blockPopup = blockPopup;
    window.__dbg_overlayOf = overlayOf;

    if (popupsOn) {
        var nativeOpen = window.open;
        window.open = function (url) {
            if (!allowPopup(url || '')) { blockPopup(url || ''); return null; }
            return nativeOpen ? nativeOpen.apply(window, arguments) : null;
        };
        // Swallow the tap that lands on an invisible layer, and remove it,
        // so the next tap reaches the real content.
        var guard = function (e) {
            var ov = overlayOf(e.target);
            if (!ov) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            ov.remove();
            reportBlocked('hidden overlays');
        };
        window.addEventListener('pointerdown', guard, true);
        window.addEventListener('click', guard, true);
        // Also sweep likely layers as the page builds itself.
        var sweepTimer = null;
        var sweep = function () {
            sweepTimer = null;
            if (!document.body) return;
            var removed = 0;
            var candidates = document.querySelectorAll('body > *, [style*="z-index"], a[style*="position"], div[style*="position"]');
            for (var i = 0; i < candidates.length && i < 400; i++) {
                var el = candidates[i];
                if (el.isConnected && overlayOf(el) === el) { el.remove(); removed++; }
            }
            if (removed) reportBlocked('hidden overlays', removed);
        };
        document.addEventListener('DOMContentLoaded', sweep);
        new MutationObserver(function () { if (!sweepTimer) sweepTimer = setTimeout(sweep, 400); })
            .observe(document.documentElement, { childList: true, subtree: true });
    }

    if (!isTop) return;

    // ------------------------------------------------- browser UI signals
    // The page lives in a native view, so the app can't see its scrolling:
    // report scroll direction (auto-hiding toolbars) and pull-down-at-top
    // gestures (pull to refresh). Passive listeners: never block scrolling.
    (function () {
        var lastY = 0, lastDir = '', acc = 0, frame = false;
        function yOf(t) {
            if (!t || t === document || t === document.documentElement || t === document.body) return window.scrollY || 0;
            return t.scrollTop || 0;
        }
        document.addEventListener('scroll', function (e) {
            if (frame) return;
            frame = true;
            requestAnimationFrame(function () {
                frame = false;
                var y = yOf(e.target);
                var d = y - lastY;
                lastY = y;
                acc = (d > 0) === (acc > 0) ? acc + d : d;
                var dir = y < 24 ? 'top' : acc > 40 ? 'down' : acc < -40 ? 'up' : lastDir;
                if (dir !== lastDir) { lastDir = dir; send('ui', { kind: 'scroll', dir: dir }); }
            });
        }, { capture: true, passive: true });

        // Pull to refresh: only when the page (and the touched scroller) is at the top.
        var startY = null, pulling = false, lastSent = 0;
        function scrolledAncestor(el) {
            for (var n = el; n && n.nodeType === 1; n = n.parentElement) {
                if (n.scrollTop > 0) return true;
            }
            return false;
        }
        window.addEventListener('touchstart', function (e) {
            startY = (e.touches.length === 1 && (window.scrollY || 0) <= 0 && !scrolledAncestor(e.target)) ? e.touches[0].clientY : null;
            pulling = false;
        }, { passive: true });
        window.addEventListener('touchmove', function (e) {
            if (startY === null) return;
            var d = e.touches[0].clientY - startY;
            if ((window.scrollY || 0) > 0 || d < 0) { if (pulling) send('ui', { kind: 'pull', state: 'cancel' }); startY = null; pulling = false; return; }
            if (d < 12) return;
            pulling = true;
            var now = Date.now();
            if (now - lastSent > 32) { lastSent = now; send('ui', { kind: 'pull', state: 'move', d: Math.round(d) }); }
        }, { passive: true });
        window.addEventListener('touchend', function (e) {
            if (!pulling) { startY = null; return; }
            var d = (e.changedTouches[0] ? e.changedTouches[0].clientY : 0) - startY;
            send('ui', { kind: 'pull', state: 'release', d: Math.round(d) });
            startY = null; pulling = false;
        }, { passive: true });
        window.addEventListener('touchcancel', function () {
            if (pulling) send('ui', { kind: 'pull', state: 'cancel' });
            startY = null; pulling = false;
        }, { passive: true });
    })();

    // Site icon: the page's best declared icon, else /favicon.ico.
    window.addEventListener('load', function () {
        try {
            var best = null, bestSize = -1;
            document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]').forEach(function (l) {
                var href = l.href;
                if (!href || !/^https?:/.test(href)) return;
                var sizes = (l.getAttribute('sizes') || '').split(/\s+/).map(function (s) { return parseInt(s, 10) || 0; });
                var size = Math.max.apply(null, sizes.concat([/apple-touch/.test(l.rel) ? 180 : 16]));
                // Prefer ~64-192px icons: crisp without being huge.
                var score = size > 256 ? 256 - (size - 256) / 4 : size;
                if (score > bestSize) { bestSize = score; best = href; }
            });
            send('favicon', { href: best || (location.origin + '/favicon.ico') });
        } catch (e) { }
    });

    // ---------------------------------------------------------- dark mode
    if (CFG.dark && siteSetting('dark', true)) {
        var dark = addStyle(
            'html{filter:invert(0.92) hue-rotate(180deg)!important;background:#fff!important}' +
            'img,video,picture,canvas,iframe,embed,object,svg image,[style*="background-image"]' +
            '{filter:invert(1) hue-rotate(180deg)!important}', '__dbg_dark');
        // Sites that are already dark keep their own colours: measure the
        // page background with our filter briefly off, and drop it if dark.
        function backgroundLuminance() {
            var els = [document.body, document.documentElement];
            for (var i = 0; i < els.length; i++) {
                if (!els[i]) continue;
                var m = getComputedStyle(els[i]).backgroundColor.match(/rgba?\(([^)]+)\)/);
                if (!m) continue;
                var p = m[1].split(',').map(parseFloat);
                if (p.length > 3 && p[3] === 0) continue; // transparent: look further up
                return (0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]) / 255;
            }
            return 1; // default canvas is white
        }
        document.addEventListener('DOMContentLoaded', function () {
            dark.disabled = true;
            var lum = 1;
            try { lum = backgroundLuminance(); } catch (e) { }
            dark.disabled = false;
            if (lum < 0.4) dark.remove();
        });
    }

    // ------------------------------------------------- cookie banners
    if (CFG.cookies && siteSetting('cookies', true)) {
        var sel = [
            '#onetrust-banner-sdk', '#onetrust-consent-sdk', '.onetrust-pc-dark-filter', '#CybotCookiebotDialog',
            '#CybotCookiebotDialogBodyUnderlay', '.qc-cmp2-container', '#qc-cmp2-container', '.fc-consent-root',
            '#truste-consent-track', '.truste_box_overlay', '#cookie-law-info-bar', '.cc-window', '.cc-banner',
            '#usercentrics-root', '#didomi-host', '.didomi-popup-backdrop', '#cmpbox', '#cmpbox2', '.cmp-root',
            '#sp_message_container', '[id^="sp_message_container"]', '.osano-cm-window', '#iubenda-cs-banner',
            '#cookiescript_injected', '.cookie-notice-container', '#cookie-notice', '#gdpr-cookie-message'
        ];
        addStyle(sel.join(',') + '{display:none!important;visibility:hidden!important}' +
            sel.map(function (s) { return 'html:has(' + s + '),body:has(' + s + ')'; }).join(',') +
            '{overflow:auto!important;position:static!important}', '__dbg_cookies');
    }
})(__CONFIG__);
''';

/// Wraps a user script so it only runs on matching pages, can't break other
/// scripts, and runs at the requested time. Raw template; `__META__` and
/// `__BODY__` are replaced (body is inserted verbatim, CSS as JSON).
const String userScriptTemplate = r'''
(function (META) {
    if (window.top !== window) return;
    var href = location.href;
    // Same rules as globToRegExp() in extensions.dart: in the host part `*`
    // can't cross / ? # ; a pattern without a path matches every path.
    function esc(s) { return s.replace(/[.+?^${}()|[\]\\]/g, '\\$&'); }
    function conv(part, star) { return part.split('*').map(esc).join(star); }
    function globToRegExp(g) {
        g = String(g).trim();
        if (g === '*') return /.*/;
        var schemeEnd = g.indexOf('://');
        if (schemeEnd < 0) return new RegExp('^' + conv(g, '.*') + '$', 'i');
        var rest = g.substring(schemeEnd + 3);
        var cut = rest.search(/[\/?#]/);
        var hostPart = cut < 0 ? g : g.substring(0, schemeEnd + 3 + cut);
        var pathPart = cut < 0 ? '' : rest.substring(cut);
        var re = conv(hostPart, '[^/?#]*') + (pathPart ? conv(pathPart, '.*') : '(?:[/?#].*)?');
        return new RegExp('^' + re + '$', 'i');
    }
    var ok = META.matches.some(function (g) { return globToRegExp(g).test(href); });
    if (!ok) return;
    if (META.css) {
        var s = document.createElement('style');
        s.textContent = META.css;
        (document.head || document.documentElement).appendChild(s);
    }
    function run() {
        try {
__BODY__
        } catch (e) {
            console.error('[User script "' + META.name + '"] ' + (e && e.stack || e));
        }
    }
    if (META.runAt === 'start' || document.readyState !== 'loading') run();
    else document.addEventListener('DOMContentLoaded', run);
})(__META__);
''';
