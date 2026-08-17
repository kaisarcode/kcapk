/**
 * redp2p demo app script.
 * Summary: Exercises the redp2p runner through the AndroidBridge.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    console.log('app.js loaded');

    var output = document.getElementById('output');
    var status = document.getElementById('status');
    var currentHandle = null;
    var INDEX_PORT = 9001;
    var REMOTE_HOST = '190.105.227.97';
    var REMOTE_PORT = 9001;
    var PUB_ID = 'kcapk';
    var CON_LISTEN_TCP = 40001;

    /**
     * Sets the status text in the header.
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
        if (output) output.textContent += text + '\n';
        console.log('LOG: ' + text);
    }

    /**
     * Runs one redp2p runner command through the native bridge.
     * @param cmd Command name.
     * @param args Command arguments object.
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
     * Starts the local index server.
     * @param port Index port.
     * @return Runner handle, or null on failure.
     */
    function startIndex(port) {
        log('Auto-test: start index on port ' + port + '...');
        var result = runCommand('open', {op: 'idx', port: port});
        if (!result || !result.handle) {
            log('start index failed');
            return null;
        }
        currentHandle = result.handle;
        log('Index started, handle: ' + result.handle);
        return result.handle;
    }

    /**
     * Lists publishers registered on the index.
     * @param host Index host.
     * @param port Index port.
     * @return Parsed result, or null on failure.
     */
    function listPublishers(host, port) {
        log('Auto-test: list publishers on ' + host + ':' + port + '...');
        var result = runCommand('list', {host: host, port: port});
        if (!result || !result.result) {
            log('list failed');
            return null;
        }
        if (result.result.publishers) {
            log('Publishers: ' + result.result.publishers.length);
        } else {
            log('List result: ' + JSON.stringify(result.result));
        }
        return result;
    }

    /**
     * Reads the status of one runner operation.
     * @param handle Runner handle.
     * @return Status result object, or null on failure.
     */
    function readStatus(handle) {
        var result = runCommand('status', {handle: handle});
        if (!result || !result.result) {
            log('status failed');
            return null;
        }
        log('Status: ' + JSON.stringify(result.result));
        return result.result;
    }

    /**
     * Stops one runner operation.
     * @param handle Runner handle.
     * @return 0 on success.
     */
    function stopOperation(handle) {
        log('Auto-test: stop handle ' + handle + '...');
        var result = runCommand('stop', {handle: handle});
        if (!result) {
            log('stop failed');
            return 1;
        }
        log('Stop result: ' + JSON.stringify(result.result));
        return 0;
    }

    /**
     * Closes one runner handle.
     * @param handle Runner handle.
     * @return 0 on success.
     */
    function closeHandle(handle) {
        log('Auto-test: close handle ' + handle + '...');
        var result = runCommand('close', {handle: handle});
        if (!result) {
            log('close failed');
            return 1;
        }
        log('Close result: ' + JSON.stringify(result.result));
        currentHandle = null;
        return 0;
    }

    /**
     * Starts a publisher on the remote index with a custom key directory.
     * @param id Publisher identifier.
     * @param host Index host.
     * @param port Index port.
     * @return Runner handle, or null on failure.
     */
    function startPub(id, host, port) {
        var addr = id + '@' + host + ':' + port;
        var keysDir = '';
        try {
            keysDir = AndroidBridge.getFilesDir();
        } catch (e) {
            log('getFilesDir failed: ' + e);
        }
        log('Auto-test: publish ' + addr + ' keys_dir=' + keysDir + '...');
        var args = {
            op: 'pub',
            addr: addr,
            pass: '1234',
            tcp: 40002,
            sweep: 0
        };
        if (keysDir) args.keys_dir = keysDir;
        var result = runCommand('open', args);
        if (!result || !result.handle) {
            log('publish failed');
            return null;
        }
        log('Published, handle: ' + result.handle);
        return result.handle;
    }

    /**
     * Connects a consumer to a publisher on the remote index.
     * @return Runner handle, or null on failure.
     */
    function startCon() {
        var addr = PUB_ID + '@' + REMOTE_HOST + ':' + REMOTE_PORT;
        log('Auto-test: connect to ' + addr + ' tcp ' + CON_LISTEN_TCP + '...');
        var result = runCommand('open', {
            op: 'con',
            addr: addr,
            tcp: CON_LISTEN_TCP,
            sweep: 0
        });
        if (!result || !result.handle) {
            log('connect failed');
            return null;
        }
        log('Connected, handle: ' + result.handle);
        return result.handle;
    }

    /**
     * Runs the full index lifecycle test.
     * @return 0 on success.
     */
    function runIndexTest() {
        var handle = startIndex(INDEX_PORT);
        if (handle === null) return 1;

        setTimeout(function () {
            readStatus(handle);
            listPublishers('127.0.0.1', INDEX_PORT);
            stopOperation(handle);
            closeHandle(handle);
            listPublishers(REMOTE_HOST, REMOTE_PORT);
        }, 1500);

        setTimeout(function () {
            var pub = startPub(PUB_ID, REMOTE_HOST, REMOTE_PORT);
            if (pub === null) return 1;
            setTimeout(function () {
                readStatus(pub);
                listPublishers(REMOTE_HOST, REMOTE_PORT);
            }, 3000);
        }, 3500);

        setTimeout(function () {
            var con = startCon();
            if (con === null) return 1;
            setTimeout(function () {
                readStatus(con);
                listPublishers(REMOTE_HOST, REMOTE_PORT);
                setStatus('Tunnel ready, send data via adb forward 40001');
            }, 3000);
        }, 7000);
        return 0;
    }

    runIndexTest();
})();
