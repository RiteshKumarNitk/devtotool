const String debugSdkJs = '''
(function () {
    if (window.__debug_sdk_injected) return;
    window.__debug_sdk_injected = true;

    function sendToFlutter(type, data) {
        if (window.DebugBridge && window.DebugBridge.postMessage) {
            window.DebugBridge.postMessage(JSON.stringify({ type: type, data: data, timestamp: Date.now() }));
        }
    }

    // 1. Hook Console
    const originalConsole = {
        log: console.log,
        warn: console.warn,
        error: console.error,
        info: console.info,
        debug: console.debug,
    };

    function hookConsole(method) {
        console[method] = function (...args) {
            try { originalConsole[method].apply(console, args); } catch (e) { }
            try {
                const message = args.map(arg => {
                    if (typeof arg === 'object') {
                        try {
                            return JSON.stringify(arg);
                        } catch (e) {
                            return String(arg);
                        }
                    }
                    return String(arg);
                }).join(' ');

                sendToFlutter('console', { level: method, message: message });
            } catch (e) { }
        };
    }

    Object.keys(originalConsole).forEach(hookConsole);

    // 2. Hook Errors
    window.addEventListener('error', function (event) {
        sendToFlutter('error', {
            message: event.message,
            source: event.filename,
            lineno: event.lineno,
            colno: event.colno,
            stack: event.error ? event.error.stack : null
        });
    });

    window.addEventListener('unhandledrejection', function (event) {
        sendToFlutter('error', {
            message: 'Unhandled Rejection: ' + (event.reason ? event.reason.toString() : 'Unknown'),
            stack: event.reason && event.reason.stack ? event.reason.stack : null
        });
    });

    // 3. Hook Fetch
    // 3. Mock API Support
    // Mock rules: [{pattern, isRegex, method, status, delay, body, contentType, enabled}]
    // A legacy {pattern: body} object is also accepted.
    window._apiMocks = [];
    window.updateApiMocks = function(mocksJson) {
        let parsed;
        try { parsed = JSON.parse(mocksJson); } catch (e) { parsed = []; }
        if (Array.isArray(parsed)) {
            window._apiMocks = parsed;
        } else if (parsed && typeof parsed === 'object') {
            window._apiMocks = Object.keys(parsed).map(function (k) { return { pattern: k, body: parsed[k] }; });
        } else {
            window._apiMocks = [];
        }
    };
    function findMock(url, method) {
        if (!url) return null;
        url = String(url);
        method = String(method || 'GET').toUpperCase();
        const rules = window._apiMocks || [];
        for (let i = 0; i < rules.length; i++) {
            const r = rules[i];
            if (!r || r.enabled === false || !r.pattern) continue;
            if (r.method && r.method !== 'ANY' && String(r.method).toUpperCase() !== method) continue;
            let hit = false;
            if (r.isRegex) {
                try { hit = new RegExp(r.pattern).test(url); } catch (e) { hit = false; }
            } else {
                hit = url.indexOf(r.pattern) !== -1;
            }
            if (hit) {
                let status = parseInt(r.status, 10);
                if (!(status >= 200 && status <= 599)) status = 200;
                return {
                    body: r.body == null ? '' : String(r.body),
                    status: status,
                    delay: Math.max(0, parseInt(r.delay, 10) || 0),
                    contentType: r.contentType || 'application/json'
                };
            }
        }
        return null;
    }
    function nullBodyStatus(status) { return status === 204 || status === 205 || status === 304; }
    const MAX_BODY = 100 * 1024;
    function clip(text) {
        if (text == null) return null;
        text = String(text);
        return text.length > MAX_BODY ? text.substring(0, MAX_BODY) + '... [truncated]' : text;
    }
    // Network condition simulation (set from Flutter).
    window._netConfig = { offline: false, latency: 0 };
    window.updateNetConfig = function(json) {
        try { window._netConfig = Object.assign({ offline: false, latency: 0 }, JSON.parse(json)); } catch (e) { }
    };
    function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
    function headersToObject(h) {
        const out = {};
        if (!h) return out;
        try {
            if (typeof Headers !== 'undefined' && h instanceof Headers) {
                h.forEach(function (v, k) { out[k] = v; });
            } else if (Array.isArray(h)) {
                h.forEach(function (pair) { out[String(pair[0]).toLowerCase()] = String(pair[1]); });
            } else if (typeof h === 'object') {
                Object.keys(h).forEach(function (k) { out[k.toLowerCase()] = String(h[k]); });
            }
        } catch (e) { }
        return out;
    }
    function parseRawHeaders(raw) {
        const out = {};
        (raw || '').trim().split(/[\\r\\n]+/).forEach(function (line) {
            const i = line.indexOf(':');
            if (i > 0) out[line.substring(0, i).trim().toLowerCase()] = line.substring(i + 1).trim();
        });
        return out;
    }
    function isTextual(contentType) {
        if (!contentType) return true;
        return /json|text|xml|javascript|html|x-www-form-urlencoded/i.test(contentType);
    }

    // 4. Hook Network Requests (Fetch)
    const originalFetch = window.fetch;
    window.fetch = async function(input, init) {
        const isRequest = typeof Request !== 'undefined' && input instanceof Request;
        const url = isRequest ? input.url : String(input);
        const method = ((init && init.method) || (isRequest ? input.method : 'GET') || 'GET').toUpperCase();
        const requestBody = init && typeof init.body === 'string' ? clip(init.body) : null;
        const requestHeaders = Object.assign({}, isRequest ? headersToObject(input.headers) : {}, headersToObject(init && init.headers));
        const net = window._netConfig || {};
        if (net.offline) {
            sendToFlutter('network', { type: 'fetch', url: url, method: method, status: 0, duration: 0, requestBody: requestBody, requestHeaders: requestHeaders, error: 'Simulated offline' });
            throw new TypeError('Failed to fetch');
        }
        if (net.latency > 0) await sleep(net.latency);

        const mock = findMock(url, method);
        if (mock) {
            if (mock.delay > 0) await sleep(mock.delay);
            console.warn('[Mocked Fetch] ' + method + ' ' + url + ' -> ' + mock.status);
            sendToFlutter('network', { type: 'fetch', url: url, method: method, status: mock.status, duration: (net.latency || 0) + mock.delay, requestBody: requestBody, requestHeaders: requestHeaders, responseHeaders: { 'content-type': mock.contentType, 'x-debug-mock': '1' }, responseBody: clip(mock.body) });
            return new Response(nullBodyStatus(mock.status) ? null : mock.body, { status: mock.status, headers: { 'Content-Type': mock.contentType, 'X-Debug-Mock': '1' } });
        }

        const startTime = Date.now() - (net.latency || 0);
        try {
            const response = await originalFetch.apply(this, arguments);
            const responseHeaders = headersToObject(response.headers);
            const duration = Date.now() - startTime;
            const report = function (body) {
                sendToFlutter('network', {
                    type: 'fetch', url: url, method: method, status: response.status,
                    duration: duration, requestBody: requestBody, requestHeaders: requestHeaders,
                    responseHeaders: responseHeaders, responseBody: body
                });
            };
            // Read the body in the background so the page is never blocked
            // and streaming / binary responses are not consumed.
            if (isTextual(response.headers.get('content-type'))) {
                response.clone().text().then(function (t) { report(clip(t)); }, function () { report(null); });
            } else {
                report('[binary: ' + (response.headers.get('content-type') || 'unknown') + ']');
            }
            return response;
        } catch (e) {
            sendToFlutter('network', {
                type: 'fetch', url: url, method: method, status: 0,
                duration: Date.now() - startTime, requestBody: requestBody, requestHeaders: requestHeaders, error: String(e)
            });
            throw e;
        }
    };

    // 5. Hook Network Requests (XHR)
    const originalXHROpen = XMLHttpRequest.prototype.open;
    const originalXHRSend = XMLHttpRequest.prototype.send;
    const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        try { this._requestHeaders[String(name).toLowerCase()] = String(value); } catch (e) { }
        return originalSetRequestHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.open = function(method, url) {
        this._requestMethod = method;
        this._requestUrl = url;
        this._requestHeaders = {};
        return originalXHROpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
        const xhr = this;
        const sendArgs = arguments;
        const net = window._netConfig || {};
        if (net.offline) {
            sendToFlutter('network', { type: 'xhr', url: xhr._requestUrl, method: (xhr._requestMethod || 'GET').toUpperCase(), status: 0, duration: 0, requestBody: typeof body === 'string' ? clip(body) : null, requestHeaders: xhr._requestHeaders, error: 'Simulated offline' });
            setTimeout(function () {
                xhr.dispatchEvent(new ProgressEvent('error'));
                xhr.dispatchEvent(new ProgressEvent('loadend'));
            }, 0);
            return;
        }
        const xhrMethod = (xhr._requestMethod || 'GET').toUpperCase();
        const mock = findMock(xhr._requestUrl, xhrMethod);
        if (mock) {
            console.warn('[Mocked XHR] ' + xhrMethod + ' ' + xhr._requestUrl + ' -> ' + mock.status);
            Object.defineProperty(xhr, 'status', { value: mock.status, configurable: true });
            Object.defineProperty(xhr, 'statusText', { value: 'Mocked', configurable: true });
            Object.defineProperty(xhr, 'responseText', { value: mock.body, configurable: true });
            Object.defineProperty(xhr, 'response', { value: mock.body, configurable: true });
            Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
            xhr.getAllResponseHeaders = function () { return 'content-type: ' + mock.contentType + '\\r\\nx-debug-mock: 1\\r\\n'; };
            xhr.getResponseHeader = function (n) { n = String(n).toLowerCase(); return n === 'content-type' ? mock.contentType : (n === 'x-debug-mock' ? '1' : null); };
            sendToFlutter('network', { type: 'xhr', url: xhr._requestUrl, method: xhrMethod, status: mock.status, duration: (net.latency || 0) + mock.delay, requestBody: typeof body === 'string' ? clip(body) : null, requestHeaders: xhr._requestHeaders, responseHeaders: { 'content-type': mock.contentType, 'x-debug-mock': '1' }, responseBody: clip(mock.body) });
            setTimeout(function () {
                xhr.dispatchEvent(new Event('readystatechange'));
                xhr.dispatchEvent(new ProgressEvent('load'));
                xhr.dispatchEvent(new ProgressEvent('loadend'));
            }, (net.latency || 0) + mock.delay);
            return;
        }

        this._startTime = Date.now();
        this.addEventListener('load', function() {
            const duration = Date.now() - this._startTime;
            sendToFlutter('network', {
                type: 'xhr',
                url: this._requestUrl,
                method: (this._requestMethod || 'GET').toUpperCase(),
                status: this.status,
                duration: duration,
                requestHeaders: this._requestHeaders,
                responseHeaders: parseRawHeaders(this.getAllResponseHeaders()),
                requestBody: typeof body === 'string' ? clip(body) : null,
                responseBody: (this.responseType === '' || this.responseType === 'text') ? clip(this.responseText) : '[' + this.responseType + ' response]'
            });
        });
        this.addEventListener('error', function() {
            const duration = Date.now() - this._startTime;
            sendToFlutter('network', {
                type: 'xhr',
                url: this._requestUrl,
                method: (this._requestMethod || 'GET').toUpperCase(),
                status: 0,
                duration: duration,
                requestHeaders: this._requestHeaders,
                error: 'XHR Error'
            });
        });
        if (net.latency > 0) {
            setTimeout(function () { originalXHRSend.apply(xhr, sendArgs); }, net.latency);
            return;
        }
        return originalXHRSend.apply(this, arguments);
    };

    // 5. Send Storage Info periodically or on request
    function sendStorageInfo() {
        try {
            const local = JSON.stringify(localStorage);
            const session = JSON.stringify(sessionStorage);
            const cookies = document.cookie;
            sendToFlutter('storage', {
                localStorage: local,
                sessionStorage: session,
                cookies: cookies
            });
        } catch (e) { }
    }
    
    // 6. Send Device/Performance Info on load
    window.addEventListener('load', () => {
        sendStorageInfo();
        
        setTimeout(() => {
            if (window.performance && window.performance.timing) {
                const t = window.performance.timing;
                const pageLoadTime = t.loadEventEnd - t.navigationStart;
                const domLoadTime = t.domComplete - t.domLoading;
                
                let firstPaint = 0;
                let firstContentfulPaint = 0;
                if (window.performance.getEntriesByType) {
                    const paints = window.performance.getEntriesByType('paint');
                    paints.forEach(p => {
                        if (p.name === 'first-paint') firstPaint = p.startTime;
                        if (p.name === 'first-contentful-paint') firstContentfulPaint = p.startTime;
                    });
                }
                
                let memory = {};
                if (window.performance.memory) {
                    memory = {
                        jsHeapSizeLimit: window.performance.memory.jsHeapSizeLimit,
                        totalJSHeapSize: window.performance.memory.totalJSHeapSize,
                        usedJSHeapSize: window.performance.memory.usedJSHeapSize
                    };
                }

                sendToFlutter('performance', {
                    pageLoadTime: pageLoadTime,
                    domLoadTime: domLoadTime,
                    firstPaint: firstPaint,
                    firstContentfulPaint: firstContentfulPaint,
                    memory: memory
                });
            }
            
            sendToFlutter('device', {
                userAgent: navigator.userAgent,
                screenWidth: window.screen.width,
                screenHeight: window.screen.height,
                pixelRatio: window.devicePixelRatio,
                platform: navigator.platform,
                language: navigator.language,
                timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
            });
        }, 1000);
    });

    window.enableInspector = function() {
        if (window._inspectorEnabled) return;
        window._inspectorEnabled = true;
        
        const overlay = document.createElement('div');
        overlay.id = 'debug-inspector-overlay';
        overlay.style.position = 'fixed';
        overlay.style.pointerEvents = 'none';
        overlay.style.zIndex = '999999';
        overlay.style.backgroundColor = 'rgba(104, 182, 255, 0.4)';
        overlay.style.border = '2px solid rgb(104, 182, 255)';
        overlay.style.transition = 'all 0.1s ease';
        document.body.appendChild(overlay);
        
        window._inspectorMove = function(e) {
            const el = document.elementFromPoint(e.clientX, e.clientY);
            if (!el || el === overlay) return;
            const rect = el.getBoundingClientRect();
            overlay.style.top = rect.top + 'px';
            overlay.style.left = rect.left + 'px';
            overlay.style.width = rect.width + 'px';
            overlay.style.height = rect.height + 'px';
        };
        
        window._inspectorClick = function(e) {
            e.preventDefault();
            e.stopPropagation();
            const el = document.elementFromPoint(e.clientX, e.clientY);
            if (!el) return;
            
            const styles = window.getComputedStyle(el);
            const styleObj = {
                color: styles.color,
                backgroundColor: styles.backgroundColor,
                fontSize: styles.fontSize,
                margin: styles.margin,
                padding: styles.padding,
                display: styles.display,
                width: styles.width,
                height: styles.height
            };
            
            const nodeInfo = {
                tagName: el.tagName.toLowerCase(),
                id: el.id,
                className: typeof el.className === 'string' ? el.className : '',
                styles: styleObj,
                text: el.innerText ? el.innerText.substring(0, 50) : ''
            };
            
            sendToFlutter('dom_node', (window.__dbg && window.__dbg.nodeDetails) ? window.__dbg.nodeDetails(el) : nodeInfo);
        };
        
        document.addEventListener('mousemove', window._inspectorMove, true);
        window._inspectorTouch = function(e) { if (e.touches && e.touches[0]) window._inspectorMove(e.touches[0]); };
        document.addEventListener('touchmove', window._inspectorTouch, true);
        document.addEventListener('click', window._inspectorClick, true);
    };

    window.disableInspector = function() {
        window._inspectorEnabled = false;
        const overlay = document.getElementById('debug-inspector-overlay');
        if (overlay) overlay.remove();
        document.removeEventListener('mousemove', window._inspectorMove, true);
        document.removeEventListener('touchmove', window._inspectorTouch, true);
        document.removeEventListener('click', window._inspectorClick, true);
    };

})();
''';
