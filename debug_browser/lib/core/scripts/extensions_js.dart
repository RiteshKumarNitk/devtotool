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

    if (!isTop) return;

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
