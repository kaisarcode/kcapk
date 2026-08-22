/**
 * KcSplash - common kcapk splash library.
 * Summary: Bridges provisioning progress from NativeBridge into render callbacks registered by the per-project splash page.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    var statusFn = null;
    var progressFn = null;
    var warningFn = null;
    var pendingStatus = null;
    var pendingProgress = null;
    var pendingWarning = null;

    function fmt(n) {
        n = Math.max(0, n);
        if (n < 1024) return n + ' B';
        if (n < 1048576) return (n / 1024).toFixed(1) + ' KiB';
        return (n / 1048576).toFixed(1) + ' MiB';
    }

    function percent(done, total) {
        if (total <= 0) return 0;
        return Math.min(100, Math.floor(100 * done / total));
    }

    function computeProgress(done, total, current, curDone, curTotal) {
        var parts = [];
        if (current && current !== '') {
            if (curTotal > 0) parts.push(current + ' ' + fmt(curDone) + ' / ' + fmt(curTotal));
            else parts.push(current + ' ' + fmt(curDone));
        }
        if (total > 0) parts.push('total ' + fmt(done) + ' / ' + fmt(total) + ' (' + percent(done, total) + '%)');
        else parts.push('downloaded ' + fmt(done));
        return {
            done: done,
            total: total,
            percent: percent(done, total),
            current: current,
            currentDone: curDone,
            currentTotal: curTotal,
            summary: parts.join(' \u00b7 ')
        };
    }

    function deliver(fn, value) {
        if (fn) {
            fn(value);
            return null;
        }
        return value;
    }

    function setupNativeBridge() {
        if (!window.NativeBridge) {
            window.NativeBridge = {};
        }

        window.NativeBridge.setStatus = function (s) {
            pendingStatus = deliver(statusFn, s);
        };

        window.NativeBridge.setProgress = function (done, total, current, curDone, curTotal) {
            pendingProgress = deliver(progressFn, computeProgress(done, total, current, curDone, curTotal));
        };

        window.NativeBridge.setWarning = function (w) {
            pendingWarning = deliver(warningFn, w);
        };

        window.NativeBridge.invoke = function (method, params) {
            return new Promise(function (resolve, reject) {
                try {
                    var paramsJson = JSON.stringify({
                        method: method,
                        params: params === undefined ? null : params
                    });
                    var resultJson = window.NativeBridge._invoke(method, paramsJson);
                    var result = JSON.parse(resultJson);
                    if (result.ok) {
                        resolve(result.result !== undefined ? result.result : {ok: true});
                    } else {
                        reject(result.error || {code: 'INTERNAL_ERROR', message: 'Bridge error'});
                    }
                } catch (e) {
                    reject({code: 'INTERNAL_ERROR', message: String(e)});
                }
            });
        };
    }

    setupNativeBridge();

    window.KcSplash = {};

    window.KcSplash.onStatus = function (fn) {
        statusFn = fn;
        if (pendingStatus !== null) {
            fn(pendingStatus);
            pendingStatus = null;
        }
    };

    window.KcSplash.onProgress = function (fn) {
        progressFn = fn;
        if (pendingProgress !== null) {
            fn(pendingProgress);
            pendingProgress = null;
        }
    };

    window.KcSplash.onWarning = function (fn) {
        warningFn = fn;
        if (pendingWarning !== null) {
            fn(pendingWarning);
            pendingWarning = null;
        }
    };
})();
