# Tests

Build the local KCAPK test application with:

```sh
sh ./tests/test.sh
```

The generated APK is written to:

```text
tests/test.apk
```

The main test build explicitly enables every optional `NativeBridge.Android` API with repeated `--api` options. This exercises the complete generated bridge while keeping normal KCAPK builds opt-in.

The test also packages prebuilt native Android executables through `--exec`. The repository ships the same logical `kcapk-test-exec` fixture for `arm64-v8a` and `x86_64` under `tests/fixtures/`, so running the test does not require an Android NDK or C compiler.

The minimal source used for those fixtures is kept in `tests/fixtures/exec.c` for reference and reproducibility. It is not compiled by `tests/test.sh`.

The full test build declares several optional Android permissions and registers `*/*` as an incoming share target. This makes the test app appear in the Android Sharesheet for arbitrary files. It does not load shared file contents; it only reads metadata and shows a toast such as:

```text
Received shared photo.png
```

After building the full app, the test inspects the APK and generated source and verifies the selected namespaces, bridge classes, Promise infrastructure, permission declarations, incoming share intent filters, launcher integration, result forwarding, and multi-ABI executable entries.

The script then builds a second application with no `--api` and no `--exec`. That core-only build verifies that `showToast()` remains available while optional JavaScript namespaces, native bridge classes, API-specific permissions, alarm receivers, Home registration, share targets, and `NativeBridge.exec()` are absent.

When the full test app runs on a compatible Android device, press **Run packaged executable**. The page invokes:

```js
var output = await NativeBridge.exec(["kcapk-test-exec"]);
```

The bundled fixture resolves with:

```text
kcapk external executable OK
```

The test UI also covers parallel executables, asynchronous permissions, file picking and sharing, launcher-app discovery and launching, and enabling the generated app as an Android Home candidate. The Home alias is disabled by default; **Home settings** opens Android's launcher selection screen after the candidate is enabled.

The Android build workspaces are created in temporary directories and removed when the test finishes. Only `tests/test.apk` is kept as the generated test artifact.

The full test APK additionally enables `voice`, locally packaged HTTPS
assets and a sample native extension. The UI exercises native speech-to-text,
Web Speech microphone capture, HTML file inputs, secure-origin navigation,
and the app-provided JavaScript bridge. Recognition depends on device services.
The extension fixture includes a Java hook, a resource, and manifest fragments.
These extras remain absent from the core-only build.
