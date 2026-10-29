# Apps and launcher

Activation:

```sh
--api apps
```

Namespace:

```js
NativeBridge.Android.apps
```

KCAPK uses Android's `LauncherApps` service for launcher-oriented discovery and launching. It does not request `QUERY_ALL_PACKAGES`.

## List launchable activities

```js
var apps = await NativeBridge.Android.apps.list();
```

The Promise resolves to entries shaped like:

```js
{
    label: "Calculator",
    packageName: "com.example.calculator",
    activityName: "com.example.calculator.MainActivity"
}
```

A package may expose multiple launcher activities. Treat entries as launchable activities rather than assuming one row per package.

Icons are deliberately excluded from the list.

## Resolve an icon resource

```js
var icon = await NativeBridge.Android.apps.icon(
    app.packageName,
    app.activityName
);
```

Returns the identity of the Android resource associated with the launcher activity:

```js
{
    packageName: "com.example.calculator",
    activityName: "com.example.calculator.MainActivity",
    resourceId: 2131230890
}
```

`activityName` may be omitted to use the first launcher activity for the package.

KCAPK does not transform the icon. Use the separate [Resources](resources.md) API if resource metadata is needed.

## Launch

```js
NativeBridge.Android.apps.launch(
    app.packageName,
    app.activityName
);
```

The activity name is optional. When omitted, KCAPK launches the first launcher activity it finds for that package.

`launch()` is synchronous and returns whether Android accepted the request.

## Home launcher role

When this API is enabled, KCAPK includes a disabled `CATEGORY_HOME` activity alias. The generated app does not become a launcher merely by including the API.

Check whether the alias is enabled:

```js
NativeBridge.Android.apps.homeEnabled();
```

Enable or disable launcher candidacy:

```js
NativeBridge.Android.apps.setHomeEnabled(true);
NativeBridge.Android.apps.setHomeEnabled(false);
```

Open Android's Home selection settings:

```js
NativeBridge.Android.apps.openHomeSettings();
```

The user remains in control of the default launcher. Enabling the alias only makes the generated app eligible to be selected as Home.

## Async methods

`list()` and `icon()` return Promises and use the shared page-generation mechanism. `launch()`, `homeEnabled()`, `setHomeEnabled()`, and `openHomeSettings()` are synchronous.

## Next step

Continue with [resources](resources.md).
