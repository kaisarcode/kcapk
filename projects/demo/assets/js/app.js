/**
 * grd demo app script.
 * Summary: Runs the grd split runner through AndroidBridge and renders the boxes.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');
    var status = document.getElementById('status');

    /**
     * Sets the status text in the footer.
     * @param text Status text.
     * @return 0 on success.
     */
    function setStatus(text) {
        status.textContent = text;
    }

    /**
     * Runs the grd split runner and renders the resulting boxes.
     * @return 0 on success.
     */
    function runGrd() {
        var payload = {
            lib: 'grd',
            cmd: 'split',
            args: {
                w: parseInt(document.getElementById('w').value, 10),
                h: parseInt(document.getElementById('h').value, 10),
                k: document.getElementById('k').value,
                W: document.getElementById('W').value.trim().split(/\s+/).map(Number)
            }
        };

        output.textContent = 'running grd (in-process)...';
        var result = AndroidBridge.runKclib(JSON.stringify(payload), '');

        if (result === null || result === undefined || result === '') {
            output.textContent = 'error: no output from grd (native bridge not provisioned?)';
            return;
        }
        if (result.indexOf('error:') === 0) {
            output.textContent = result;
            return;
        }

        var parsed;
        try {
            parsed = JSON.parse(result);
        } catch (e) {
            output.textContent = result;
            return;
        }

        var boxes = parsed.result && parsed.result.boxes;
        if (!boxes) {
            output.textContent = result;
            return;
        }

        var lines = boxes.map(function (b) {
            return '#' + b.index + ' x=' + b.x + ' y=' + b.y + ' w=' + b.w + ' h=' + b.h;
        });
        output.textContent = lines.join('\n');
    }

    /**
     * Shows the installed dependency status in the footer.
     * @return 0 on success.
     */
    function showDeps() {
        setStatus('deps requested: grd');
    }

    document.getElementById('run').addEventListener('click', runGrd);
    document.getElementById('deps').addEventListener('click', showDeps);
})();
