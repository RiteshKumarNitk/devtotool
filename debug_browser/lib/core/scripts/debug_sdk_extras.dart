/// Second part of the injected SDK: Web Vitals, DOM tree + live editing,
/// accessibility audit and geolocation override.
///
/// Kept as a RAW Dart string so JavaScript backslashes and dollar signs
/// need no escaping. Never add Dart interpolation here.
const String debugSdkExtrasJs = r'''
(function () {
    if (window.__dbg_extras_injected) return;
    window.__dbg_extras_injected = true;

    function send(type, data) {
        try {
            if (window.DebugBridge && window.DebugBridge.postMessage) {
                window.DebugBridge.postMessage(JSON.stringify({ type: type, data: data, timestamp: Date.now() }));
            }
        } catch (e) { }
    }
    const dbg = window.__dbg = window.__dbg || {};

    // ---------------------------------------------------------------
    // Web Vitals (LCP, CLS, INP approximation, FCP, TTFB) + resources
    // ---------------------------------------------------------------
    const vitals = { lcp: null, cls: 0, inp: null, fcp: null, ttfb: null };
    function observe(type, cb, opts) {
        try {
            const po = new PerformanceObserver(function (list) { list.getEntries().forEach(cb); scheduleVitals(); });
            po.observe(Object.assign({ type: type, buffered: true }, opts || {}));
        } catch (e) { }
    }
    observe('largest-contentful-paint', function (e) { vitals.lcp = Math.round(e.startTime); });
    observe('layout-shift', function (e) { if (!e.hadRecentInput) vitals.cls = Math.round((vitals.cls + e.value) * 1000) / 1000; });
    observe('event', function (e) {
        if (e.interactionId && (vitals.inp === null || e.duration > vitals.inp)) vitals.inp = Math.round(e.duration);
    }, { durationThreshold: 16 });
    observe('paint', function (e) { if (e.name === 'first-contentful-paint') vitals.fcp = Math.round(e.startTime); });
    try {
        const nav = performance.getEntriesByType('navigation')[0];
        if (nav) vitals.ttfb = Math.round(nav.responseStart);
    } catch (e) { }

    function resourceSummary() {
        let entries = [];
        try { entries = performance.getEntriesByType('resource'); } catch (e) { }
        const byType = {};
        let totalBytes = 0;
        entries.forEach(function (r) {
            const t = r.initiatorType || 'other';
            byType[t] = byType[t] || { count: 0, bytes: 0 };
            byType[t].count++;
            byType[t].bytes += r.transferSize || 0;
            totalBytes += r.transferSize || 0;
        });
        const slowest = entries.slice().sort(function (a, b) { return b.duration - a.duration; }).slice(0, 15).map(function (r) {
            return { name: r.name, type: r.initiatorType, duration: Math.round(r.duration), start: Math.round(r.startTime), bytes: r.transferSize || 0 };
        });
        return { count: entries.length, totalBytes: totalBytes, byType: byType, slowest: slowest };
    }

    let vitalsTimer = null;
    function scheduleVitals() {
        if (vitalsTimer) return;
        vitalsTimer = setTimeout(function () { vitalsTimer = null; dbg.collectVitals(); }, 1000);
    }
    dbg.collectVitals = function () {
        send('vitals', { vitals: vitals, resources: resourceSummary(), url: location.href });
    };
    scheduleVitals();

    // ---------------------------------------------------------------
    // DOM tree, selection, live style/attribute editing
    // ---------------------------------------------------------------
    const MAX_NODES = 1500;
    function nodeLabel(el) {
        return {
            tag: el.tagName.toLowerCase(),
            id: el.id || '',
            cls: typeof el.className === 'string' ? el.className.trim().split(/\s+/).filter(Boolean).slice(0, 4).join(' ') : ''
        };
    }
    function pathOf(el) {
        const path = [];
        while (el && el !== document.documentElement) {
            const parent = el.parentElement;
            if (!parent) break;
            path.unshift(Array.prototype.indexOf.call(parent.children, el));
            el = parent;
        }
        return path.join('/');
    }
    function byPath(path) {
        let el = document.documentElement;
        if (!path) return el;
        const parts = String(path).split('/');
        for (let i = 0; i < parts.length; i++) {
            el = el && el.children[parseInt(parts[i], 10)];
        }
        return el || null;
    }
    dbg.domTree = function (maxDepth) {
        maxDepth = maxDepth || 12;
        let count = 0;
        function walk(el, depth, path) {
            count++;
            const n = nodeLabel(el);
            n.path = path;
            n.childCount = el.children.length;
            n.children = [];
            if (depth < maxDepth) {
                for (let i = 0; i < el.children.length && count < MAX_NODES; i++) {
                    const c = el.children[i];
                    if (c.id === 'debug-inspector-overlay' || c.id === '__dbg-highlight') continue;
                    n.children.push(walk(c, depth + 1, path === '' ? String(i) : path + '/' + i));
                }
            }
            return n;
        }
        send('dom_tree', { root: walk(document.documentElement, 0, ''), truncated: count >= MAX_NODES });
    };

    const STYLE_PROPS = ['display', 'position', 'width', 'height', 'margin', 'padding', 'color',
        'background-color', 'font-size', 'font-weight', 'font-family', 'line-height', 'border',
        'border-radius', 'opacity', 'z-index', 'overflow', 'flex-direction', 'justify-content',
        'align-items', 'gap', 'box-shadow', 'transform'];

    function nodeDetails(el) {
        const cs = getComputedStyle(el);
        const styles = {};
        STYLE_PROPS.forEach(function (p) { styles[p] = cs.getPropertyValue(p); });
        const attrs = {};
        for (let i = 0; i < el.attributes.length && i < 40; i++) attrs[el.attributes[i].name] = el.attributes[i].value;
        const rect = el.getBoundingClientRect();
        return {
            path: pathOf(el),
            tagName: el.tagName.toLowerCase(),
            id: el.id,
            className: typeof el.className === 'string' ? el.className : '',
            text: el.innerText ? el.innerText.substring(0, 80) : '',
            styles: styles,
            inlineStyle: el.getAttribute('style') || '',
            attributes: attrs,
            box: { x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.width), h: Math.round(rect.height) },
            outerHTML: el.outerHTML.substring(0, 2000)
        };
    }
    dbg.nodeDetails = nodeDetails;

    function highlight(el) {
        let hl = document.getElementById('__dbg-highlight');
        if (!hl) {
            hl = document.createElement('div');
            hl.id = '__dbg-highlight';
            hl.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;background:rgba(104,182,255,.35);border:2px solid #68b6ff;transition:all .1s';
            document.documentElement.appendChild(hl);
        }
        const r = el.getBoundingClientRect();
        hl.style.top = r.top + 'px'; hl.style.left = r.left + 'px';
        hl.style.width = r.width + 'px'; hl.style.height = r.height + 'px';
        hl.style.display = 'block';
        clearTimeout(dbg._hlTimer);
        dbg._hlTimer = setTimeout(function () { hl.style.display = 'none'; }, 2500);
    }
    dbg.select = function (path) {
        const el = byPath(path);
        if (!el) return;
        try { el.scrollIntoView({ block: 'center', behavior: 'smooth' }); } catch (e) { }
        setTimeout(function () { highlight(el); }, 300);
        send('dom_node', nodeDetails(el));
    };
    dbg.setStyle = function (path, prop, value) {
        const el = byPath(path);
        if (!el) return;
        el.style.setProperty(prop, value);
        send('dom_node', nodeDetails(el));
    };
    dbg.setAttr = function (path, name, value) {
        const el = byPath(path);
        if (!el) return;
        if (value === null) el.removeAttribute(name); else el.setAttribute(name, value);
        send('dom_node', nodeDetails(el));
    };

    // ---------------------------------------------------------------
    // Accessibility audit (subset of WCAG 2.2 automated checks)
    // ---------------------------------------------------------------
    function describe(el) {
        let s = el.tagName.toLowerCase();
        if (el.id) s += '#' + el.id;
        else if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\s+/)[0];
        return s;
    }
    function visible(el) {
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return false;
        const cs = getComputedStyle(el);
        const opacity = parseFloat(cs.opacity);
        return cs.visibility !== 'hidden' && cs.display !== 'none' && (isNaN(opacity) || opacity > 0);
    }
    function accessibleName(el) {
        const label = el.getAttribute('aria-label') || el.getAttribute('title') || '';
        if (label.trim()) return label.trim();
        const by = el.getAttribute('aria-labelledby');
        if (by) {
            const t = by.split(/\s+/).map(function (id) { const n = document.getElementById(id); return n ? n.textContent : ''; }).join(' ');
            if (t.trim()) return t.trim();
        }
        if (el.id) {
            const lab = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
            if (lab && lab.textContent.trim()) return lab.textContent.trim();
        }
        const wrapping = el.closest('label');
        if (wrapping && wrapping.textContent.trim()) return wrapping.textContent.trim();
        const txt = (el.innerText || el.value || '').trim();
        if (txt) return txt;
        const img = el.querySelector && el.querySelector('img[alt]');
        if (img && img.getAttribute('alt').trim()) return img.getAttribute('alt').trim();
        return el.getAttribute('placeholder') || '';
    }
    function parseColor(c) {
        const m = c && c.match(/rgba?\(([^)]+)\)/);
        if (!m) return null;
        const p = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
        return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
    }
    function luminance(c) {
        const f = function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function backgroundOf(el) {
        while (el) {
            const cs = getComputedStyle(el);
            if (cs.backgroundImage && cs.backgroundImage !== 'none') return null; // unknown
            const bg = parseColor(cs.backgroundColor);
            if (bg && bg.a >= 0.95) return bg;
            el = el.parentElement;
        }
        return { r: 255, g: 255, b: 255, a: 1 };
    }

    dbg.a11yAudit = function () {
        const issues = [];
        const MAX = 300;
        function add(rule, severity, el, message) {
            if (issues.length >= MAX) return;
            issues.push({ rule: rule, severity: severity, message: message, element: el ? describe(el) : '', path: el ? pathOf(el) : '' });
        }

        if (!document.documentElement.getAttribute('lang')) add('html-lang', 'serious', null, 'The <html> element has no lang attribute.');
        if (!document.title || !document.title.trim()) add('document-title', 'serious', null, 'The page has no <title>.');
        const vp = document.querySelector('meta[name="viewport"]');
        if (vp && /user-scalable\s*=\s*no|maximum-scale\s*=\s*1(\.0)?(\s|,|$)/i.test(vp.getAttribute('content') || '')) {
            add('meta-viewport', 'critical', vp, 'Zooming is disabled by the viewport meta tag.');
        }

        document.querySelectorAll('img').forEach(function (img) {
            if (!img.hasAttribute('alt') && img.getAttribute('role') !== 'presentation' && img.getAttribute('aria-hidden') !== 'true') {
                add('image-alt', 'critical', img, 'Image has no alt attribute.');
            }
        });

        document.querySelectorAll('button, a[href], [role="button"], [role="link"]').forEach(function (el) {
            if (!visible(el) || el.getAttribute('aria-hidden') === 'true') return;
            if (!accessibleName(el)) add('control-name', 'critical', el, 'Interactive element has no accessible name.');
            const r = el.getBoundingClientRect();
            if ((r.width < 24 || r.height < 24) && el.tagName !== 'A') {
                add('target-size', 'moderate', el, 'Tap target is ' + Math.round(r.width) + 'x' + Math.round(r.height) + 'px (minimum 24x24).');
            }
        });

        document.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea').forEach(function (el) {
            if (!visible(el)) return;
            const hasLabel = el.getAttribute('aria-label') || el.getAttribute('aria-labelledby') || el.closest('label') ||
                (el.id && document.querySelector('label[for="' + CSS.escape(el.id) + '"]'));
            if (!hasLabel) add('form-label', 'serious', el, 'Form field has no label' + (el.placeholder ? ' (placeholder is not a label).' : '.'));
        });

        const ids = {};
        document.querySelectorAll('[id]').forEach(function (el) { ids[el.id] = (ids[el.id] || 0) + 1; });
        Object.keys(ids).forEach(function (id) {
            if (ids[id] > 1) add('duplicate-id', 'minor', document.getElementById(id), 'id="' + id + '" is used ' + ids[id] + ' times.');
        });

        let last = 0;
        document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(function (h) {
            const level = parseInt(h.tagName.substring(1), 10);
            if (last && level > last + 1) add('heading-order', 'moderate', h, 'Heading jumps from h' + last + ' to h' + level + '.');
            last = level;
        });
        if (!document.querySelector('h1')) add('page-has-heading-one', 'moderate', null, 'The page has no <h1>.');

        // Contrast: only elements that directly contain text.
        let checked = 0;
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
        const seen = new Set();
        while (walker.nextNode() && checked < 400) {
            const t = walker.currentNode;
            if (!t.textContent.trim()) continue;
            const el = t.parentElement;
            if (!el || seen.has(el) || !visible(el)) continue;
            seen.add(el);
            checked++;
            const cs = getComputedStyle(el);
            const fg = parseColor(cs.color);
            const bg = backgroundOf(el);
            if (!fg || !bg || fg.a < 0.5) continue;
            const l1 = luminance(fg), l2 = luminance(bg);
            const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
            const size = parseFloat(cs.fontSize);
            const bold = parseInt(cs.fontWeight, 10) >= 700;
            const large = size >= 24 || (bold && size >= 18.66);
            const need = large ? 3 : 4.5;
            if (ratio < need) {
                add('color-contrast', 'serious', el, 'Contrast ' + ratio.toFixed(2) + ':1 (needs ' + need + ':1) for "' + t.textContent.trim().substring(0, 40) + '"');
            }
        }

        const counts = { critical: 0, serious: 0, moderate: 0, minor: 0 };
        issues.forEach(function (i) { counts[i.severity]++; });
        send('a11y', { url: location.href, issues: issues, counts: counts, truncated: issues.length >= MAX });
    };

    // ---------------------------------------------------------------
    // Geolocation override
    // ---------------------------------------------------------------
    const realGeo = navigator.geolocation;
    const realGet = realGeo && realGeo.getCurrentPosition ? realGeo.getCurrentPosition.bind(realGeo) : null;
    const realWatch = realGeo && realGeo.watchPosition ? realGeo.watchPosition.bind(realGeo) : null;
    let fakePos = null;
    function position() {
        return {
            coords: { latitude: fakePos.lat, longitude: fakePos.lng, accuracy: fakePos.accuracy || 10,
                altitude: null, altitudeAccuracy: null, heading: null, speed: null },
            timestamp: Date.now()
        };
    }
    dbg.setGeolocation = function (json) {
        try { fakePos = json ? JSON.parse(json) : null; } catch (e) { fakePos = null; }
    };
    if (realGeo) {
        try {
            realGeo.getCurrentPosition = function (ok, err, opts) {
                if (fakePos) { setTimeout(function () { ok(position()); }, 0); return; }
                return realGet && realGet(ok, err, opts);
            };
            realGeo.watchPosition = function (ok, err, opts) {
                if (fakePos) { setTimeout(function () { ok(position()); }, 0); return 0; }
                return realWatch ? realWatch(ok, err, opts) : 0;
            };
        } catch (e) { }
    }
})();
''';
