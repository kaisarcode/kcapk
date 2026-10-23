# WebView and trusted origins

KCAPK can load either packaged local content or a remote web application.

## Local content

Pass a local HTML entry file with `--webview-url`:

```sh
./build.sh --webview-url ./web/index.html
```

KCAPK copies the complete containing directory into the generated Android `assets/` directory and changes the startup URL to the corresponding `file:///android_asset/...` URL.

For example:

```text
web/
├── index.html
├── app.js
├── style.css
└── images/
```

Using `web/index.html` packages the entire `web/` directory, so relative references continue to work inside the app.

Packaged local assets are trusted automatically for `NativeBridge` access.

## Secure HTTPS origin for local assets

Pass `--local-https-assets` to serve packaged resources at
`https://appassets.androidplatform.net/<path>` without network access.
This opt-in origin enables browser capabilities restricted to secure contexts.
The starting local `--webview-url` still loads through `file:///android_asset/`;
the app explicitly navigates to the HTTPS page when appropriate. The origin is
added to the trusted NativeBridge set only for that build.

The generated WebChromeClient handles `<input type="file">` with Android's
document picker and evaluates browser microphone permission requests. Audio
capture is granted only when the active WebView page is trusted, its origin
matches the requesting frame and Android has already granted `RECORD_AUDIO`.
Other WebView media requests are denied. Enable `--api permissions` and declare
`--permission microphone` if the app needs to request Android microphone access.

This is separate from `--api voice`, which starts the Android system speech
recognizer through an explicit asynchronous native API. Browser Web Speech
support and network/offline behavior depend on the installed WebView and speech
service.

## Remote content

A remote application can be used directly:

```sh
./build.sh --webview-url https://app.example.com
```

For remote content, KCAPK derives the origin of the configured startup URL and includes it in the bridge trust set.

An origin is matched as:

```text
scheme://host[:port]
```

Path components are not part of the origin.

## Additional trusted origins

Additional origins may be supplied explicitly:

```sh
./build.sh \
    --webview-url https://app.example.com \
    --trusted-origin https://app.example.com \
    --trusted-origin https://cdn.example.com
```

`--trusted-origin` is repeatable.

The environment-variable fallback is:

```sh
TRUSTED_ORIGINS="https://app.example.com https://cdn.example.com"
```

When at least one `--trusted-origin` option is supplied, the command-line list replaces the environment fallback. The startup origin is still included automatically when KCAPK can derive it.

## Bridge installation

`NativeBridge` is installed only while the WebView is displaying a trusted URL.

The generated WebView client updates the native bridge trust state when top-level navigation starts and injects the JavaScript API only for trusted pages.

This means application code should not assume that `NativeBridge` exists on arbitrary external pages.

## External navigation

Top-level navigation outside the trusted set is opened through Android rather than loaded as trusted application content.

This keeps the native bridge from following the user into unrelated websites.

## Security model

`NativeBridge` grants access to native capabilities that normal web content does not have. Trusted origins therefore form a security boundary.

Only origins controlled by the application operator should be added to the trusted list.

Avoid trusting a broad third-party origin simply because the application embeds resources from it. If remote third-party content only needs to provide scripts, media, or other resources, it generally does not need top-level bridge access.

## JavaScript APIs

The bridge is divided into:

```text
NativeBridge.exec(...)
NativeBridge.Android.*
```

See [NativeBridge](NATIVE_BRIDGE.md), [Android APIs](ANDROID_APIS.md), and [External binaries](EXTERNAL_BINARIES.md).

## Next step

Continue with [NativeBridge](NATIVE_BRIDGE.md).
