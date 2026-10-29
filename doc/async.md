# Async operations

KCAPK uses one Promise-based request layer for native operations whose result is not available immediately.

The async infrastructure is generated only when the selected build needs it: `--exec`, `--api permissions`, `--api files`, `--api apps`, or `--api resources`. A core-only build does not include `AsyncBridge`.

The public API does not expose request IDs or callback objects. Application code uses normal JavaScript Promises when the corresponding capability is enabled:

```js
var output = await NativeBridge.exec(["mytool", "status"]);
var granted = await NativeBridge.Android.permissions.request("notifications");
var file = await NativeBridge.Android.files.open({ type: "*/*" });
var apps = await NativeBridge.Android.apps.list();
var icon = await NativeBridge.Android.apps.icon(
    apps[0].packageName,
    apps[0].activityName
);
var resource = await NativeBridge.Android.resources.describe(
    icon.packageName,
    icon.resourceId
);
```

## Which methods are async

An operation is asynchronous when it must wait for native work, Android lifecycle callbacks, or user interaction.

Current asynchronous operations are:

```text
NativeBridge.exec(...)
NativeBridge.Android.permissions.request(...)
NativeBridge.Android.files.open(...)
NativeBridge.Android.apps.list()
NativeBridge.Android.apps.icon(...)
NativeBridge.Android.resources.describe(...)
```

`NativeBridge.exec()` exists only when at least one `--exec` is packaged. Android async APIs exist only when their corresponding `--api` is selected.

Immediate operations remain synchronous. KCAPK does not create duplicate `foo()` / `fooAsync()` APIs.

## Request flow

Each Promise receives an internal request ID and the generation of the current top-level WebView page.

Conceptually:

```text
JavaScript Promise
    -> AndroidBridge request
    -> native worker / Android system flow
    -> native result
    -> WebView.evaluateJavascript()
    -> Promise resolve or reject
```

The request IDs are internal implementation details and are not part of the public API.

## Page generations

Each top-level page load receives a new generation number when async infrastructure is present.

A native request belongs to the page generation that created it. If navigation starts before the request completes, KCAPK drops the stale native result rather than delivering it into a different page.

The JavaScript wrapper also rejects pending requests with:

```text
PAGE_CHANGED
```

when it observes a generation change while the old document is still alive.

This prevents a delayed permission result, file picker result, app/resource result, or native process result from resolving a Promise in unrelated content after navigation.

## Native completion

The native side completes requests through a private bridge callback. It is not intended for application code.

Successful requests resolve with the operation result.

Failed requests reject with a JavaScript `Error` containing at least:

```js
error.code
error.message
```

Operation-specific fields may also be included.

For example, a failed native executable can expose:

```js
error.code === "EXEC_FAILED"
error.exitCode
error.output
```

## Common error codes

The current infrastructure uses codes such as:

```text
BRIDGE_NOT_READY
BRIDGE_UNAVAILABLE
BRIDGE_DESTROYED
NATIVE_START_FAILED
INVALID_NATIVE_RESPONSE
INVALID_ARGUMENT
ACTIVITY_UNAVAILABLE
PERMISSION_NOT_DECLARED
PERMISSION_REQUEST_FAILED
FILE_RESULT_FAILED
APP_LIST_FAILED
APP_NOT_FOUND
APP_ICON_FAILED
PACKAGE_NOT_FOUND
RESOURCE_NOT_FOUND
RESOURCE_LOOKUP_FAILED
BUSY
EXEC_NOT_EXPOSED
EXEC_FAILED
CANCELLED
PAGE_CHANGED
INTERNAL_ERROR
```

Additional APIs may define more specific codes while keeping the same Promise error shape.

## External executables

`NativeBridge.exec()` always returns a Promise when executables are packaged.

Native processes run outside the JavaScript bridge thread in a bounded worker pool, so JavaScript does not wait inside the synchronous `addJavascriptInterface` call while the process executes.

Multiple executions can be pending concurrently:

```js
var results = await Promise.all([
    NativeBridge.exec(["tool-a"]),
    NativeBridge.exec(["tool-b"])
]);
```

When the WebView moves to another page, running processes belonging to older page generations are terminated when possible.

When the Activity is destroyed, KCAPK destroys active processes and shuts down the executor.

See [External binaries](external-binaries.md) for the complete executable integration model.

## Permissions

The runtime permissions API requires:

```sh
--api permissions
```

Permission declaration and permission granting remain separate operations.

Build-time declaration uses repeatable `--permission` options:

```sh
./build.sh \
    --api permissions \
    --permission camera
```

Runtime access then uses:

```js
var granted = await NativeBridge.Android.permissions.request("camera");
```

If Android requires the permission but it was not declared in the generated Manifest, the Promise rejects with `PERMISSION_NOT_DECLARED`.

When declared, the Promise resolves to the effective permission state:

```text
true  -> granted / available
false -> denied / unavailable after the user flow
```

Runtime permissions resolve from Android's permission-result callback.

Special access such as exact alarms is checked again when the Activity resumes after returning from Android Settings.

Only one runtime permission dialog and one exact-alarm settings request may be active at a time. A conflicting request rejects with `BUSY`.

See [Permissions](apis/permissions.md).

## File picker

With `--api files`, `NativeBridge.Android.files.open()` uses Android's document picker and resolves through the shared activity-result registry:

```js
var file = await NativeBridge.Android.files.open({ type: "image/*" });
```

The Promise resolves with `null` when the user cancels. Otherwise it resolves with a descriptor containing the selected `content://` URI and available metadata such as name, MIME type, and size.

KCAPK does not read or copy the selected file as part of the picker operation.

See [Files](apis/files.md).

## Launcher app data and resources

With `--api apps`, launcher discovery and icon-resource identity are asynchronous:

```js
var apps = await NativeBridge.Android.apps.list();
var icon = await NativeBridge.Android.apps.icon(
    apps[0].packageName,
    apps[0].activityName
);
```

Icons are deliberately excluded from the list. `apps.icon()` returns package/activity/resource identity only.

With `--api resources`, generic Android resource metadata is handled independently:

```js
var resource = await NativeBridge.Android.resources.describe(
    icon.packageName,
    icon.resourceId
);
```

The resources API does not rasterize, decode, copy, or otherwise interpret the resource.

See [Apps and launcher](apis/apps.md) and [Resources](apis/resources.md).

## Activity results

When an enabled async feature needs Android activity results, `MainActivity` forwards `onActivityResult()` to the shared registry. The file picker is currently the public API that consumes this mechanism directly.

This keeps future directory selection, camera flows, or other Android activities on the same Promise mechanism rather than adding feature-specific callback conventions.

## UI-thread delivery

Native results are delivered back into the WebView with `evaluateJavascript()` on the Activity UI thread.

The native bridge itself may be called by WebView on a non-UI thread, so operations that interact with Android UI or lifecycle APIs explicitly switch to the Activity thread when required.

## Adding new async APIs

A new async bridge API should:

1. register the request in the shared async layer,
2. start its native operation,
3. keep the request ID and page generation associated with the operation,
4. resolve or reject through the shared completion mechanism,
5. stop or discard stale work when the page changes when practical,
6. participate in build-time dependency selection,
7. document cancellation and lifecycle behavior.

The public API should expose only the natural Promise-returning method, not the internal request machinery.

## Next step

Continue with [extensions](advanced/extensions.md).
