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

    /**
     * Formats a byte count for display.
     * @param n Byte count.
     * @return Formatted string.
     */
    function fmt(n) {
        n = Math.max(0, n);
        if (n < 1024) return n + ' B';
        if (n < 1048576) return (n / 1024).toFixed(1) + ' KiB';
        return (n / 1048576).toFixed(1) + ' MiB';
    }

    /**
     * Computes the integer percentage of done over total.
     * @param done Bytes done.
     * @param total Bytes total.
     * @return Percentage 0..100.
     */
    function percent(done, total) {
        if (total <= 0) return 0;
        return Math.min(100, Math.floor(100 * done / total));
    }

    /**
     * Computes the progress value handed to the registered render callback.
     * @param done Aggregate bytes done.
     * @param total Aggregate bytes total.
     * @param current Current file label.
     * @param curDone Current file bytes done.
     * @param curTotal Current file bytes total.
     * @return Progress value object.
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
     * Calls a callback with a value, or buffers it when no callback is set.
     * @param fn Callback or null.
     * @param value Value to deliver.
     * @return Buffered value when no callback is set, null otherwise.
     */
    function deliver(fn, value) {
        if (fn) {
            fn(value);
            return null;
        }
        return value;
    }

    /**
     * Receives provisioning status text from the native bridge.
     * @param s Status text.
     */
    window.NativeBridge.setStatus = function (s) {
        pendingStatus = deliver(statusFn, s);
    };

    /**
     * Receives provisioning progress from the native bridge.
     * @param done Aggregate bytes done.
     * @param total Aggregate bytes total.
     * @param current Current file label.
     * @param curDone Current file bytes done.
     * @param curTotal Current file bytes total.
     */
    window.NativeBridge.setProgress = function (done, total, current, curDone, curTotal) {
        pendingProgress = deliver(progressFn, computeProgress(done, total, current, curDone, curTotal));
    };

    /**
     * Receives provisioning warning text from the native bridge.
     * @param w Warning text.
     */
    window.NativeBridge.setWarning = function (w) {
        pendingWarning = deliver(warningFn, w);
    };

    window.KcSplash = {};

    /**
     * Registers the render callback for status text.
     * @param fn Function receiving the status string.
     */
    window.KcSplash.onStatus = function (fn) {
        statusFn = fn;
        if (pendingStatus !== null) {
            fn(pendingStatus);
            pendingStatus = null;
        }
    };

    /**
     * Registers the render callback for progress values.
     * @param fn Function receiving the progress value object.
     */
    window.KcSplash.onProgress = function (fn) {
        progressFn = fn;
        if (pendingProgress !== null) {
            fn(pendingProgress);
            pendingProgress = null;
        }
    };

    /**
     * Registers the render callback for warning text.
     * @param fn Function receiving the warning string.
     */
    window.KcSplash.onWarning = function (fn) {
        warningFn = fn;
        if (pendingWarning !== null) {
            fn(pendingWarning);
            pendingWarning = null;
        }
    };
})();
