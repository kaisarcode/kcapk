# Clipboard

Activation:

```sh
--api clipboard
```

Namespace:

```js
NativeBridge.Android.clipboard
```

## Methods

```js
NativeBridge.Android.clipboard.set("text");
NativeBridge.Android.clipboard.get();
NativeBridge.Android.clipboard.hasText();
NativeBridge.Android.clipboard.clear();
```

`set(text)` writes text to the Android clipboard and returns whether the operation succeeded.

`get()` returns the first clipboard item coerced to text, or an empty string when unavailable.

`hasText()` reports whether the current primary clip contains text.

`clear()` clears the primary clip directly on API 28+. Older Android versions replace it with an empty text clip.

All methods are synchronous.

Clipboard behavior remains subject to Android's platform-level privacy and foreground-access rules.

## Next step

Continue with [screen](screen.md).
