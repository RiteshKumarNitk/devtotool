// Debug SDK injected into web pages

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
            originalConsole[method].apply(console, args);
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
    const originalFetch = window.fetch;
    window.fetch = async function (...args) {
        const startTime = Date.now();
        const requestUrl = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url ? args[0].url : 'Unknown');
        const method = (args[1] && args[1].method) || (args[0] && args[0].method) || 'GET';
        const body = (args[1] && args[1].body) ? args[1].body : null;

        try {
            const response = await originalFetch.apply(this, args);
            const duration = Date.now() - startTime;
            
            // Clone response to read it without consuming the original
            const clonedResponse = response.clone();
            let responseText = '';
            try {
                responseText = await clonedResponse.text();
            } catch(e) {}

            sendToFlutter('network', {
                type: 'fetch',
                url: requestUrl,
                method: method.toUpperCase(),
                status: response.status,
                duration: duration,
                requestBody: body ? String(body) : null,
                responseBody: responseText
            });

            return response;
        } catch (error) {
            const duration = Date.now() - startTime;
            sendToFlutter('network', {
                type: 'fetch',
                url: requestUrl,
                method: method.toUpperCase(),
                status: 0,
                duration: duration,
                error: error.message
            });
            throw error;
        }
    };

    // 4. Hook XMLHttpRequest
    const originalXHRSend = XMLHttpRequest.prototype.send;
    const originalXHROpen = XMLHttpRequest.prototype.open;

    XMLHttpRequest.prototype.open = function(method, url, ...args) {
        this._requestMethod = method;
        this._requestUrl = url;
        this._startTime = Date.now();
        return originalXHROpen.apply(this, [method, url, ...args]);
    };

    XMLHttpRequest.prototype.send = function(body) {
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

    // 5. Send Storage Info periodically or on request (We'll send on load)
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
        
        // Performance
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
            
            // Device Info
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

})();
