/**
 * redp2p demo app script.
 * Summary: Exercises the redp2p runner through the NativeBridge.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    console.log('app.js loaded');

    var output = document.getElementById('output');
    var currentHandle = null;
    var INDEX_PORT = 9001;
    var REMOTE_HOST = '190.105.227.97';
    var REMOTE_PORT = 9001;
    var REMOTE_PASS = 'AqKT3xFR4kWKhC7pxq26kE56DpSy7Fb6uvoXNWkuPz6m2pDwbkDzEoUjdAP';
    var PUB_ID = 'kcapk';
    var CON_LISTEN_TCP = 40001;
    var results = [];

    /**
     * Appends one line to the on-screen test output and the console.
     * @param text Line to append.
     * @return None.
     */
    function log(text) {
        if (output) output.textContent += text + '\n';
        console.log('LOG: ' + text);
    }

    /**
     * Stores one test outcome and prints its PASS or FAIL line.
     * @param name Test name.
     * @param ok True when the test passed.
     * @param detail Optional result detail appended to the line.
     * @return None.
     */
    function recordResult(name, ok, detail) {
        results.push({name: name, ok: ok, detail: detail || ''});
        log((ok ? 'PASS' : 'FAIL') + ' ' + name + (detail ? ' - ' + detail : ''));
    }

    /**
     * Prints the final PASS and FAIL counts collected so far.
     * @return None.
     */
    function printSummary() {
        var passed = 0, failed = 0;
        for (var i = 0; i < results.length; i++) {
            if (results[i].ok) passed++; else failed++;
        }
        log('');
        log('=== SUMMARY ===');
        log('Passed: ' + passed + ' / ' + results.length);
        if (failed > 0) log('Failed: ' + failed);
        log('===============');
    }

    /**
     * Runs one redp2p runner command through the native bridge.
     * @param cmd Command name.
     * @param args Command arguments object.
     * @return Promise resolving to parsed result JSON, or null on failure.
     */
    function runCommand(cmd, args) {
        var payload = {lib: "redp2p", cmd: cmd, args: args};
        log('\u2192 ' + JSON.stringify(payload));
        return NativeBridge.invoke("runKclib", payload)
            .then(function (result) {
                return result;
            })
            .catch(function (err) {
                log('error: ' + JSON.stringify(err));
                return null;
            });
    }

    /**
     * Starts the local index server.
     * @param port Index port.
     * @return Promise resolving to runner handle, or null on failure.
     */
    function startIndex(port) {
        log('Auto-test: start index on port ' + port + '...');
        return runCommand('open', {op: 'idx', port: port})
            .then(function (result) {
                if (!result || !result.handle) {
                    recordResult('start index', false, 'no handle');
                    return null;
                }
                currentHandle = result.handle;
                recordResult('start index', true, 'handle: ' + result.handle);
                return result.handle;
            });
    }

    /**
     * Lists publishers registered on the index.
     * @param host Index host.
     * @param port Index port.
     * @return Promise resolving to parsed result, or null on failure.
     */
    function listPublishers(host, port) {
        log('Auto-test: list publishers on ' + host + ':' + port + '...');
        return runCommand('list', {host: host, port: port})
            .then(function (result) {
                if (!result || !result.result) {
                    recordResult('list ' + host + ':' + port, false, 'no result');
                    return null;
                }
                var count = result.result.publishers ? result.result.publishers.length : 0;
                recordResult('list ' + host + ':' + port, true, count + ' publishers');
                return result;
            });
    }

    /**
     * Reads the status of one runner operation.
     * @param handle Runner handle.
     * @return Promise resolving to status result object, or null on failure.
     */
    function readStatus(handle) {
        return runCommand('status', {handle: handle})
            .then(function (result) {
                if (!result || !result.result) {
                    recordResult('status handle ' + handle, false, 'no result');
                    return null;
                }
                recordResult('status handle ' + handle, true, JSON.stringify(result.result));
                return result.result;
            });
    }

    /**
     * Stops one runner operation.
     * @param handle Runner handle.
     * @return Promise resolving to 0 on success.
     */
    function stopOperation(handle) {
        log('Auto-test: stop handle ' + handle + '...');
        return runCommand('stop', {handle: handle})
            .then(function (result) {
                recordResult('stop handle ' + handle, !!result, result ? JSON.stringify(result.result) : 'no result');
                return result ? 0 : 1;
            });
    }

    /**
     * Closes one runner handle.
     * @param handle Runner handle.
     * @return Promise resolving to 0 on success.
     */
    function closeHandle(handle) {
        log('Auto-test: close handle ' + handle + '...');
        return runCommand('close', {handle: handle})
            .then(function (result) {
                recordResult('close handle ' + handle, !!result, result ? JSON.stringify(result.result) : 'no result');
                currentHandle = null;
                return result ? 0 : 1;
            });
    }

    /**
     * Starts a publisher on the remote index with a custom key directory.
     * @param id Publisher identifier.
     * @param host Index host.
     * @param port Index port.
     * @return Promise resolving to runner handle, or null on failure.
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
            pass: REMOTE_PASS,
            tcp: 40002,
            sweep: 0,
            state_dir: keysDir ? keysDir + '/redp2p' : ''
        };
        if (keysDir) args.keys_dir = keysDir;
        return runCommand('open', args)
            .then(function (result) {
                if (!result || !result.handle) {
                    recordResult('publish', false, 'no handle');
                    return null;
                }
                recordResult('publish', true, 'handle: ' + result.handle);
                return result.handle;
            });
    }

    /**
     * Connects a consumer to a publisher on the remote index.
     * @return Promise resolving to runner handle, or null on failure.
     */
    function startCon() {
        var addr = PUB_ID + '@' + REMOTE_HOST + ':' + REMOTE_PORT;
        log('Auto-test: connect to ' + addr + ' tcp ' + CON_LISTEN_TCP + '...');
        return runCommand('open', {
            op: 'con',
            addr: addr,
            tcp: CON_LISTEN_TCP,
            sweep: 0
        })
            .then(function (result) {
                if (!result || !result.handle) {
                    recordResult('connect', false, 'no handle');
                    return null;
                }
                recordResult('connect', true, 'handle: ' + result.handle);
                return result.handle;
            });
    }

    /**
     * Waits for the given number of milliseconds.
     * @param ms Delay in milliseconds.
     * @return Promise resolving after the delay.
     */
    function delay(ms) {
        return new Promise(function (resolve) {
            setTimeout(resolve, ms);
        });
    }

    /**
     * Runs the local index, remote publish, and consumer tests in order.
     * @return None.
     */
    function runIndexTest() {
        startIndex(INDEX_PORT)
            .then(function (handle) {
                if (handle === null) {
                    return null;
                }
                return delay(1500)
                    .then(function () { return readStatus(handle); })
                    .then(function () { return listPublishers('127.0.0.1', INDEX_PORT); })
                    .then(function () { return stopOperation(handle); })
                    .then(function () { return closeHandle(handle); });
            })
            .then(function () { return listPublishers(REMOTE_HOST, REMOTE_PORT); })
            .then(function () {
                return startPub(PUB_ID, REMOTE_HOST, REMOTE_PORT);
            })
            .then(function (pub) {
                if (pub === null) {
                    return null;
                }
                return delay(3000)
                    .then(function () { return readStatus(pub); })
                    .then(function () { return listPublishers(REMOTE_HOST, REMOTE_PORT); })
                    .then(function () { return startCon(); })
                    .then(function (con) {
                        if (con === null) {
                            return null;
                        }
                        return delay(3000)
                            .then(function () { return readStatus(con); })
                            .then(function () { return listPublishers(REMOTE_HOST, REMOTE_PORT); })
                            .then(function () { return stopOperation(con); })
                            .then(function () { return closeHandle(con); });
                    })
                    .then(function () { return stopOperation(pub); })
                    .then(function () { return closeHandle(pub); });
            })
            .then(function () {
                printSummary();
            });
    }

    runIndexTest();
})();
