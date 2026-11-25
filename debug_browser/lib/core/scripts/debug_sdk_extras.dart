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
    // Find in page: wraps matches in <mark>, reports {count, index}
    // ---------------------------------------------------------------
    const FIND_CLASS = '__dbg-find';
    let findMarks = [];
    let findIndex = -1;
    dbg.findClear = function () {
        findMarks.forEach(function (m) {
            const parent = m.parentNode;
            if (!parent) return;
            parent.replaceChild(document.createTextNode(m.textContent), m);
            parent.normalize();
        });
        findMarks = [];
        findIndex = -1;
    };
    function paintActive() {
        findMarks.forEach(function (m, i) {
            m.style.background = i === findIndex ? '#ff9632' : '#ffff00';
            m.style.color = '#000';
        });
        const cur = findMarks[findIndex];
        if (cur) { try { cur.scrollIntoView({ block: 'center' }); } catch (e) { } }
        send('find_result', { count: findMarks.length, index: findIndex });
    }
    dbg.find = function (term) {
        dbg.findClear();
        term = String(term || '');
        if (!term) { send('find_result', { count: 0, index: -1 }); return; }
        const needle = term.toLowerCase();
        const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT, {
            acceptNode: function (n) {
                const p = n.parentElement;
                if (!p || /^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA|INPUT)$/.test(p.tagName)) return NodeFilter.FILTER_REJECT;
                return n.nodeValue.toLowerCase().indexOf(needle) >= 0 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        });
        const nodes = [];
        while (walker.nextNode() && nodes.length < 2000) nodes.push(walker.currentNode);
        nodes.forEach(function (node) {
            let text = node.nodeValue;
            const frag = document.createDocumentFragment();
            let pos = 0, i;
            while ((i = text.toLowerCase().indexOf(needle, pos)) >= 0 && findMarks.length < 1000) {
                if (i > pos) frag.appendChild(document.createTextNode(text.substring(pos, i)));
                const mark = document.createElement('mark');
                mark.className = FIND_CLASS;
                mark.textContent = text.substr(i, term.length);
                frag.appendChild(mark);
                findMarks.push(mark);
                pos = i + term.length;
            }
            if (pos < text.length) frag.appendChild(document.createTextNode(text.substring(pos)));
            node.parentNode.replaceChild(frag, node);
        });
        findIndex = findMarks.length ? 0 : -1;
        paintActive();
    };
    dbg.findStep = function (delta) {
        if (!findMarks.length) return;
        findIndex = (findIndex + delta + findMarks.length) % findMarks.length;
        paintActive();
    };

    // ---------------------------------------------------------------
    // Tabs: long-press link menu, target=_blank and window.open
    // ---------------------------------------------------------------
    function absolute(u) { try { return new URL(u, location.href).href; } catch (e) { return ''; } }
    document.addEventListener('contextmenu', function (e) {
        const a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        const img = e.target && e.target.closest ? e.target.closest('img[src]') : null;
        if (!a && !img) return;
        e.preventDefault();
        send('link_menu', {
            href: a ? absolute(a.getAttribute('href')) : absolute(img.getAttribute('src')),
            text: a ? (a.innerText || a.textContent || '').trim().substring(0, 120) : (img.alt || ''),
            image: img ? absolute(img.getAttribute('src')) : ''
        });
    }, true);
    document.addEventListener('click', function (e) {
        if (e.defaultPrevented || e.button !== 0) return;
        const a = e.target && e.target.closest ? e.target.closest('a[href][target]') : null;
        if (!a) return;
        const target = (a.getAttribute('target') || '').toLowerCase();
        if (target !== '_blank') return;
        const href = absolute(a.getAttribute('href'));
        if (!/^https?:/.test(href)) return;
        e.preventDefault();
        // An invisible full-screen link is a click-jacking ad, not a real link.
        if (window.__dbg_overlayOf && window.__dbg_overlayOf(a)) {
            window.__dbg_blockPopup && window.__dbg_blockPopup(href);
            return;
        }
        send('open_tab', { href: href });
    }, false);
    // Downloads the WebView can't do natively: blob:/data: links and
    // <a download>. blob/data are read here and sent as a data: URL.
    const MAX_BLOB = 25 * 1024 * 1024;
    function blobDownload(href, name) {
        fetch(href).then(function (r) { return r.blob(); }).then(function (b) {
            if (b.size > MAX_BLOB) {
                console.warn('[Download] ' + (name || 'file') + ' is larger than 25 MB and cannot be saved from a blob: URL');
                return;
            }
            const fr = new FileReader();
            fr.onload = function () { send('blob_download', { href: fr.result, name: name || '', mime: b.type || '' }); };
            fr.readAsDataURL(b);
        }).catch(function (e) { console.warn('[Download] failed: ' + e); });
    }
    function handleDownloadAnchor(a) {
        if (!a || !a.getAttribute) return false;
        const raw = a.getAttribute('href') || '';
        const isBlob = /^(blob|data):/i.test(raw);
        if (!isBlob && !a.hasAttribute('download')) return false;
        const name = a.getAttribute('download') || '';
        if (isBlob) { blobDownload(a.href, name); return true; }
        const href = absolute(raw);
        if (!/^https?:/.test(href)) return false;
        send('download_link', { href: href, name: name });
        return true;
    }
    dbg.handleDownloadAnchor = handleDownloadAnchor;
    document.addEventListener('click', function (e) {
        if (e.defaultPrevented || e.button !== 0) return;
        const a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        if (a && handleDownloadAnchor(a)) e.preventDefault();
    }, true);
    // Scripts often create a detached <a download> and call .click() on it.
    const realAnchorClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () {
        if (!this.isConnected && handleDownloadAnchor(this)) return;
        return realAnchorClick.apply(this, arguments);
    };

    const realOpen = window.open;
    window.open = function (url, name, features) {
        const href = absolute(url || '');
        if (/^https?:/.test(href)) {
            // Pop-up blocker (extensions core) decides first.
            if (window.__dbg_allowPopup && !window.__dbg_allowPopup(href)) {
                window.__dbg_blockPopup(href);
                return null;
            }
            send('open_tab', { href: href });
            return null;
        }
        return realOpen ? realOpen.apply(window, arguments) : null;
    };

    // ---------------------------------------------------------------
    // Reader mode: the main article in a clean, readable overlay
    // ---------------------------------------------------------------
    function textLen(el) { return (el.innerText || el.textContent || '').trim().length; }
    function findArticle() {
        const direct = document.querySelector('article, [role="main"] article, main article, [itemprop="articleBody"]');
        if (direct && textLen(direct) > 400) return direct;
        // Score blocks by the paragraph text they directly contain.
        let best = null, bestScore = 0;
        document.querySelectorAll('p').forEach(function (p) {
            const parent = p.parentElement;
            if (!parent) return;
            const len = textLen(p);
            if (len < 40) return;
            parent.__dbgScore = (parent.__dbgScore || 0) + len;
            if (parent.__dbgScore > bestScore) { bestScore = parent.__dbgScore; best = parent; }
        });
        // Include a wrapping container (e.g. with the article header), but
        // never grow to the whole page.
        const up = best && best.parentElement;
        if (up && up !== document.body && up !== document.documentElement &&
            textLen(up) < textLen(best) * 1.6) best = up;
        return bestScore > 300 ? best : (document.querySelector('main') || null);
    }
    dbg.readerMode = function () {
        const existing = document.getElementById('__dbg_reader');
        if (existing) { existing.remove(); document.documentElement.style.overflow = ''; return; }
        const src = findArticle();
        if (!src) { alert('Reader mode: no article found on this page.'); return; }
        const clone = src.cloneNode(true);
        clone.querySelectorAll('script,style,noscript,iframe,form,button,input,select,textarea,nav,aside,footer,header,svg,canvas,video,audio,[aria-hidden="true"],ins,.adsbygoogle,[class*="share"],[class*="social"],[class*="related"],[id*="comments"]')
            .forEach(function (n) { n.remove(); });
        clone.querySelectorAll('*').forEach(function (n) {
            n.removeAttribute('style'); n.removeAttribute('class'); n.removeAttribute('id');
            if (n.tagName === 'A') n.setAttribute('target', '_self');
            if (n.tagName === 'IMG') { const s = n.getAttribute('data-src') || n.getAttribute('src'); if (s) n.setAttribute('src', s); n.removeAttribute('srcset'); n.removeAttribute('loading'); }
        });
        // Prefer the article's own heading over the page's first <h1>
        // (often a logo), and don't show it twice.
        // Nearest heading: inside the article, then its ancestors, then page.
        let h1 = null;
        for (let n = src; n && !h1; n = n.parentElement) h1 = n.querySelector('h1');
        h1 = h1 || document.querySelector('h1');
        const h1Text = h1 ? (h1.innerText || h1.textContent || '').trim() : '';
        const title = h1Text || (document.title || '').trim();
        const dup = clone.querySelector('h1');
        if (dup && (dup.innerText || dup.textContent || '').trim() === h1Text) dup.remove();
        const words = textLen(clone) / 5.5;
        const themes = { light: ['#ffffff', '#1f2328'], sepia: ['#f4ecd8', '#3b2f20'], dark: ['#1e1f22', '#e3e3e3'] };
        let size = 19, theme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
        const root = document.createElement('div');
        root.id = '__dbg_reader';
        root.innerHTML =
            '<div class="bar"><button data-a="close" aria-label="Close">✕</button><span></span>' +
            '<button data-a="smaller" aria-label="Smaller text">A−</button><button data-a="bigger" aria-label="Bigger text">A+</button>' +
            '<button data-a="theme" aria-label="Theme">◐</button></div><main><h1></h1><p class="meta"></p><div class="body"></div></main>';
        root.querySelector('h1').textContent = title;
        root.querySelector('.meta').textContent = location.hostname.replace(/^www\./, '') + ' · ' + Math.max(1, Math.round(words / 220)) + ' min read';
        root.querySelector('.body').appendChild(clone);
        const style = document.createElement('style');
        root.appendChild(style);
        function paint() {
            const t = themes[theme];
            style.textContent =
                '#__dbg_reader{position:fixed;inset:0;z-index:2147483646;overflow-y:auto;background:' + t[0] + ';color:' + t[1] + ';-webkit-text-size-adjust:100%}' +
                '#__dbg_reader .bar{position:sticky;top:0;display:flex;gap:6px;align-items:center;padding:8px 12px;background:' + t[0] + 'ee;border-bottom:1px solid ' + t[1] + '22;backdrop-filter:blur(6px)}' +
                '#__dbg_reader .bar span{flex:1}' +
                '#__dbg_reader button{all:unset;cursor:pointer;padding:6px 12px;border-radius:16px;border:1px solid ' + t[1] + '33;font:600 15px system-ui,sans-serif;color:' + t[1] + '}' +
                '#__dbg_reader main{max-width:42rem;margin:0 auto;padding:16px 20px 64px;font:' + size + 'px/1.65 Georgia,"Noto Serif",serif}' +
                '#__dbg_reader h1{font:700 1.6em/1.25 system-ui,sans-serif;margin:.4em 0}' +
                '#__dbg_reader .meta{opacity:.65;font:14px system-ui,sans-serif;margin-bottom:1.5em}' +
                '#__dbg_reader img,#__dbg_reader figure{max-width:100%!important;height:auto!important;margin:1em 0}' +
                '#__dbg_reader a{color:inherit;text-decoration:underline}' +
                '#__dbg_reader pre,#__dbg_reader code{white-space:pre-wrap;font-size:.85em}';
        }
        root.addEventListener('click', function (e) {
            const a = e.target && e.target.getAttribute && e.target.getAttribute('data-a');
            if (!a) return;
            if (a === 'close') { root.remove(); document.documentElement.style.overflow = ''; return; }
            if (a === 'smaller') size = Math.max(14, size - 2);
            if (a === 'bigger') size = Math.min(30, size + 2);
            if (a === 'theme') theme = theme === 'light' ? 'sepia' : theme === 'sepia' ? 'dark' : 'light';
            paint();
        });
        paint();
        document.documentElement.style.overflow = 'hidden';
        document.body.appendChild(root);
        root.scrollTop = 0;
    };

    // ---------------------------------------------------------------
    // Read aloud: plain article text (same article detection as reader)
    // ---------------------------------------------------------------
    dbg.readerText = function () {
        const src = findArticle() || document.body;
        if (!src) return JSON.stringify({ title: document.title, text: '' });
        const clone = src.cloneNode(true);
        clone.querySelectorAll('script,style,noscript,iframe,nav,aside,footer,form,button,figure figcaption,[aria-hidden="true"]').forEach(function (n) { n.remove(); });
        const blocks = [];
        clone.querySelectorAll('h1,h2,h3,h4,p,li,blockquote').forEach(function (n) {
            const t = (n.innerText || n.textContent || '').replace(/\s+/g, ' ').trim();
            if (t.length > 1) blocks.push(t);
        });
        let h1 = null;
        for (let n = src; n && !h1; n = n.parentElement) h1 = n.querySelector('h1');
        const title = ((h1 && (h1.innerText || h1.textContent)) || document.title || '').trim();
        if (blocks.length && blocks[0] === title) blocks.shift();
        return JSON.stringify({ title: title, text: blocks.join('\n') });
    };

    // ---------------------------------------------------------------
    // JSON viewer for API responses opened as a page
    // ---------------------------------------------------------------
    (function jsonViewer() {
        const ct = (document.contentType || '').toLowerCase();
        if (ct.indexOf('json') < 0 || !document.body) return;
        const raw = document.body.innerText || document.body.textContent || '';
        if (raw.length > 5 * 1024 * 1024) return;
        let data;
        try { data = JSON.parse(raw); } catch (e) { return; }
        const esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); };
        function render(v, key, depth) {
            const k = key === null ? '' : '<span class="k">' + esc(key) + '</span>: ';
            if (v === null) return '<div>' + k + '<span class="n">null</span></div>';
            if (Array.isArray(v) || typeof v === 'object') {
                const isArr = Array.isArray(v);
                const keys = isArr ? v.map(function (_, i) { return i; }) : Object.keys(v);
                const summary = isArr ? '[' + keys.length + ']' : '{' + keys.length + '}';
                const inner = keys.slice(0, 2000).map(function (kk) { return render(v[kk], isArr ? kk : kk, depth + 1); }).join('');
                return '<details' + (depth < 2 ? ' open' : '') + '><summary>' + k + '<span class="c">' + summary + '</span></summary>' + inner + '</details>';
            }
            const cls = typeof v === 'string' ? 's' : typeof v === 'number' ? 'num' : 'b';
            return '<div>' + k + '<span class="' + cls + '">' + esc(typeof v === 'string' ? JSON.stringify(v) : v) + '</span></div>';
        }
        document.head.insertAdjacentHTML('beforeend', '<meta name="viewport" content="width=device-width,initial-scale=1"><style>' +
            'body{margin:0;font:13px/1.55 ui-monospace,Menlo,monospace;background:#fff;color:#1f2328}' +
            '@media (prefers-color-scheme:dark){body{background:#1e1f22;color:#e3e3e3}}' +
            '.bar{position:sticky;top:0;display:flex;gap:8px;padding:8px;background:inherit;border-bottom:1px solid #8884}' +
            '.bar button{font:600 13px system-ui;padding:6px 12px;border-radius:14px;border:1px solid #8886;background:none;color:inherit}' +
            '#tree,#raw{padding:8px 12px}#tree details,#tree div{margin-left:14px}#tree>details,#tree>div{margin-left:0}' +
            'summary{cursor:pointer}.k{color:#a626a4}.s{color:#22863a}.num{color:#1a73e8}.b{color:#e36209}.n{color:#888}.c{color:#888}' +
            '#raw{white-space:pre-wrap;word-break:break-all;display:none}</style>');
        document.body.innerHTML = '<div class="bar"><button data-v="tree">Pretty</button><button data-v="raw">Raw</button><button data-v="copy">Copy</button></div>' +
            '<div id="tree">' + render(data, null, 0) + '</div><pre id="raw"></pre>';
        document.getElementById('raw').textContent = JSON.stringify(data, null, 2);
        document.querySelector('.bar').addEventListener('click', function (e) {
            const v = e.target.getAttribute && e.target.getAttribute('data-v');
            if (v === 'tree' || v === 'raw') {
                document.getElementById('tree').style.display = v === 'tree' ? '' : 'none';
                document.getElementById('raw').style.display = v === 'raw' ? 'block' : 'none';
            } else if (v === 'copy' && navigator.clipboard) {
                navigator.clipboard.writeText(JSON.stringify(data, null, 2));
            }
        });
    })();

    // ---------------------------------------------------------------
    // Page audit: SEO + best-practice checks (scored in Dart)
    // ---------------------------------------------------------------
    dbg.pageAudit = function () {
        const meta = function (sel) { const m = document.querySelector(sel); return m ? (m.getAttribute('content') || '').trim() : ''; };
        const imgs = Array.prototype.slice.call(document.images);
        const genericLinks = Array.prototype.filter.call(document.querySelectorAll('a[href]'), function (a) {
            return /^(click here|here|read more|more|link|learn more)$/i.test((a.innerText || a.textContent || '').trim());
        }).length;
        let mixed = 0;
        if (location.protocol === 'https:') {
            document.querySelectorAll('img[src],script[src],link[href][rel=stylesheet],iframe[src],video[src],audio[src]').forEach(function (el) {
                const u = el.getAttribute('src') || el.getAttribute('href') || '';
                if (/^http:\/\//i.test(u)) mixed++;
            });
        }
        let robots = meta('meta[name="robots"]').toLowerCase();
        send('page_audit', {
            url: location.href,
            https: location.protocol === 'https:',
            title: document.title || '',
            description: meta('meta[name="description"]'),
            h1Count: document.querySelectorAll('h1').length,
            viewport: meta('meta[name="viewport"]'),
            lang: document.documentElement.getAttribute('lang') || '',
            canonical: !!document.querySelector('link[rel="canonical"]'),
            noindex: robots.indexOf('noindex') >= 0,
            ogTags: document.querySelectorAll('meta[property^="og:"]').length,
            structuredData: document.querySelectorAll('script[type="application/ld+json"]').length,
            images: imgs.length,
            imagesMissingAlt: imgs.filter(function (i) { return !i.hasAttribute('alt'); }).length,
            genericLinks: genericLinks,
            mixedContent: mixed,
            doctype: !!document.doctype,
            charset: !!document.querySelector('meta[charset], meta[http-equiv="Content-Type" i]'),
            domNodes: document.getElementsByTagName('*').length,
            fontSizeSmall: (function () {
                let small = 0, total = 0;
                document.querySelectorAll('p,li,span,a,td').forEach(function (el) {
                    if (total > 400 || !(el.textContent || '').trim()) return;
                    total++;
                    if (parseFloat(getComputedStyle(el).fontSize) < 12) small++;
                });
                return total ? small / total : 0;
            })()
        });
    };

    // ---------------------------------------------------------------
    // Edit & resend: replay a request from the page (its cookies, origin)
    // ---------------------------------------------------------------
    dbg.replay = function (id, req) {
        const t0 = performance.now();
        const init = { method: req.method || 'GET', headers: req.headers || {}, credentials: 'include' };
        if (req.body && !/^(GET|HEAD)$/i.test(init.method)) init.body = req.body;
        fetch(req.url, init).then(function (res) {
            const headers = {};
            res.headers.forEach(function (v, k) { headers[k] = v; });
            return res.text().then(function (body) {
                send('replay_result', {
                    id: id, status: res.status, statusText: res.statusText, headers: headers,
                    body: body.length > 200000 ? body.substring(0, 200000) + '\n… [truncated]' : body,
                    ms: Math.round(performance.now() - t0)
                });
            });
        }).catch(function (e) {
            send('replay_result', { id: id, error: String(e), ms: Math.round(performance.now() - t0) });
        });
    };

    // ---------------------------------------------------------------
    // Full-page screenshot helpers
    // ---------------------------------------------------------------
    dbg.pageMetrics = function () {
        const h = Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0);
        return JSON.stringify({ height: h, viewport: window.innerHeight, y: window.scrollY });
    };
    dbg.hideFixed = function (hide) {
        let s = document.getElementById('__dbg_hidefixed');
        if (!hide) { if (s) s.remove(); document.querySelectorAll('[data-dbg-fixed]').forEach(function (el) { el.style.visibility = el.getAttribute('data-dbg-fixed'); el.removeAttribute('data-dbg-fixed'); }); return; }
        document.querySelectorAll('body *').forEach(function (el) {
            const p = getComputedStyle(el).position;
            if (p === 'fixed' || p === 'sticky') { el.setAttribute('data-dbg-fixed', el.style.visibility || ''); el.style.visibility = 'hidden'; }
        });
    };

    // ---------------------------------------------------------------
    // Block this element: tap to pick, "bigger" = parent, preview
    // ---------------------------------------------------------------
    function cssEscape(s) { return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/[^a-zA-Z0-9_-]/g, '\\$&'); }
    function uniqueSelector(el) {
        if (el.id && !/\d{3,}/.test(el.id) && document.querySelectorAll('#' + cssEscape(el.id)).length === 1) return '#' + cssEscape(el.id);
        const parts = [];
        for (let n = el; n && n.nodeType === 1 && n !== document.body && n !== document.documentElement; n = n.parentElement) {
            if (n.id && !/\d{3,}/.test(n.id)) { parts.unshift('#' + cssEscape(n.id)); break; }
            let part = n.tagName.toLowerCase();
            const cls = (typeof n.className === 'string' ? n.className : '').trim().split(/\s+/)
                .filter(function (c) { return c && !/\d{3,}|^(active|open|show|hover|focus|selected)$/.test(c) && !c.startsWith('__dbg'); })
                .slice(0, 2);
            if (cls.length) part += '.' + cls.map(cssEscape).join('.');
            const parent = n.parentElement;
            if (parent) {
                const same = Array.prototype.filter.call(parent.children, function (c) { return c.tagName === n.tagName; });
                if (same.length > 1) part += ':nth-of-type(' + (same.indexOf(n) + 1) + ')';
            }
            parts.unshift(part);
            const sel = parts.join(' > ');
            if (document.querySelectorAll(sel).length === 1 && parts.length >= 2) return sel;
            if (parts.length >= 6) break;
        }
        return parts.join(' > ');
    }
    let picked = null, pickBox = null, pickPreview = null;
    function markPicked(el) {
        picked = el;
        if (!pickBox) {
            pickBox = document.createElement('div');
            pickBox.id = '__dbg-pickbox';
            pickBox.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:3px solid #ff4e42;background:rgba(255,78,66,.18);border-radius:4px';
            document.documentElement.appendChild(pickBox);
        }
        const r = el.getBoundingClientRect();
        pickBox.style.top = r.top + 'px'; pickBox.style.left = r.left + 'px';
        pickBox.style.width = r.width + 'px'; pickBox.style.height = r.height + 'px';
        const sel = uniqueSelector(el);
        send('element_picked', {
            selector: sel,
            tag: el.tagName.toLowerCase(),
            text: (el.innerText || el.textContent || '').trim().substring(0, 80),
            count: document.querySelectorAll(sel).length,
            canGrow: !!(el.parentElement && el.parentElement !== document.body && el.parentElement !== document.documentElement)
        });
    }
    function pickTap(e) {
        e.preventDefault(); e.stopImmediatePropagation();
        const el = document.elementFromPoint(e.clientX, e.clientY);
        if (el && el !== pickBox) markPicked(el);
    }
    dbg.pickElement = function () {
        dbg.pickCancel();
        window.addEventListener('click', pickTap, true);
        document.documentElement.style.cursor = 'crosshair';
    };
    dbg.pickParent = function () {
        if (picked && picked.parentElement && picked.parentElement !== document.body) markPicked(picked.parentElement);
    };
    dbg.pickPreview = function (on) {
        if (!picked) return;
        if (on) { pickPreview = picked.style.display; picked.style.setProperty('display', 'none', 'important'); if (pickBox) pickBox.style.display = 'none'; }
        else { picked.style.display = pickPreview || ''; if (pickBox) pickBox.style.display = ''; }
    };
    dbg.pickCancel = function () {
        window.removeEventListener('click', pickTap, true);
        document.documentElement.style.cursor = '';
        if (picked && pickPreview !== null) picked.style.display = pickPreview || '';
        if (pickBox) { pickBox.remove(); pickBox = null; }
        picked = null; pickPreview = null;
    };
    dbg.hideSelector = function (sel) {
        dbg.pickCancel();
        let s = document.getElementById('__dbg_hidden_live');
        if (!s) { s = document.createElement('style'); s.id = '__dbg_hidden_live'; document.documentElement.appendChild(s); }
        s.textContent += sel + '{display:none!important}\n';
    };

    // ---------------------------------------------------------------
    // Highlighter: select text -> floating "Highlight" button
    // ---------------------------------------------------------------
    const HL_COLORS = { yellow: '#fff176', green: '#a5d6a7', pink: '#f8bbd0', blue: '#90caf9' };
    function textNodesIn(root) {
        const out = [];
        const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (n) {
                const p = n.parentElement;
                return p && !/^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA)$/.test(p.tagName) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        });
        while (w.nextNode()) out.push(w.currentNode);
        return out;
    }
    function wrapRange(range, id, color) {
        const nodes = textNodesIn(range.commonAncestorContainer.nodeType === 1 ? range.commonAncestorContainer : range.commonAncestorContainer.parentNode)
            .filter(function (n) { return range.intersectsNode(n); });
        nodes.forEach(function (n) {
            let start = n === range.startContainer ? range.startOffset : 0;
            let end = n === range.endContainer ? range.endOffset : n.nodeValue.length;
            if (end <= start) return;
            const part = n.splitText(start);
            part.splitText(end - start);
            const mark = document.createElement('mark');
            mark.className = '__dbg_hl';
            mark.setAttribute('data-hl', id);
            mark.style.cssText = 'background:' + (HL_COLORS[color] || color) + ';color:inherit;border-radius:2px;padding:0 1px';
            part.parentNode.replaceChild(mark, part);
            mark.appendChild(part);
        });
    }
    function contextOf(range) {
        const all = textNodesIn(document.body);
        let text = '', startAt = -1, endAt = -1;
        all.forEach(function (n) {
            if (n === range.startContainer) startAt = text.length + range.startOffset;
            if (n === range.endContainer) endAt = text.length + range.endOffset;
            text += n.nodeValue;
        });
        return {
            prefix: startAt < 0 ? '' : text.substring(Math.max(0, startAt - 32), startAt),
            suffix: endAt < 0 ? '' : text.substring(endAt, endAt + 32)
        };
    }
    /** Finds [text] in the page, preferring the match with the same context. */
    function findText(t, prefix, suffix) {
        const all = textNodesIn(document.body);
        let full = '';
        const starts = [];
        all.forEach(function (n) { starts.push(full.length); full += n.nodeValue; });
        let best = -1, bestScore = -1, i = full.indexOf(t);
        while (i >= 0) {
            let score = 0;
            if (prefix && full.substring(i - prefix.length, i) === prefix) score += 2;
            if (suffix && full.substring(i + t.length, i + t.length + suffix.length) === suffix) score += 2;
            if (score > bestScore) { bestScore = score; best = i; }
            i = full.indexOf(t, i + 1);
        }
        if (best < 0) return null;
        function locate(off) {
            let k = 0;
            while (k + 1 < starts.length && starts[k + 1] <= off) k++;
            return { node: all[k], offset: off - starts[k] };
        }
        const a = locate(best), b = locate(best + t.length);
        const r = document.createRange();
        r.setStart(a.node, a.offset);
        r.setEnd(b.node, b.offset);
        return r;
    }
    let hlButton = null;
    function hideHlButton() { if (hlButton) { hlButton.remove(); hlButton = null; } }
    document.addEventListener('selectionchange', function () {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || sel.rangeCount === 0 || sel.toString().trim().length < 3) { setTimeout(hideHlButton, 200); return; }
        const r = sel.getRangeAt(0).getBoundingClientRect();
        if (!hlButton) {
            hlButton = document.createElement('button');
            hlButton.textContent = '✎ Highlight';
            hlButton.style.cssText = 'position:fixed;z-index:2147483647;padding:8px 14px;border-radius:18px;border:0;' +
                'background:#1a73e8;color:#fff;font:600 14px system-ui,sans-serif;box-shadow:0 2px 8px rgba(0,0,0,.3)';
            hlButton.addEventListener('mousedown', function (e) { e.preventDefault(); });
            hlButton.addEventListener('click', function (e) {
                e.preventDefault(); e.stopPropagation();
                dbg.highlightSelection('yellow');
            });
            document.documentElement.appendChild(hlButton);
        }
        hlButton.style.top = Math.max(8, r.top - 46) + 'px';
        hlButton.style.left = Math.max(8, Math.min(window.innerWidth - 130, r.left)) + 'px';
    });
    dbg.highlightSelection = function (color) {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed || !sel.rangeCount) return;
        const range = sel.getRangeAt(0);
        const text = sel.toString();
        const ctx = contextOf(range);
        const id = 'h' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
        wrapRange(range, id, color);
        sel.removeAllRanges();
        hideHlButton();
        send('highlight_added', { id: id, text: text.substring(0, 2000), prefix: ctx.prefix, suffix: ctx.suffix, color: color });
    };
    dbg.applyHighlights = function (json) {
        let list = [];
        try { list = JSON.parse(json) || []; } catch (e) { }
        list.forEach(function (h) {
            if (document.querySelector('mark[data-hl="' + h.id + '"]')) return;
            const r = findText(h.text, h.prefix, h.suffix);
            if (r) wrapRange(r, h.id, h.color || 'yellow');
        });
    };
    dbg.removeHighlight = function (id) {
        document.querySelectorAll('mark[data-hl="' + id + '"]').forEach(function (m) {
            const p = m.parentNode;
            while (m.firstChild) p.insertBefore(m.firstChild, m);
            p.removeChild(m);
            p.normalize();
        });
    };
    document.addEventListener('click', function (e) {
        const m = e.target && e.target.closest ? e.target.closest('mark.__dbg_hl') : null;
        if (m) send('highlight_tap', { id: m.getAttribute('data-hl') });
    }, true);

    // ---------------------------------------------------------------
    // Picture-in-picture: make the playing video fill the page
    // ---------------------------------------------------------------
    let pipEl = null, pipStyle = null;
    dbg.focusVideo = function (on) {
        if (!on) {
            if (pipEl) pipEl.setAttribute('style', pipStyle || '');
            const bg = document.getElementById('__dbg_pipbg'); if (bg) bg.remove();
            pipEl = null;
            return JSON.stringify({ ok: true });
        }
        let best = null, area = 0;
        document.querySelectorAll('video, iframe').forEach(function (el) {
            const r = el.getBoundingClientRect();
            const a = r.width * r.height;
            const playing = el.tagName === 'VIDEO' ? !el.paused : true;
            if (a > area && a > 120 * 80 && playing) { area = a; best = el; }
        });
        if (!best) return JSON.stringify({ ok: false });
        const r = best.getBoundingClientRect();
        let w = best.videoWidth || r.width, h = best.videoHeight || r.height;
        pipEl = best;
        pipStyle = best.getAttribute('style');
        const bg = document.createElement('div');
        bg.id = '__dbg_pipbg';
        bg.style.cssText = 'position:fixed;inset:0;background:#000;z-index:2147483646';
        document.documentElement.appendChild(bg);
        best.setAttribute('style', (pipStyle || '') + ';position:fixed!important;inset:0!important;width:100vw!important;' +
            'height:100vh!important;max-width:none!important;max-height:none!important;z-index:2147483647!important;' +
            'background:#000!important;object-fit:contain!important;margin:0!important;transform:none!important');
        return JSON.stringify({ ok: true, w: Math.round(w), h: Math.round(h) });
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
