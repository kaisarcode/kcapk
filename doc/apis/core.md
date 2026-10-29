# Core

The core Android bridge is always included. It does not require `--api`.

## API

```js
NativeBridge.Android.showToast(message);
```

Shows an Android short-duration toast.

Example:

```js
NativeBridge.Android.showToast("Saved");
```

The method is synchronous and has no optional Android permission requirement.

## Build impact

The core consists only of functionality KCAPK intentionally considers safe and broadly useful enough to include in every generated application. Optional APIs are not folded into core merely because they are small.

This keeps the default NativeBridge surface minimal and makes additional capabilities explicit in the build command.

## Trust boundary

Like every NativeBridge method, `showToast()` is callable only while the current top-level WebView page is trusted.

## Next step

Continue with [Files](files.md).
