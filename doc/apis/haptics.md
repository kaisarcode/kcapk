# Haptics

Activation:

```sh
--api haptics
```

Namespace:

```js
NativeBridge.Android.haptics
```

Enabling this API adds `android.permission.VIBRATE` to the generated Manifest.

## Methods

```js
NativeBridge.Android.haptics.hasVibrator();
NativeBridge.Android.haptics.vibrate(200);
NativeBridge.Android.haptics.effect("click");
NativeBridge.Android.haptics.cancel();
```

`hasVibrator()` reports whether Android exposes a vibrator.

`vibrate(milliseconds)` requests a duration-based vibration.

`effect(name)` supports:

```text
click
doubleClick
tick
heavyClick
```

On API 29+ KCAPK uses Android predefined vibration effects where available. Older versions fall back to duration-based vibration.

`cancel()` stops an active vibration when Android allows it.

All methods are synchronous.

## Next step

Continue with [Intents](intents.md).
