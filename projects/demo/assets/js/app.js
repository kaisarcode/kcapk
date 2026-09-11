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

    NativeBridge.redp2p.redp2p_is_valid_id('demo').then(function (valid) {
        if (valid !== 1) {
            throw new Error('typed string parameter was rejected');
        }
        return NativeBridge.redp2p.redp2p_version();
    }).then(function (version) {
        output.textContent = version > 0
            ? 'redp2p version: ' + version + '\nNativeBridge loaded successfully.'
            : 'NativeBridge error: unavailable';
    }).catch(function (error) {
        output.textContent = 'NativeBridge error: ' + error.message;
    });
})();
