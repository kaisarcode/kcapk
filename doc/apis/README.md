# NativeBridge Android API reference

This directory contains the detailed reference for APIs exposed under `NativeBridge.Android`.

Only `showToast()` is part of the always-present core. Every other capability is opt-in with repeatable `--api` build options.

## Available APIs

| API | Activation | JavaScript surface |
|---|---|---|
| [Core](core.md) | always enabled | `NativeBridge.Android.showToast()` |
| [Network](network.md) | `--api network` | `NativeBridge.Android.isOnline()` |
| [Permissions](permissions.md) | `--api permissions` | `NativeBridge.Android.permissions.*` |
| [Notifications](notifications.md) | `--api notifications` | `NativeBridge.Android.notifications.*` |
| [Alarms](alarms.md) | `--api alarms` | `NativeBridge.Android.alarms.*` |
| [Haptics](haptics.md) | `--api haptics` | `NativeBridge.Android.haptics.*` |
| [Intents](intents.md) | `--api intents` | `NativeBridge.Android.intents.*` |
| [Files](files.md) | `--api files` | `NativeBridge.Android.files.*` |
| [Apps and launcher](apps.md) | `--api apps` | `NativeBridge.Android.apps.*` |
| [Resources](resources.md) | `--api resources` | `NativeBridge.Android.resources.*` |
| [System UI](system-ui.md) | `--api system-ui` | `NativeBridge.Android.systemUI.*` |
| [Clipboard](clipboard.md) | `--api clipboard` | `NativeBridge.Android.clipboard.*` |
| [Voice](voice.md) | `--api voice` | `NativeBridge.Android.voice.*` |
| [Screen](screen.md) | `--api screen` | `NativeBridge.Android.screen.*` |

## Activation model

Example:

```sh
./build.sh \
    --api permissions \
    --api notifications \
    --api clipboard \
    --permission notifications \
    --webview-url ./web/index.html
```

API selection and Android permission declaration are separate. `--api` determines which native bridge surface is compiled into the generated app. `--permission` determines which optional Android permissions are declared in its Manifest.

Disabled APIs are omitted from generated Java sources and from the JavaScript bridge wrapper. Their API-specific Manifest components are also omitted.

Internal dependencies are selected automatically and do not expose extra public namespaces.

## Common rules

All APIs are available only to trusted top-level WebView content. See [WebView and trusted origins](../WEBVIEW.md).

Methods are synchronous unless their page explicitly says they return a Promise. Promise behavior, page-generation protection, and common error codes are documented in [Async operations](../ASYNC.md).

`NativeBridge.exec()` is outside this directory because it is a KCAPK executable facility rather than an Android namespace. See [External binaries](../EXTERNAL_BINARIES.md).

## Documentation convention

Every API page documents:

- build-time activation,
- JavaScript namespace and methods,
- Android permissions or Manifest behavior,
- synchronous/asynchronous behavior,
- lifecycle or version-specific constraints,
- practical examples.

When a new public Android API is added to KCAPK, it should also receive a page in this directory.
