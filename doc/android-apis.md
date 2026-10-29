# Android APIs

KCAPK exposes Android capabilities under `NativeBridge.Android`.

The bridge is intentionally selective. Only the small core is included by default; optional APIs are added at build time with repeatable `--api` options. This keeps generated APKs smaller and reduces the native surface exposed to trusted WebView content.

## Core API

The core API is always available and does not require `--api`:

```js
NativeBridge.Android.showToast("Hello");
```

See [Core](apis/core.md).

## Enabling optional APIs

Enable only the capabilities an application needs:

```sh
./build.sh \
    --api notifications \
    --api alarms \
    --api clipboard \
    --webview-url ./web/index.html
```

`--api` is repeatable. APIs that are not enabled are omitted from the generated Java sources and from the JavaScript `NativeBridge` wrapper. API-specific Manifest entries are also omitted when they are not needed.

Permissions remain separate from API selection. For example:

```sh
./build.sh \
    --api notifications \
    --api permissions \
    --permission notifications
```

`--api notifications` includes the notification API. `--permission notifications` declares `POST_NOTIFICATIONS`. `--api permissions` includes the runtime permission-request API.

`NativeBridge.exec()` is not an Android API selection. It is included automatically only when at least one executable is packaged with `--exec`.

## API catalog

| Build option | JavaScript API | Default | Notes |
|---|---|---|---|
| `--api alarms` | `NativeBridge.Android.alarms.*` | no | Native alarms, persistence, boot restore. |
| `--api apps` | `NativeBridge.Android.apps.*` | no | Launcher app discovery, launching, Home role. |
| `--api clipboard` | `NativeBridge.Android.clipboard.*` | no | Clipboard read/write operations. |
| core | `NativeBridge.Android.showToast()` | yes | Minimal always-present bridge. |
| `--api files` | `NativeBridge.Android.files.*` | no | Android document picker. |
| `--api haptics` | `NativeBridge.Android.haptics.*` | no | Vibration and predefined haptic effects. |
| `--api intents` | `NativeBridge.Android.intents.*` | no | Sharing, URL/settings intents, incoming shares. |
| `--api network` | `NativeBridge.Android.isOnline()` | no | Adds network-state inspection. |
| `--api notifications` | `NativeBridge.Android.notifications.*` | no | Notification channels and posting. |
| `--api permissions` | `NativeBridge.Android.permissions.*` | no | Runtime permission and special-access flows. |
| `--api resources` | `NativeBridge.Android.resources.*` | no | Generic Android resource metadata. |
| `--api screen` | `NativeBridge.Android.screen.*` | no | Keep-screen-on behavior. |
| `--api system-ui` | `NativeBridge.Android.systemUI.*` | no | System-bar appearance and visibility. |
| `--api voice` | `NativeBridge.Android.voice.*` | no | System speech-to-text via the device recognizer. |

## Internal dependencies

An API may require internal support code without exposing another public namespace. For example, async APIs share `AsyncBridge`, and alarms use notification internals to deliver their current native notification action.

Internal dependencies are selected automatically. Applications only choose public capabilities with `--api`.

## Async APIs

Operations that wait for Android work or user interaction use the shared Promise layer. Current examples include permissions, file selection, voice recognition, launcher app discovery, app icon lookup, and resource lookup.

See [Async operations](async.md) for request IDs, page generations, lifecycle behavior, and the common error model.

## Security boundary

API selection is separate from trusted-origin enforcement. An enabled API is still callable only from WebView content KCAPK considers trusted.

See [WebView and trusted origins](webview.md) and [NativeBridge](native-bridge.md).

## Adding APIs

An app may supply isolated native extensions using `--extension` without altering KCAPK templates. App-specific bridge calls are not automatically part of the public `NativeBridge.Android` catalog; general-use features such as voice belong here as opt-in APIs.

New Android integrations should remain general-purpose, live under `NativeBridge.Android`, use a dedicated bridge class when non-trivial, and be opt-in unless they belong to the deliberately small core.

Every new public API should also receive a page under `doc/apis/` documenting activation, methods, permissions, async behavior, examples, and Android-specific constraints.

## Detailed reference

[Detailed Android API reference](apis/readme.md) - one page per optional Android capability with activation, usage, permissions, and platform behavior.

## Next step

Continue with [readme](apis/readme.md).
