# Files

Activation:

```sh
--api files
```

Namespace:

```js
NativeBridge.Android.files
```

## Open a document

```js
var file = await NativeBridge.Android.files.open({
    type: "*/*"
});
```

The optional MIME `type` defaults to `*/*`.

Example restricted to images:

```js
var file = await NativeBridge.Android.files.open({
    type: "image/*"
});
```

`open()` launches Android's `ACTION_OPEN_DOCUMENT` picker and returns a Promise.

If the user cancels, it resolves with `null`. Otherwise it resolves with a descriptor such as:

```js
{
    uri: "content://...",
    name: "photo.png",
    type: "image/png",
    size: 12345
}
```

## Content handling

KCAPK does not read or copy the selected file. The API returns the Android content URI and available metadata.

No storage permission is required for the document-picker flow itself.

The returned URI can be passed to other APIs, such as `NativeBridge.Android.intents.share()`, when those APIs are also enabled.

## Async lifecycle

The picker uses the shared Activity-result and Promise infrastructure. Cancellation resolves `null`; native failures reject the Promise. Results belonging to stale WebView page generations are not delivered to a newer page.

## Next step

Continue with [Haptics](haptics.md).
