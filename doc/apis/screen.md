# Screen

Activation:

```sh
--api screen
```

Namespace:

```js
NativeBridge.Android.screen
```

## Keep screen on

```js
NativeBridge.Android.screen.keepOn(true);
NativeBridge.Android.screen.keepOn(false);
```

The method toggles Android's keep-screen-on flag for the generated Activity.

The setting applies while the Activity is visible. It is not a background wake lock and does not keep the application process alive.

The method is synchronous and returns whether KCAPK could apply the requested state.

## Next step

Continue with [System UI](system-ui.md).
