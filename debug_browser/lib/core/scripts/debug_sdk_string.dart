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
            // originalConsole[method].apply(console, args);
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
        window._apiMocks = JSON.parse(mocksJson);
    };

    // 4. Hook Network Requests (Fetch)
    const originalFetch = window.fetch;
    window.fetch = async function() {
        const url = typeof arguments[0] === 'string' ? arguments[0] : arguments[0].url;
        
        for (const pattern in window._apiMocks) {
            if (url.includes(pattern)) {
                console.warn('[Mocked Fetch] ' + url);
                const mockBody = window._apiMocks[pattern];
                sendToFlutter('network', { type: 'fetch', url: url, method: 'GET', status: 200, duration: 0, responseBody: mockBody });
                return new Response(mockBody, { status: 200, statusText: 'OK' });
            }
        }

        const startTime = Date.now();
        try {
            const response = await originalFetch.apply(this, arguments);
            const clone = response.clone();
            const text = await clone.text();
            const duration = Date.now() - startTime;
            
            let method = 'GET';
            if (arguments[1] && arguments[1].method) method = arguments[1].method;
            
            sendToFlutter('network', {
                type: 'fetch',
                url: url,
                method: method.toUpperCase(),
                status: response.status,
                duration: duration,
                responseBody: text
            });
            return response;
        } catch (e) {
            const duration = Date.now() - startTime;
            sendToFlutter('network', {
                type: 'fetch',
                url: url,
                method: 'GET',
                status: 0,
                duration: duration,
                error: e.toString()
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
        for (const pattern in window._apiMocks) {
            if (this._requestUrl && this._requestUrl.includes(pattern)) {
                console.warn('[Mocked XHR] ' + this._requestUrl);
                const mockBody = window._apiMocks[pattern];
                Object.defineProperty(this, 'status', { value: 200 });
                Object.defineProperty(this, 'responseText', { value: mockBody });
                Object.defineProperty(this, 'readyState', { value: 4 });
                sendToFlutter('network', { type: 'xhr', url: this._requestUrl, method: this._requestMethod, status: 200, duration: 0, responseBody: mockBody });
                if (this.onload) this.onload();
                if (this.onreadystatechange) this.onreadystatechange();
                return;
            }
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
                requestBody: body ? String(body) : null,
                responseBody: this.responseText || ''
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
            
            window.DebugBridge.postMessage(JSON.stringify({ type: 'dom_node', data: nodeInfo }));
        };
        
        document.addEventListener('mousemove', window._inspectorMove, true);
        document.addEventListener('touchmove', function(e) { window._inspectorMove(e.touches[0]); }, true);
        document.addEventListener('click', window._inspectorClick, true);
    };

    window.disableInspector = function() {
        window._inspectorEnabled = false;
        const overlay = document.getElementById('debug-inspector-overlay');
        if (overlay) overlay.remove();
        document.removeEventListener('mousemove', window._inspectorMove, true);
        document.removeEventListener('touchmove', window._inspectorMove, true);
        document.removeEventListener('click', window._inspectorClick, true);
    };

})();
''';
