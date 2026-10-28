# Testing

KCAPK includes an integration test that builds generated Android applications and validates key packaging, API-selection, and bridge behavior.

## Run the test

From the repository root:

```sh
sh ./tests/test.sh
```

The generated full-feature test APK is written to:

```text
tests/test.apk
```

Temporary generated Android projects are created outside `tests/` and removed after the test completes.

## What the host-side test validates

The script performs two builds.

The full-feature build explicitly enables every optional `NativeBridge.Android` API. It validates that KCAPK can:

- generate the selected Java bridge classes and JavaScript namespaces,
- include shared Promise infrastructure for asynchronous capabilities,
- forward permission, activity-result, and incoming-intent lifecycle events when required,
- include API-specific Manifest permissions and components,
- include requested optional Android permissions,
- include incoming share filters,
- include launcher/Home integration,
- package external executables for multiple ABIs,
- produce the final APK.

The script verifies that asynchronous APIs such as `NativeBridge.exec()`, permission requests, file selection, app discovery, icon-resource lookup, and Android resource lookup are wired through the shared request layer.

The second build uses no `--api` and no `--exec`. It validates the opposite side of the selection model:

- core `NativeBridge.Android.showToast()` remains available,
- optional JavaScript namespaces are absent,
- optional bridge classes and `AsyncBridge` are not generated,
- `NativeBridge.exec()` is absent,
- network, boot, and vibration permissions are not added automatically,
- alarm receivers, incoming-share filters, and the Home activity alias are absent.

This core-only build guards against regressions that would silently reintroduce native surface or APK bloat.

## Native executable fixtures

The repository includes the same logical test executable for multiple Android ABIs under:

```text
tests/fixtures/
```

The fixture source is kept in:

```text
tests/fixtures/exec.c
```

The integration test does not compile that C source. Prebuilt Android fixtures are included so running the test does not require an Android NDK or C compiler.

The full build packages them through `--exec` and verifies the resulting APK entries.

See [External binaries](EXTERNAL_BINARIES.md) for the integration model.

## Test application

`tests/index.html` is a small WebView application designed to exercise the fully enabled bridge on a real Android device.

Its controls cover:

- asynchronous packaged executable execution,
- concurrent executable requests with `Promise.all`,
- Android notification permission results,
- network-state queries,
- vibration and haptics,
- clipboard round trips,
- document picking and file sharing,
- incoming Android shares,
- launcher-app discovery and launching,
- Home launcher candidacy/settings,
- keep-screen-on behavior,
- native speech recognition and Web Speech microphone permission,
- HTML file input via Android's document picker,
- direct packaged HTTPS asset startup,
- app-specific native extension bridge.

Interactive results are surfaced with Android toasts.

## Install the generated test APK

After a successful test build:

```sh
adb install -r -t tests/test.apk
```

The test script also prints the corresponding install command.

## Manual validation

A successful host-side build proves that generated source compiles and the APK packages correctly, but device behavior still needs manual validation for Android features that depend on runtime services, permissions, lifecycle, system settings, or hardware.

The async layer should be manually checked for:

- `await NativeBridge.exec()` resolving with executable output,
- parallel executable requests resolving independently,
- notification permission requests resolving only after Android returns a result,
- file picker cancellation and selection,
- page navigation not receiving stale native completions,
- pending native processes being cleaned up when the Activity is destroyed.

Other device-dependent checks include vibration hardware, exact-alarm special access, Sharesheet behavior, launcher/Home behavior, and system bars across Android versions.

When adding a NativeBridge Android API, update its `doc/apis/` reference page and add both positive selection and pruning coverage when practical.

The full integration APK enables `--api voice`, `--local-https-assets` and
`--extension tests/extension`. Use the **Native voice**, **Web Speech**,
**HTML file input**, **Secure local assets**, and **Native extension** buttons
on a device. The native-extension button shows a Java-generated toast with a call counter; the HTTPS button confirms that the initial page was loaded directly through KCAPK's secure local origin. Voice recognition may need a speech service and network connection.

## Next step

- [Advanced documentation](advanced/index.md) - explore the architecture and integration guides.
- [Project README](../README.md) - return to the main documentation.
