# Configuration

KCAPK can be configured with command-line options or environment variables.

Command-line values take precedence over environment variables, which take precedence over built-in defaults.

```text
command-line option > environment variable > built-in default
```

## Command-line options

| Option | Description |
|---|---|
| --display-name <name> | Application display name. |
| --project-name <name> | Project name and default build directory name. |
| --output-path <path> | Generated project/build directory. |
| --package-name <name> | Android package name. |
| --webview-url <url|file> | Remote URL or local HTML entry file. |
| --icon <path|url> | Local or remote icon source. |
| --icon-background <color> | Adaptive launcher icon background. |
| --background <color> | Activity, WebView, and system-bar startup background. |
| --trusted-origin <origin> | Additional trusted bridge origin; repeatable. |
| --api <name> | Include one optional NativeBridge Android API; repeatable. |
| --permission <name> | Declare an optional Android permission; repeatable. |
| --share-target <mime> | Accept incoming Android shares for a MIME type; repeatable. Requires --api intents. |
| --fullscreen | Enable fullscreen mode. |
| --local-https-assets | Enable the packaged HTTPS asset origin for secure WebView APIs. |
| --extension <dir> | Compose application-owned native Java, resources and manifest declarations; repeatable. |
| --version-code <N> | Android version code. |
| --version-name <name> | Android version name. |
| --exec <path> | Package one native executable; repeatable. |
| --clean | Regenerate the debug keystore. |
| --release | Build the debug APK and an AAB. |

## Main environment variables

```sh
DISPLAY_NAME="My App"
PROJECT_NAME="myapp"
OUTPUT_PATH="./build/myapp"
PACKAGE_NAME="com.example.myapp"
WEBVIEW_URL="./web/index.html"
ICON_SOURCE_FILE="./src/assets/icon.svg"
ICON_BACKGROUND="#000000"
BACKGROUND="#101010"
TRUSTED_ORIGINS=""
IS_FULLSCREEN="false"
LOCAL_HTTPS_ASSETS="false"
VERSION_CODE=1
VERSION_NAME="1.0"
```

When `OUTPUT_PATH` is empty, KCAPK uses:

```text
./build/<project-name>
```

## Display and package names

`DISPLAY_NAME` / `--display-name` controls the user-visible application name.

`PROJECT_NAME` / `--project-name` controls generated artifact names and the default build directory.

`PACKAGE_NAME` / `--package-name` controls the Android package identifier.

Example:

```sh
./build.sh \
    --display-name "Notes" \
    --project-name notes \
    --package-name com.example.notes
```

## Background

The default startup background is:

```text
#101010
```

Accepted values are:

```text
#RRGGBB
#AARRGGBB
```

Example:

```sh
./build.sh --background '#202020'
```

The value is applied to the generated Activity window, WebView, and system-bar startup surfaces.

## Icons

The bundled default icon lives at:

```text
src/assets/icon.svg
```

A custom icon may be local or remote:

```sh
./build.sh --icon ./assets/icon.svg
```

```sh
./build.sh --icon https://example.com/icon.png
```

KCAPK generates raster launcher assets for the standard Android densities and adaptive launcher icon assets for modern Android versions.

`--icon-background` / `ICON_BACKGROUND` sets the adaptive icon background color.

## Fullscreen

```sh
./build.sh --fullscreen
```

The generated Activity starts in fullscreen mode. Runtime system-bar control is available only when the app is also built with `--api system-ui`; see [System UI](apis/system-ui.md).

## Trusted origins

Remote bridge access can be extended with repeated options:

```sh
./build.sh \
    --webview-url https://app.example.com \
    --trusted-origin https://app.example.com \
    --trusted-origin https://cdn.example.com
```

`--trusted-origin` is repeatable.

The `TRUSTED_ORIGINS` environment variable remains available as a whitespace-separated fallback.

See [WebView and trusted origins](WEBVIEW.md) for the trust model.

## NativeBridge API selection

Only the core bridge is included by default. Core currently exposes:

```js
NativeBridge.Android.showToast(...)
```

Optional Android APIs are added with repeatable `--api` options:

```sh
./build.sh \
    --api network \
    --api notifications \
    --api clipboard
```

Supported API names are:

```text
network
permissions
notifications
alarms
haptics
intents
files
apps
resources
system-ui
clipboard
screen
voice
```

`systemUI` is also accepted as an alias for `system-ui`, but `system-ui` is the canonical command-line spelling.

Disabled APIs are removed from the generated Java sources and from the generated JavaScript NativeBridge wrapper. Their API-specific Manifest entries are omitted as well.

Internal dependencies are resolved automatically. For example, alarms include the native notification implementation needed by the alarm receiver without exposing the public notifications namespace unless `--api notifications` was also requested.

`NativeBridge.exec()` is separate from Android API selection and is generated automatically when at least one `--exec` binary is packaged.

Native system speech recognition is enabled with `--api voice` and does not automatically grant browser microphone permission. Browser Web Speech additionally requires WebView support and an explicit Android microphone grant.

See [Android APIs](ANDROID_APIS.md) for the catalog and [API reference](apis/README.md) for detailed pages.

## Android permissions

API selection and Android permission declaration are independent.

Optional permissions are declared at build time with repeatable `--permission` options:

```sh
./build.sh \
    --api permissions \
    --permission notifications \
    --permission camera \
    --permission locationCoarse
```

Supported aliases include:

```text
notifications
exactAlarm
exactAlarms
camera
microphone
location
locationFine
locationCoarse
```

KCAPK also accepts explicit Android permission names:

```sh
./build.sh --permission android.permission.RECORD_AUDIO
```

Aliases are resolved to `<uses-permission>` entries in the generated `AndroidManifest.xml`. Duplicate permissions are emitted only once.

`android.permission.INTERNET` remains part of the base application because KCAPK supports remote WebView content.

Some APIs add the normal permissions required by their own implementation automatically:

```text
--api network   -> android.permission.ACCESS_NETWORK_STATE
--api alarms    -> android.permission.RECEIVE_BOOT_COMPLETED
--api haptics   -> android.permission.VIBRATE
```

Sensitive or optional permissions such as `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, camera, microphone, and location are not added merely because a related API is present. Declare them explicitly with `--permission` when the application needs them.

Runtime permission requests require `--api permissions`. For example:

```js
var granted = await NativeBridge.Android.permissions.request("camera");
```

requires both the permissions API and a Manifest declaration:

```sh
--api permissions \
--permission camera
```

If a permission is not declared, the Promise rejects with `PERMISSION_NOT_DECLARED` on Android versions where that permission is required.

See [Permissions](apis/permissions.md).

## Incoming shares

Incoming Android Sharesheet support requires the intents API plus repeatable `--share-target` options:

```sh
./build.sh \
    --api intents \
    --share-target 'image/*' \
    --share-target 'application/pdf'
```

KCAPK adds `ACTION_SEND` and `ACTION_SEND_MULTIPLE` intent filters for those MIME types to the generated activity.

A universal receiver can be built with:

```sh
./build.sh \
    --api intents \
    --share-target '*/*'
```

Android supports `*/*`, but it should normally be reserved for applications that intentionally accept arbitrary content. KCAPK's test application uses it to validate generic incoming file shares.

Receiving a share does not require a storage permission by itself. Android delivers shared files as `content://` URIs and grants the receiving activity access through the incoming intent. KCAPK does not read file contents when receiving a share; it only captures the URI and metadata such as display name, MIME type, and size.

Application code can consume the pending share with:

```js
var share = NativeBridge.Android.intents.consumeShare();
```

See [Intents](apis/intents.md).

## Native executables

`--exec` can be repeated to package native binaries:

```sh
./build.sh \
    --exec /path/to/arm64-v8a/tool \
    --exec /path/to/x86_64/tool
```

See [External binaries](EXTERNAL_BINARIES.md).

## Release settings

Release signing uses these environment variables:

```sh
RELEASE_KEYSTORE
RELEASE_KEY_ALIAS
RELEASE_STORE_PASS
RELEASE_KEY_PASS
```

See [Release builds](RELEASES.md).

## Next step

Continue with [WebView and trusted origins](WEBVIEW.md).

## Native application extensions

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
This flag does not change the initial startup URL and does not fetch a server.
The application may navigate from a packaged `file://` page to the local HTTPS
origin, for example when preserving legacy IndexedDB data during a migration.

See [WebView](WEBVIEW.md) and [Voice](apis/voice.md).
