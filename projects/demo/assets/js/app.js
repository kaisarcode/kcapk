/**
 * redp2p demo app script.
 * Summary: Verifies generated libabi-based redp2p dispatch.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');

    KcSplash.onToken(function (token) {
        var response = NativeBridge.callNative(token, 'redp2p', 'redp2p_version', '[]');
        var result;

        try {
            result = JSON.parse(response);
        } catch (error) {
            result = { error: 'invalid native response' };
        }
        output.textContent = result.result > 0
            ? 'redp2p version: ' + result.result + '\nNativeBridge loaded successfully.'
            : 'NativeBridge error: ' + (result.error || 'unavailable');
    });
})();
