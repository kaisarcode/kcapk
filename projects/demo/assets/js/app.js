/**
 * redp2p demo app script.
 * Summary: Verifies generated typed redp2p dispatch.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');
    var context;

    window.NativeBridge.redp2p.redp2p_is_valid_id('demo').then(function (valid) {
        if (valid !== 1) {
            throw new Error('typed string parameter was rejected');
        }
        return window.NativeBridge.redp2p.redp2p_open();
    }).then(function (handle) {
        if (!handle) {
            throw new Error('typed opaque output was not returned');
        }
        context = handle;
        return window.NativeBridge.redp2p.redp2p_set_vip(context, 'a,b', 64);
    }).then(function () {
        return window.NativeBridge.redp2p.redp2p_set_stream_faults(context, 7, 11);
    }).then(function (result) {
        if (result !== 0) {
            throw new Error('typed scalar arguments were rejected');
        }
        return window.NativeBridge.redp2p.redp2p_version();
    }).then(function (version) {
        return window.NativeBridge.redp2p.redp2p_close(context).then(function (result) {
            if (result !== 0) {
                throw new Error('typed handle release was rejected');
            }
            return version;
        });
    }).then(function (version) {
        output.textContent = version > 0
            ? 'redp2p version: ' + version + '\nNativeBridge loaded successfully.'
            : 'NativeBridge error: unavailable';
    }).catch(function (error) {
        output.textContent = 'NativeBridge error: ' + error.message;
    });
})();
