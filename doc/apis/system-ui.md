# System UI

Activation:

```sh
--api system-ui
```

JavaScript namespace:

```js
NativeBridge.Android.systemUI
```

`systemUI` is the JavaScript namespace; `system-ui` is the canonical build option name.

## Status bar icon appearance

```js
NativeBridge.Android.systemUI.statusBar({ icons: "light" });
NativeBridge.Android.systemUI.statusBar({ icons: "dark" });
```

Dark status-bar icons require API 23+.

## Navigation bar icon appearance

```js
NativeBridge.Android.systemUI.navigationBar({ icons: "light" });
NativeBridge.Android.systemUI.navigationBar({ icons: "dark" });
```

Dark navigation-bar icons require API 26+.

## System bar visibility

```js
NativeBridge.Android.systemUI.hideBars();
NativeBridge.Android.systemUI.showBars();
```

These operations affect the generated Activity while it is visible.

On modern edge-to-edge Android versions, the visible system-bar background may be application content behind the bars rather than a separately painted bar color.

All methods are synchronous.

## Next step

Continue with [clipboard](clipboard.md).
