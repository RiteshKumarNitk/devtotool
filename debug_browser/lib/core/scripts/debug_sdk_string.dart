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
    window._apiMocks = {};
    window.updateApiMocks = function(mocksJson) {
        try { window._apiMocks = JSON.parse(mocksJson) || {}; } catch (e) { window._apiMocks = {}; }
    };
    function findMock(url) {
        if (!url) return null;
        for (const pattern in window._apiMocks) {
            if (String(url).indexOf(pattern) !== -1) return window._apiMocks[pattern];
        }
        return null;
    }
    const MAX_BODY = 100 * 1024;
    function clip(text) {
        if (text == null) return null;
        text = String(text);
        return text.length > MAX_BODY ? text.substring(0, MAX_BODY) + '... [truncated]' : text;
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

        const mockBody = findMock(url);
        if (mockBody !== null) {
            console.warn('[Mocked Fetch] ' + method + ' ' + url);
            sendToFlutter('network', { type: 'fetch', url: url, method: method, status: 200, duration: 0, requestBody: requestBody, responseBody: clip(mockBody) });
            return new Response(mockBody, { status: 200, statusText: 'OK', headers: { 'Content-Type': 'application/json' } });
        }

        const startTime = Date.now();
        try {
            const response = await originalFetch.apply(this, arguments);
            const duration = Date.now() - startTime;
            const report = function (body) {
                sendToFlutter('network', {
                    type: 'fetch', url: url, method: method, status: response.status,
                    duration: duration, requestBody: requestBody, responseBody: body
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
                duration: Date.now() - startTime, requestBody: requestBody, error: String(e)
            });
            throw e;
        }
    };

    // 5. Hook Network Requests (XHR)
    const originalXHROpen = XMLHttpRequest.prototype.open;
    const originalXHRSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
        this._requestMethod = method;
        this._requestUrl = url;
        return originalXHROpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
        const xhr = this;
        const mockBody = findMock(xhr._requestUrl);
        if (mockBody !== null) {
            console.warn('[Mocked XHR] ' + xhr._requestUrl);
            Object.defineProperty(xhr, 'status', { value: 200, configurable: true });
            Object.defineProperty(xhr, 'statusText', { value: 'OK', configurable: true });
            Object.defineProperty(xhr, 'responseText', { value: mockBody, configurable: true });
            Object.defineProperty(xhr, 'response', { value: mockBody, configurable: true });
            Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
            sendToFlutter('network', { type: 'xhr', url: xhr._requestUrl, method: (xhr._requestMethod || 'GET').toUpperCase(), status: 200, duration: 0, requestBody: body ? clip(body) : null, responseBody: clip(mockBody) });
            // Fire asynchronously, like a real request, so both on* handlers
            // and addEventListener listeners run.
            setTimeout(function () {
                xhr.dispatchEvent(new Event('readystatechange'));
                xhr.dispatchEvent(new ProgressEvent('load'));
                xhr.dispatchEvent(new ProgressEvent('loadend'));
            }, 0);
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
                error: 'XHR Error'
            });
        });
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
            
            sendToFlutter('dom_node', nodeInfo);
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
