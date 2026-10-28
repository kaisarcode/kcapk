# Building

KCAPK builds Android applications with command-line tools only. Android Studio and Gradle are not required.

## Requirements

The host system should provide:

- POSIX shell
- Java JDK 11 or newer
- Android SDK command-line tools, build-tools, and platform files
- ImageMagick `convert`
- `git`
- `curl` or `wget`
- `unzip`
- `zip`
- `file` when using `--exec`

`rsvg-convert` is optional and improves SVG icon rasterization when available.

KCAPK currently uses:

```text
Minimum SDK: 24
Target SDK: 36
Build tools: 36.0.0
Java release: 11
```

## Android SDK location

KCAPK looks for an SDK in this order:

1. `ANDROID_SDK_ROOT`
2. `ANDROID_HOME`
3. `~/android-sdk`

If the required command-line tools are missing, KCAPK downloads the configured Android command-line tools package and installs the required platform and build-tools with `sdkmanager`.

To use an existing SDK:

```sh
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
./build.sh
```

## Build a debug APK

```sh
./build.sh
```

With default settings the generated project is placed under:

```text
build/myapp/
```

and the APK under:

```text
build/myapp/bin/myapp.apk
```

## Generated project

KCAPK does not discard the generated Android project. The output directory contains the rendered manifest, Java sources, resources, packaged web assets, and build output.

A simplified layout is:

```text
build/<project>/
├── AndroidManifest.xml
├── assets/
├── res/
├── src/main/java/
├── temp/
└── bin/
```

Temporary build data is removed at the end of a successful build, while the generated source tree and final artifacts remain.

## Debug signing

Debug APKs are signed with the standard KCAPK debug keystore at:

```text
~/.android/debug.keystore
```

If it does not exist, KCAPK creates it automatically.

`--clean` deletes the existing debug keystore before the build so it will be regenerated.

## Release mode

`--release` keeps the debug APK flow and additionally creates an Android App Bundle.

```sh
./build.sh --release
```

See [Release builds](RELEASES.md) for signing and AAB details.

## Host platform notes

KCAPK is primarily developed and tested on Debian x86_64. The shell script also contains Android command-line tools download handling for macOS.

WSL can be used through a Linux distribution with the same command-line dependencies.

Because the builder intentionally avoids Gradle, compatibility depends directly on the Java and Android command-line tools available on the host.

## Next step

- [Getting started](GETTING_STARTED.md) - build and install your first app.
- [Configuration](CONFIGURATION.md) - customize the generated application.
