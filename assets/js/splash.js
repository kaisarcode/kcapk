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
    var invokeSeq = 0;
    var invokePending = {};

    /**
     * Formats a byte count as a compact human-readable string.
     * @param n Byte count to format.
     * @return Formatted size such as "512 B" or "1.5 MiB".
     */
    function fmt(n) {
        n = Math.max(0, n);
        if (n < 1024) return n + ' B';
        if (n < 1048576) return (n / 1024).toFixed(1) + ' KiB';
        return (n / 1048576).toFixed(1) + ' MiB';
    }

    /**
     * Computes an integer percentage clamped to 0-100.
     * @param done Completed byte count.
     * @param total Total byte count.
     * @return Percentage from 0 to 100.
     */
    function percent(done, total) {
        if (total <= 0) return 0;
        return Math.min(100, Math.floor(100 * done / total));
    }

    /**
     * Builds the progress snapshot handed to the page render callback.
     * @param done Aggregate completed byte count.
     * @param total Aggregate total byte count.
     * @param current Name of the file being downloaded.
     * @param curDone Completed byte count of the current file.
     * @param curTotal Total byte count of the current file.
     * @return Progress snapshot for the page render callback.
     */
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

    /**
     * Delivers a value to a registered callback or parks it until registration.
     * @param fn Registered render callback or null.
     * @param value Value produced by the bridge.
     * @return Null when delivered, otherwise the parked value.
     */
    function deliver(fn, value) {
        if (fn) {
            fn(value);
            return null;
        }
        return value;
    }

    /**
     * Installs the NativeBridge shims: events park until callbacks register,
     * and invoke responses settle their Promises.
     * @return None.
     */
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
            var id = String(++invokeSeq);
            return new Promise(function (resolve, reject) {
                invokePending[id] = {resolve: resolve, reject: reject};
                try {
                    var paramsJson = JSON.stringify({
                        id: id,
                        method: method,
                        params: params === undefined ? null : params
                    });
                    window.NativeBridge._invoke(method, paramsJson);
                } catch (e) {
                    delete invokePending[id];
                    reject({code: 'INTERNAL_ERROR', message: String(e)});
                }
            });
        };

        window.NativeBridge._receive = function (id, response) {
            var pending = invokePending[id];
            if (!pending) return;
            delete invokePending[id];
            if (!response || typeof response !== 'object') {
                pending.reject({code: 'INTERNAL_ERROR', message: 'Invalid bridge response'});
                return;
            }
            if (response.ok) {
                pending.resolve(response.result !== undefined ? response.result : {ok: true});
            } else {
                pending.reject(response.error || {code: 'INTERNAL_ERROR', message: 'Bridge error'});
            }
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
