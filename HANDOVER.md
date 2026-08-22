# kcapk - Handover

## Current state

**Partially working.** The bridge compiles and the kclib runners execute, but the
async bridge between Java and JavaScript has a timing issue. The first call from
JavaScript to the native bridge returns immediately but the Promise is not
resolved.

## What's done

### jni.c (kclib repo)
- Rewritten as canonical bridge matching wvw.c pattern
- Parson for JSON (vendored from wvw.c)
- `setWhitelist` native method (Java passes whitelist, no more JNI manifest reading)
- `setHome` removed — not needed, `state_dir` in redp2p runner handles it
- Structured JSON responses: `{"ok":true,"result":...}` / `{"ok":false,"error":{...}}`
- Error codes: `INVALID_ARGUMENT`, `KCLIB_NOT_ALLOWED`, `KCLIB_FAILED`
- `make all` + `dist.sh` working, both ABIs build without warnings
- Pushed to `github.com:kaisarcode/jni.c.git`

### kcapk (repo)
- `build.sh` generates:
  - `KclibBridge.java` — JNI facade, `System.loadLibrary("jni")`, `run()` + `setWhitelist()` native methods
  - `NativeBridge.java` — `@JavascriptInterface` with `_invoke()` that calls `KclibBridge.run()`
  - `JSBridge.java` — Android-specific (`showToast`, `isOnline`, `getFilesDir`)
  - `MainActivity.java` — registers all three bridges, injects `NativeBridge` JS
- `Provisioner.ensureNative()` loads `libjni.so`, calls `setWhitelist()` with kclib deps from manifest
- `Provisioner` skips `.so` download when embedded manifest is newer than server manifest
- `splash.js` — KcSplash library with `NativeBridge.invoke()` and `NativeBridge.receive()`
- `app.js` — redp2p demo with PASS/FAIL summary per process
- Pushed to `github.com:kaisarcode/kcapk.git`

### Demo app
- All 12 runner calls succeed (open, status, list, stop, close, connect)
- The redp2p errors (HOME missing, target publisher not found) are expected network behavior
- `state_dir` added to publisher payload to avoid HOME dependency on Android

## What's broken

The synchronous `_invoke` approach blocks the JS thread. The `NativeBridge.invoke()` creates a Promise but `_invoke` returns synchronously. The first call fails because:

1. `_invoke` is a `@JavascriptInterface` method — it runs on the JS thread
2. `KclibBridge.run()` is a JNI call that may block (especially first call while library loads)
3. The Promise is created, `_invoke` returns the JSON string, but something in the
   chain is not correctly resolving the Promise

The log shows `error: {}` which means the catch block gets an empty object. This
suggests either:
- `_invoke` throws an exception that gets caught by the try/catch
- Or the return value from `_invoke` is not being parsed correctly

## What needs to be done

1. **Fix the async bridge** — The `_invoke` method should NOT be called from the
   JS thread. Instead, have the Java side manage the Promise lifecycle:
   - `_invoke` runs the kclib call on a background thread
   - Posts result back via `evaluateJavascript("NativeBridge.receive(...)"  )
   - `NativeBridge.receive` resolves/rejects the pending Promise
   - The `id` field tracks which Promise to resolve

   OR: Keep `_invoke` synchronous but ensure it returns quickly. The first call
   may be slow due to library loading — add a warmup call in `ensureNative`.

2. **Verify the `NativeBridge.receive` flow** — The background thread approach
   was abandoned mid-debug. It needs to be properly tested.

3. **The `error: {}` mystery** — Investigate why the catch block gets `{}`.
   Add logging to `_invoke` to see if it's even being called.

## Key files

| File | What |
|---|---|
| `/home/kaisar/work/kcapk/repo/build.sh` | Builder that generates all Java code |
| `/home/kaisar/work/kcapk/repo/assets/js/splash.js` | KcSplash + NativeBridge JS |
| `/home/kaisar/work/kcapk/repo/projects/demo/assets/js/app.js` | Demo test script |
| `/home/kaisar/work/kclib/repo/jni.c/src/kcjni.c` | JNI bridge (pushed, working) |
| `/home/kaisar/work/kclib/repo/wvw.c/src/libwvw.c` | Reference bridge (wvw.c) |

## Android devices connected

- **pocox3**: 100.67.183.8:41813
- **tab**: 100.68.204.93:36187

## Build commands

```bash
# jni.c
cd /home/kaisar/work/kclib/repo/jni.c
make all
/home/kaisar/work/kclib/scripts/dist.sh

# kcapk
cd /home/kaisar/work/kcapk/repo
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/home/kaisar/box/work/.local/share/android-sdk
./build.sh demo

# Install on tablet
adb -s 100.68.204.93:36187 install -r -t repo/projects/demo/app/bin/demo.apk
adb -s 100.68.204.93:36187 shell am start -n com.kaisarcode.demo/.MainActivity

# Check logs
adb -s 100.68.204.93:36187 logcat -d -s JSConsole
```
