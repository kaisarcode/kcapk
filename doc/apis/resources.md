# Resources

Activation:

```sh
--api resources
```

Namespace:

```js
NativeBridge.Android.resources
```

This API inspects Android resources generically. It does not assume the caller wants an image, bytes, a data URL, or any particular presentation.

## Describe a resource

```js
var resource = await NativeBridge.Android.resources.describe(
    packageName,
    resourceId
);
```

Example result:

```js
{
    packageName: "com.example.app",
    resourceId: 2131230890,
    resourcePackage: "com.example.app",
    resourceType: "mipmap",
    resourceName: "ic_launcher",
    resourceFullName: "com.example.app:mipmap/ic_launcher",
    uri: "android.resource://com.example.app/2131230890",
    valueType: 3,
    density: 480,
    assetPath: "res/mipmap-xxhdpi-v4/ic_launcher.png"
}
```

`assetPath` is `null` when Android does not expose a backing `res/...` or `assets/...` path through the resolved `TypedValue`.

The `android.resource://` URI identifies a resource inside an installed APK. KCAPK does not read, copy, rasterize, encode, or otherwise transform the resource.

## Relationship with apps

The apps API can identify the icon resource used by a launcher activity:

```js
var icon = await NativeBridge.Android.apps.icon(
    app.packageName,
    app.activityName
);

var resource = await NativeBridge.Android.resources.describe(
    icon.packageName,
    icon.resourceId
);
```

The two APIs are intentionally independent. Enabling `apps` does not automatically expose `resources`.

## Errors

Resource lookup can reject with codes including:

```text
INVALID_ARGUMENT
PACKAGE_NOT_FOUND
RESOURCE_NOT_FOUND
RESOURCE_LOOKUP_FAILED
```

The method is asynchronous and uses the shared Promise/page-generation infrastructure.

## Next step

Continue with [system ui](system-ui.md).
