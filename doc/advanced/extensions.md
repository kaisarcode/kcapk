# Native application extensions

KCAPK's `--extension /absolute/path` option composes app-owned Android code
without modifying or duplicating KCAPK's internal templates. Repeat the flag
for independent extension directories. An extension may contain:

```text
java/FeatureBridge.java.in
java/KcapkAppExtension.java.in       # optional lifecycle composition hook
res/raw/feature_sound.mp3
manifest/permissions.xml            # optional uses-permission XML nodes
manifest/components.xml             # optional application children (receiver, metadata...)
```

Java templates use the standard `@PACKAGE_NAME@` variable. KCAPK processes
these files in the normal generator before compiling Java and Android resources.
The only replaceable KCAPK class is `KcapkAppExtension.java.in`; other
internal templates cannot be overwritten by extensions.

The extension hook is constructed with `(Activity, WebView)` and has four
methods: `attach()`, `onActivityResult(requestCode, resultCode, data)`,
`onBackPressed()` and `destroy()`. It can delegate to independently owned
native adapters. The default no-op hook keeps extensions optional. The
extension's `onActivityResult` and `onBackPressed` return `true` when they
consume the operation. KCAPK uses its own normal callbacks otherwise.

`addJavascriptInterface` exposes methods to frames in the WebView. Any
extension bridge must validate the intended application's active page and
expose only narrowly authorized operations. Do not treat merely having a
JavaScript interface as proof of origin authorization.

For local packaged content that needs a browser secure context, enable
`--local-https-assets`. KCAPK serves
`https://appassets.androidplatform.net/<file>` directly from the packaged APK.
When `--webview-url` names a local HTML file, this flag loads that file
directly through the synthetic HTTPS origin. No redirect, staging page, or
network request is necessary. Without the flag, local apps continue loading
from `file:///android_asset/`.

See [WebView](../WEBVIEW.md) and [Voice](../apis/voice.md).

## Next step

- [Architecture](../ARCHITECTURE.md) - understand KCAPK's build and integration boundaries.

