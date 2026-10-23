# KCAPK

**Android WebView App Builder**

KCAPK builds Android applications directly from the command line, with a focus on WebView-based apps. It generates the Android project, compiles resources and Java sources, creates Dalvik/ART bytecode, signs the APK, and can optionally produce an Android App Bundle for Play Store distribution.

No Android Studio or Gradle project is required.

A KCAPK application can load either packaged local web content or a remote web application. Trusted WebView content can use `NativeBridge` for selected Android capabilities including optional system voice recognition. Applications can compose native Java extensions through `--extension` without patching KCAPK templates, enable a local secure HTTPS asset origin, and package command-line executables for controlled use from JavaScript.

KCAPK currently targets Android SDK 24-36.

## Quick example

Build a packaged local WebView application:

```sh
./build.sh \
    --display-name "My App" \
    --project-name myapp \
    --package-name com.example.myapp \
    --webview-url ./web/index.html
```

The generated APK is written to:

```text
build/myapp/bin/myapp.apk
```

If the WebView entry point is a local file, KCAPK packages its containing directory so adjacent HTML, CSS, JavaScript, images, fonts, and other assets remain available to the application.

For a complete first setup, see [Getting started](doc/GETTING_STARTED.md).

## Architecture

KCAPK is intentionally small. `build.sh` orchestrates the build while reusable Android source templates, resources, and the default icon live under `src/`.

The generated application contains a normal Android Activity with a WebView. KCAPK adds two optional integration layers on top of that:

- `NativeBridge.Android.*` exposes a curated set of useful Android platform capabilities to trusted WebView content. Only the core is present by default; optional capabilities are selected with repeatable `--api` options.
- `NativeBridge.exec()` executes only native binaries explicitly packaged with `--exec`.

These are kept separate deliberately: Android framework integrations are namespaced under `NativeBridge.Android`, while external executables remain a KCAPK capability at the top level.

KCAPK does not try to mirror the complete Android API. The bridge is intended to provide a practical set of general-purpose primitives while application-specific behavior remains in the web application.

## Documentation

- [Getting started](doc/GETTING_STARTED.md) - build and install a first KCAPK application.
- [Architecture](doc/ARCHITECTURE.md) - understand the builder, generated application, templates, and bridge layers.
- [Building](doc/BUILDING.md) - requirements, Android SDK setup, build outputs, and supported targets.
- [Configuration](doc/CONFIGURATION.md) - command-line options, API selection, permissions, icons, backgrounds, and output paths.
- [WebView and trusted origins](doc/WEBVIEW.md) - local and remote content, asset packaging, navigation, and bridge trust boundaries.
- [NativeBridge](doc/NATIVE_BRIDGE.md) - bridge model, namespaces, security boundary, and return conventions.
- [Async operations](doc/ASYNC.md) - Promise-based native requests, page generations, lifecycle, and error handling.
- [Android APIs](doc/ANDROID_APIS.md) - overview and build-time catalog for `NativeBridge.Android.*`.
- [External binaries](doc/EXTERNAL_BINARIES.md) - package native executables with `--exec`, multi-ABI integration, and `NativeBridge.exec()`.
- [Release builds](doc/RELEASES.md) - APK/AAB output and release signing.
- [Testing](doc/TESTING.md) - run the integration test application and validate generated output.

## License

[![LGPLv3](https://www.gnu.org/graphics/lgplv3-147x51.png)](https://www.gnu.org/licenses/lgpl-3.0.html)

KCAPK is distributed under the **GNU Lesser General Public License version 3 (LGPLv3)**.
