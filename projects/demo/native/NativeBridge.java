package com.kaisarcode.demo;

import android.content.Context;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

/**
 * Exposes the small redp2p surface used by the demo application.
 * @return None.
 */
public final class NativeBridge {
    static {
        System.loadLibrary("projectbridge");
    }

    private final JSBridge jsBridge;

    /**
     * Stores the origin gate shared with AndroidBridge.
     * @param context Application context.
     * @param webView Application WebView.
     * @param jsBridge Common origin gate.
     * @return None.
     */
    public NativeBridge(Context context, WebView webView, JSBridge jsBridge) {
        this.jsBridge = jsBridge;
    }

    /**
     * Returns the linked redp2p build version to trusted application code.
     * The caller must present the bridge capability token that Android
     * injects only into trusted main-frame content, so untrusted subframes
     * cannot obtain bridge authority.
     * @param token Bridge capability token.
     * @return Build timestamp, or zero for an untrusted caller.
     */
    @JavascriptInterface
    public long redp2pVersion(String token) {
        if (!jsBridge.isTrustedCall(token)) {
            return 0;
        }
        return nativeRedp2pVersion();
    }

    /**
     * Reads the linked redp2p build version from the project JNI library.
     * @return Build timestamp from libredp2p.
     */
    private static native long nativeRedp2pVersion();
}
