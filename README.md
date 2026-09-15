# kcapk

`kcapk` is a small manifest-driven Android application builder.

It keeps one general Android build path while allowing each project to define
its own frontend and, when needed, its own native integration.

The builder is a single POSIX shell script. No Gradle or Android Studio project
is required for the normal build flow.

## Effective architecture

- `window.NativeBridge` is the single public bridge root.
- Android host capabilities are available under `window.NativeBridge.<method>`.
- config-selected kclibs are optional build-time dependencies exposed under `window.NativeBridge.KcLib.<kclib>`.
- Native `.so` files ship with the APK/AAB and are not runtime-updated.
- Web assets may continue to update independently.
- Project JNI/native integration belongs in `projects/NAME/native/`.

## Layout

```text
kcapk/
|-- scripts/
|   |-- build.sh
|   |-- install.sh
|   `-- uninstall.sh
|-- repo/
|   |-- build.sh
|   |-- assets/
|   `-- projects/NAME/
|       |-- config.json
|       |-- assets/
|       |-- native/          # project-specific native integration when present
|       `-- app/             # generated build tree; do not edit
`-- dist/
    `-- NAME/
        |-- manifest.json
        |-- NAME.apk
        `-- www/
```

## Build

From `repo/`:

```sh
./build.sh NAME
```

Thin operator helpers are available under `scripts/`.

The general builder remains responsible for Android mechanics such as:

- SDK/build-tool setup;
- generated Android project files;
- resources and icons;
- WebView shell;
- shared NativeBridge host and generated kclib bridge support;
- web asset staging/provisioning;
- project-native compilation;
- APK/AAB packaging;
- signing;
- publication.

## Project contract

A project has a small declarative contract in `projects/NAME/config.json`.
It is developer-authored source configuration. By contrast,
`dist/NAME/manifest.json` is generated release metadata and must not be edited
as source configuration.

Example `config.json`:

```json
{
  "display_name": "Demo",
  "package_name": "com.kaisarcode.demo",
  "icon": "icon.png",
  "icon_background": "#222222",
  "trusted_origins": ["file:///"],
  "fullscreen": true,
  "version_code": 1,
  "version_name": "0.1.0",
  "app_manifest_url": "https://kaisarcode.com/kcapk/dist/demo/manifest.json",
  "kclib": ["redp2p"],
  "start": "www/index.html"
}
```

`start` selects the application start document.

`kclib` selects the application kclibs. Selected kclibs are automatically
available through the generated `window.NativeBridge.KcLib.<kclib>` namespace.

## Kclib dependency model

The native dependency set is exactly the `NAME` entries in
`config.json:kclib`. The builder resolves each canonical distribution package under:

```text
KCLIB_DIST_DIR/NAME.c/
```

The canonical Android inputs are:

```text
KCLIB_DIST_DIR/NAME.c/aarch64/android/libNAME.so
KCLIB_DIST_DIR/NAME.c/aarch64/android/libNAME.h
KCLIB_DIST_DIR/NAME.c/armv7/android/libNAME.so
KCLIB_DIST_DIR/NAME.c/armv7/android/libNAME.h
```

Each target directory supplies the precompiled library together with its public
header. The builder discovers public declarations with the NDK Clang AST,
generates typed C calls against the distributed header, links the common bridge
against the selected precompiled libraries, and packages the native libraries.
Kclib implementation C sources are not required or rebuilt. Every APK/AAB
contains only the config-selected `libNAME.so` files in addition to the
common bridge.

Projects should not manually copy kclib headers or `.so` files when the builder
can derive them from the canonical distribution.

## Native release model

Native libraries are part of the APK/AAB release.

They are not intended to update independently at runtime.

If a native dependency changes incompatibly, rebuild the affected application
with matching headers and `.so` files.

## NativeBridge

`window.NativeBridge` is the single public root native bridge object.

Android host capabilities are native services provided by the Android host and
are exposed under:

```js
window.NativeBridge.<method>()
```

Generated kclib APIs for config-selected kclibs are exposed under the `KcLib`
namespace as:

```js
window.NativeBridge.KcLib.<kclib>.<exact_C_function_name>()
```

The generated facade builds a single `window.NativeBridge` object that carries
both the Android host methods and the `KcLib` kclib namespaces. Host methods
forward to an internal, hidden host transport that supplies the capability
token itself, so application code never supplies or sees it. Neither path
replaces the other.

The generated bridge is produced by `build.sh`. It maintains the existing
trusted WebView capability gate and exposes only config-selected functions
discovered from their real public header trees. Generated native code invokes
those typed C declarations and links directly to the selected packaged
libraries. It never accepts paths or arbitrary process symbols from application
JavaScript.

Conceptually:

```text
WebView / JavaScript
    |
    +-- window.NativeBridge
          |
          +-- <host method>            direct Android host capabilities
          |
          +-- KcLib.<kclib>.<function> generated kclib APIs
                  |
                  +-- generated Java facade
                          |
                          +-- internal trusted transport
                                  |
                                  +-- typed calls compiled from libNAME.h
                                  +-- selected precompiled libNAME.so
```

Application code calls the bridge directly, for example:

```js
window.NativeBridge.showToast(...)
window.NativeBridge.KcLib.redp2p.redp2p_version()
window.NativeBridge.KcLib.redp2p.redp2p_is_valid_id("demo")
```

The facade owns tokens, JSON transport, JNI dispatch, and library lookup.
Those details are not application APIs. A public declaration that cannot be
represented safely causes the build to fail with its library, function, and
unsupported type.

## Web assets

Web assets remain separate from native dependencies.

The existing provisioning model may continue to provide:

- embedded first-run assets;
- remote web asset updates;
- SHA-256 verification;
- offline fallback;
- splash progress and warnings.

Native `.so` files must not use the same independent runtime update mechanism.

## Generated tree

`projects/NAME/app/` is generated by the builder.

Do not edit it by hand.

Changes to generated Java, JNI dispatch, AndroidManifest.xml, native packaging,
or other generated behavior belong in `repo/build.sh`.

## Development rule

Automate deterministic build mechanics.

If behavior can be derived reliably from `config.json` and the canonical
kclib dist layout, it belongs in the builder.

`projects/NAME/native/bridge.c` remains available for project-specific native
behavior, but ordinary selected kclib calls belong to the generated bridge.
