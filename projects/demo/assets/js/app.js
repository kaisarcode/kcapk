/**
 * redp2p demo app script.
 * Summary: Controls redp2p tunnels through the KcSplash runner interface.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');
    var status = document.getElementById('status');
    var currentHandle = null;

/**
 * Sets the status text in the footer.
 * @param text Status text.
 * @return 0 on success.
 */
function setStatus(text) {
    status.textContent = text;
}

/**
 * Logs a message to the output area.
 * @param text Message text.
 * @return 0 on success.
 */
function log(text) {
    output.textContent = text;
}

    function runCommand(cmd, args) {
        var payload = JSON.stringify({cmd: cmd, args: args});
        log('→ ' + JSON.stringify({cmd: cmd, args: args}));
        var err = null;
        var result = AndroidBridge.runKclib(JSON.stringify({cmd: cmd, args: args}), '');
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

    function runDel(addr) {
        var result = runCommand('del', {addr: addr});
        if (!result) return false;
        try {
            var parsed = JSON.parse(result);
            return parsed.result && parsed.result.ok;
        } catch (e) {
            log('error parsing del: ' + result);
            return false;
        }
    }

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

    function waitForFinished(handle) {
        return new Promise(function (resolve) {
            function poll() {
                if (currentHandle !== handle) {
                    resolve({state: 'stopped'});
                    return;
                }
                var status = runStatus(handle);
                if (status) {
                    if (status.result && status.result.state === 'finished') {
                        resolve(status.result);
                        return;
                    }
                }
                setTimeout(poll, 500);
            }
            poll();
        });
    }

    var currentHandle = null;

    document.getElementById('idxStart').addEventListener('click', function () {
        var port = parseInt(document.getElementById('idxPort').value, 10);
        var seats = parseInt(document.getElementById('idxSeats').value, 10) || 0;
        var pow = parseInt(document.getElementById('idxPow').value, 10) || 0;

        var args = {
            op: 'idx',
            port: port
        };
        if (document.getElementById('idxSeats').value) {
            args.seats = parseInt(document.getElementById('idxSeats').value, 10);
        }
        if (document.getElementById('idxPow').value) {
            args.pow = parseInt(document.getElementById('idxPow').value, 10);
        }
        if (document.getElementById('idxPass').value) {
            args.pass = document.getElementById('idxPass').value;
        }
        if (document.getElementById('idxVip').value) {
            args.vip = document.getElementById('idxVip').value;
        }

        log('Starting index server on port ' + port + '...');
        var handle = runOpen('idx', {port: port, seats: seats, pow: 0});
        if (handle) {
            currentHandle = handle;
            log('Index started, handle: ' + handle);
            pollStatus(handle);
        }
    });

    document.getElementById('idxStop').addEventListener('click', function () {
        if (currentHandle) {
            log('Stopping index...');
            var result = runCommand('stop', {handle: currentHandle});
            log('Stop result: ' + JSON.stringify(runCommand('stop', {handle: currentHandle})));
            runCommand('close', {handle: currentHandle});
            currentHandle = null;
        }
    });

    document.getElementById('idxList').addEventListener('click', function () {
        var port = parseInt(document.getElementById('idxPort').value, 10);
        log('Listing publishers...');
        var result = runList('127.0.0.1', parseInt(document.getElementById('idxPort').value, 10));
        if (result && result.result && result.result.publishers) {
            log('Publishers:\n' + result.result.publishers.join('\n'));
        } else if (result) {
            log('List result: ' + JSON.stringify(result));
        }
    });

    document.getElementById('pubStart').addEventListener('click', function () {
        var proto = document.getElementById('pubProto').value;
        var port = parseInt(document.getElementById('pubPort').value, 10);
        var sweep = parseInt(document.getElementById('pubSweep').value, 10) || 0;
        var stun = document.getElementById('pubStun').value || null;
        var addr = document.getElementById('pubId').value + '@' + document.getElementById('pubIdx').value;

        var args = {
            op: 'pub',
            addr: document.getElementById('pubId').value + '@' + document.getElementById('pubIdx').value,
            sweep: parseInt(document.getElementById('pubSweep').value, 10) || 0
        };
        if (document.getElementById('pubProto').value === 'tcp') {
            args.tcp = parseInt(document.getElementById('pubPort').value, 10);
        } else {
            args.udp = parseInt(document.getElementById('pubPort').value, 10);
        }
        var stun = document.getElementById('pubStun').value;
        if (stun) args.stun = stun;

        log('Publishing ' + document.getElementById('pubId').value + '...');
        var handle = runOpen('pub', {addr: addr, tcp: proto === 'tcp' ? port : undefined, udp: proto === 'udp' ? port : undefined, sweep: sweep, stun: stun});
        if (handle) {
            currentHandle = handle;
            log('Published, handle: ' + handle);
            pollStatus(handle);
        }
    });

    document.getElementById('pubStop').addEventListener('click', function () {
        if (currentHandle) {
            log('Stopping publisher...');
            var result = runCommand('stop', {handle: currentHandle});
            log('Stop result: ' + JSON.stringify(runCommand('stop', {handle: currentHandle})));
            runCommand('close', {handle: currentHandle});
            currentHandle = null;
        }
    });

    document.getElementById('conStart').addEventListener('click', function () {
        var proto = document.getElementById('conProto').value;
        var port = parseInt(document.getElementById('conPort').value, 10);
        var sweep = parseInt(document.getElementById('conSweep').value, 10) || 0;

        var addr = document.getElementById('conId').value + '@' + document.getElementById('conIdx').value;
        var args = {
            op: 'con',
            addr: addr,
            sweep: parseInt(document.getElementById('conSweep').value, 10) || 0
        };
        if (document.getElementById('conProto').value === 'tcp') {
            args.tcp = parseInt(document.getElementById('conPort').value, 10);
        } else {
            args.udp = parseInt(document.getElementById('conPort').value, 10);
        }

        log('Connecting to ' + document.getElementById('conId').value + '...');
        var handle = runOpen('con', {addr: addr, tcp: proto === 'tcp' ? port : undefined, udp: proto === 'udp' ? port : undefined, sweep: sweep});
        if (handle) {
            currentHandle = handle;
            log('Connecting, handle: ' + handle);
            pollStatus(handle);
        }
    });

    document.getElementById('conStop').addEventListener('click', function () {
        if (currentHandle) {
            log('Stopping consumer...');
            var result = runCommand('stop', {handle: currentHandle});
            log('Stop result: ' + JSON.stringify(runCommand('stop', {handle: currentHandle})));
            runCommand('close', {handle: currentHandle});
            currentHandle = null;
        }
    });

    document.getElementById('delBtn').addEventListener('click', function () {
        var addr = document.getElementById('delId').value + '@' + document.getElementById('delIdx').value;
        log('Deleting ' + addr + '...');
        var ok = runDel(addr);
        if (ok) {
            log('Deleted successfully');
        } else {
            log('Delete failed');
        }
    });

    document.getElementById('listBtn').addEventListener('click', function () {
        var port = parseInt(document.getElementById('idxPort').value, 10);
        log('Listing publishers...');
        var result = runList('127.0.0.1', parseInt(document.getElementById('idxPort').value, 10));
        if (result && result.result && result.result.publishers) {
            log('Publishers:\n' + result.result.publishers.join('\n'));
        } else if (result) {
            log('List result: ' + JSON.stringify(result));
        }
    });

    document.getElementById('deps').addEventListener('click', function () {
        var result = runCommand('list', {host: '127.0.0.1', port: 9001});
        if (result && result.result && result.result.publishers) {
            log('Deps:\n' + result.result.publishers.join('\n'));
        }
    });

    log('Auto-test: Index List...');
    var testResult = runCommand('list', {host: '127.0.0.1', port: 9001});
    if (testResult && testResult.result && testResult.result.publishers) {
        log('Publishers:\n' + testResult.result.publishers.join('\n'));
    } else if (testResult) {
        log('List result: ' + JSON.stringify(testResult));
    } else {
        log('Index list test failed');
    }
})();
        if (currentHandle !== handle) return;
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
    document.getElementById('testIdx').addEventListener('click', function () {
        log('Testing Index List...');
        var result = runCommand('list', {host: '127.0.0.1', port: 9001});
        if (result && result.result && result.result.publishers) {
            log('Publishers:\n' + result.result.publishers.join('\n'));
        } else if (result) {
            log('List result: ' + JSON.stringify(result));
        } else {
            log('Index list test failed');
        }
    });

    document.getElementById('testDel').addEventListener('click', function () {
        log('Testing Delete...');
        var ok = runDel('web@127.0.0.1:9001');
        if (ok) {
            log('Delete successful');
        } else {
            log('Delete failed');
        }
    });

    document.getElementById('testOpenIdx').addEventListener('click', function () {
        log('Testing Open Index...');
        var handle = runOpen('idx', {port: 9001});
        if (handle) {
            currentHandle = handle;
            log('Index opened, handle: ' + handle);
            pollStatus(handle);
        } else {
            log('Failed to open index');
        }
    });
})();
