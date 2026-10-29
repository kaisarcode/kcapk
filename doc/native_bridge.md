# NativeBridge

`NativeBridge` is the JavaScript API KCAPK injects into trusted WebView content.

It is intentionally small and explicit. KCAPK does not expose arbitrary Java reflection or the complete Android SDK.

## Public structure

The default build exposes only the core Android bridge:

```text
NativeBridge
└── Android
    └── showToast(...)
```

Optional Android APIs are added with repeatable `--api` options. A fully enabled build can expose:

```text
NativeBridge
├── exec(...)
└── Android
    ├── showToast(...)
    ├── isOnline()
    ├── permissions
    ├── notifications
    ├── alarms
    ├── haptics
    ├── intents
    ├── files
    ├── apps
    ├── resources
    ├── systemUI
    ├── clipboard
    └── screen
```

The separation is deliberate:

- `NativeBridge.exec()` is a KCAPK facility for explicitly packaged native executables and is generated only when `--exec` is used.
- `NativeBridge.Android.showToast()` is part of the always-present core.
- other `NativeBridge.Android.*` capabilities are compiled only when their `--api` option is selected.

Disabled APIs are absent rather than exposed as methods that merely fail. Their dedicated Java bridge classes are also left out of the generated project when they are not needed.

See [Android APIs](android_apis.md) and the detailed [API reference](apis/readme.md).

## Trust boundary

API selection does not replace origin trust checks. The bridge is available only while KCAPK considers the current top-level WebView page trusted.

Packaged local assets are trusted automatically. Remote applications use origin matching and optional `--trusted-origin` entries.

See [WebView and trusted origins](webview.md).

## Synchronous and asynchronous methods

Methods that can produce an immediate result remain synchronous:

```js
NativeBridge.Android.showToast("Saved");
```

When the corresponding APIs are enabled, examples include:

```js
var online = NativeBridge.Android.isOnline();
var value = NativeBridge.Android.clipboard.get();
var opened = NativeBridge.Android.intents.openUrl("https://example.com");
```

Operations that wait for native work or user interaction return Promises:

```js
var granted = await NativeBridge.Android.permissions.request("notifications");
var file = await NativeBridge.Android.files.open({ type: "*/*" });
```

`NativeBridge.exec()` also returns a Promise when external executables are packaged.

KCAPK does not provide separate sync and async variants of the same operation. An operation uses a Promise when its result is inherently deferred.

The Promise/request mechanism, page-generation protection, lifecycle behavior, and common errors are documented in [Async operations](async.md).

## Error model

Synchronous Android bridge methods generally return `false` when an immediate operation cannot be performed and empty strings when a string value is unavailable.

Asynchronous operations reject their Promise with a JavaScript `Error`. KCAPK adds a stable `code` property and may attach operation-specific fields.

Example:

```js
try {
    await NativeBridge.exec(["missing-tool"]);
} catch (error) {
    console.log(error.code);
    console.log(error.message);
}
```

## API selection and permissions

API selection and Android permissions are independent build concerns:

```sh
./build.sh \
    --api permissions \
    --api notifications \
    --permission notifications
```

`--api notifications` includes the notification API. `--api permissions` includes the runtime permission API. `--permission notifications` declares the Android notification permission.

See [Configuration](configuration.md).

## External executables

Packaging native programs, ABI handling, the executable whitelist, and the Promise returned by `NativeBridge.exec()` are documented in [External binaries](external_binaries.md).

## Implementation boundary

The JavaScript wrapper is generated from `src/res/raw/native_bridge.js.in`. Build-time API selection removes namespaces that were not requested.

Java source templates use the same API-selection model, so omitted public APIs do not leave their bridge implementation classes in the generated project unless another selected capability needs one internally.

The shared async infrastructure is included automatically only when selected features require it.

## Next step

- [Android APIs](android_apis.md) - find available application-facing APIs.
