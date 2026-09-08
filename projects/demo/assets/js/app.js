/**
 * redp2p demo app script.
 * Summary: Verifies the project's explicit redp2p NativeBridge mapping.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

(function () {
    'use strict';

    var output = document.getElementById('output');

    KcSplash.onToken(function (token) {
        var version = NativeBridge.redp2pVersion(token);

        output.textContent = version > 0
            ? 'redp2p version: ' + version + '\nNativeBridge loaded successfully.'
            : 'NativeBridge is unavailable from this origin.';
    });
})();
