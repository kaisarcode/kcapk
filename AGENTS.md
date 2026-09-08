# kcapk

## Purpose

kcapk is one general Android application builder. It generates the Android
shell, compiles declared native dependencies, packages releases, and preserves
an explicit project boundary for application semantics.

## Architecture

AndroidBridge is common kcapk infrastructure for Android-specific features.

NativeBridge is project-specific. A project defines its own Java and JNI
surface under `projects/PROJECT/native/`; it exposes only the operations that
project intentionally supports.

There is no generic native runner, reflection-based dispatch, dynamic native
symbol dispatcher, or common kclib ABI. Declaring a dependency does not expose
it automatically to JavaScript.

## Project contract

Each project provides `config.json`, `manifest.json`, and `assets/`.

`manifest.json:kclib` declares build-time kclib dependencies only. For a
declared `NAME`, `build.sh` resolves these canonical distribution inputs:

```text
KCLIB_DIST_DIR/NAME.c/source.zip
KCLIB_DIST_DIR/NAME.c/aarch64/android/libNAME.so
KCLIB_DIST_DIR/NAME.c/armv7/android/libNAME.so
```

`source.zip` is extracted only into build staging to provide headers. The
public header convention is `src/libNAME.h`.

## Native packaging

Project JNI and native code live under `projects/PROJECT/native/`. Their
meaning and API belong to that project, while `build.sh` supplies deterministic
compilation and packaging mechanics.

The compiled project bridge and declared dependency `.so` files ship in the
APK/AAB native library directories. They are never runtime-updated. An
incompatible native API or ABI change requires rebuilding the affected app.

## Web assets

Web asset provisioning is separate from native packaging. It may keep using
the existing embedded-first, remote-update mechanism where configured.

## Generated output

`projects/PROJECT/app/` is builder output and must not be hand-edited. The
builder owns its generated Java source set and regenerates it deterministically
on every build. Do not edit generated files to change application behavior.

Put deterministic build mechanics in `build.sh`. Keep semantic application
integration explicit in project-owned source files.

## Validation

Run builds from `repo/` with:

```sh
./build.sh NAME
```

Do not run broad clean operations or delete generated artifacts unless the
task explicitly requires a narrow, builder-owned cleanup.
