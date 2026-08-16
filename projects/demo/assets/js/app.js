/**
 * redp2p demo app script.
 * Summary: Controls redp2p tunnels through the KcSplash runner interface.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    console.log('app.js loaded');

    var output = document.getElementById('output');
    var status = document.getElementById('status');

    /**
     * Sets the status text in the footer.
     * @param text Status text.
     * @return 0 on success.
     */
    function setStatus(text) {
        if (status) status.textContent = text;
        console.log('STATUS: ' + text);
    }

    /**
     * Logs a message to the output area.
     * @param text Message text.
     * @return 0 on success.
     */
    function log(text) {
        if (output) output.textContent = text + '\n';
        console.log('LOG: ' + text);
    }

    /**
     * Runs a redp2p command through the native bridge.
     * @param cmd Command name.
     * @param args Command arguments.
     * @return Parsed result JSON, or null on failure.
     */
    function runCommand(cmd, args) {
        var payload = JSON.stringify({lib: "redp2p", cmd: cmd, args: args});
        log('→ ' + payload);
        var result = AndroidBridge.runKclib(payload, '');
        if (result === null || result === undefined || result === '') {
            log('error: no output from runner (native bridge not provisioned?)');
            return null;
        }
        if (result.indexOf('error:') === 0) {
            log('error: ' + result);
            return null;
        }
        try {
            return JSON.parse(result);
        } catch (e) {
            log('error parsing result: ' + result);
            return null;
        }
    }

    /**
     * Opens a redp2p operation and returns the handle.
     * @param op Operation name.
     * @param args Operation arguments.
     * @return Handle string, or null on failure.
     */
    function runOpen(op, args) {
        var payload = {cmd: 'open', args: args};
        var result = runCommand('open', args);
        if (!result) return null;
        try {
            var parsed = JSON.parse(result);
            if (parsed.result && parsed.result.handle) {
                return parsed.result.handle;
            }
        } catch (e) {
            log('error parsing open result: ' + result);
        }
        return null;
    }

    /**
     * Reads the status of a redp2p operation.
     * @param handle Operation handle.
     * @return Status result JSON, or null on failure.
     */
    function runStatus(handle) {
        var result = runCommand('status', {handle: handle});
        if (!result) return null;
        try {
            return JSON.parse(result);
        } catch (e) {
            log('error parsing status: ' + result);
            return null;
        }
    }

    /**
     * Stops a redp2p operation.
     * @param handle Operation handle.
     * @return Result JSON, or null on failure.
     */
    function runStop(handle) {
        var result = runCommand('stop', {handle: handle});
        if (!result) return null;
        try {
            return JSON.parse(result);
        } catch (e) {
            log('error parsing stop: ' + result);
            return null;
        }
    }

    /**
     * Closes a redp2p operation.
     * @param handle Operation handle.
     * @return Result JSON, or null on failure.
     */
    function runClose(handle) {
        var result = runCommand('close', {handle: handle});
        if (!result) return null;
        try {
            return JSON.parse(result);
        } catch (e) {
            log('error parsing close: ' + result);
            return null;
        }
    }

    /**
     * Lists publishers on an index server.
     * @param host Index host.
     * @param port Index port.
     * @return List result JSON, or null on failure.
     */
    function runList(host, port) {
        var result = runCommand('list', {host: host, port: port});
        if (!result) return null;
        try {
            return JSON.parse(result);
        } catch (e) {
            log('error parsing list: ' + result);
            return null;
        }
    }

    /**
     * Polls an operation until it finishes.
     * @param handle Operation handle.
     * @return 0 on success.
     */
    function pollStatus(handle) {
        var status = runStatus(handle);
        if (status) {
            if (status.result && status.result.state === 'finished') {
                log('Operation finished with result: ' + JSON.stringify(status.result.result));
                if (status.result.error) {
                    log('Error: ' + status.result.error);
                }
                return;
            }
            if (status.result && status.result.state === 'running') {
                setTimeout(function () { pollStatus(handle); }, 1000);
            }
        }
    }

    /**
     * Runs the local index list test.
     * @return 0 on success.
     */
    function testLocalList() {
        log('Auto-test: Local Index List...');
        var testResult = runCommand('list', {host: '127.0.0.1', port: 9001});
        if (testResult && testResult.result && testResult.result.publishers) {
            log('Publishers:\n' + testResult.result.publishers.join('\n'));
        } else if (testResult) {
            log('List result: ' + JSON.stringify(testResult));
        } else {
            log('Index list test failed');
        }
    }

    /**
     * Runs the local index open test.
     * @return 0 on success.
     */
    function testOpenLocal() {
        log('Auto-test: Open Local Index...');
        var handle = runOpen('idx', {port: 9001});
        if (handle) {
            log('Index opened, handle: ' + handle);
            pollStatus(handle);
        } else {
            log('Failed to open local index');
        }
    }

    testLocalList();
    setTimeout(testOpenLocal, 2000);
})();
