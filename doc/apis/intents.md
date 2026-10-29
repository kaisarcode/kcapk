# Intents

Activation:

```sh
--api intents
```

Namespace:

```js
NativeBridge.Android.intents
```

This API covers general Android Intent operations: outbound sharing, opening URLs/settings, and consuming incoming shares.

## Share text

```js
NativeBridge.Android.intents.share({
    text: "Hello",
    subject: "Optional subject",
    title: "Optional content title",
    chooserTitle: "Share with",
    type: "text/plain"
});
```

## Share a content URI

A file selected through the files API can be shared separately:

```js
var file = await NativeBridge.Android.files.open({ type: "*/*" });

if (file) {
    NativeBridge.Android.intents.share({
        uri: file.uri,
        type: file.type || "*/*",
        title: file.name,
        chooserTitle: "Share file"
    });
}
```

When a `content://` URI is supplied, KCAPK sends it through `EXTRA_STREAM` and grants temporary read access to the receiving app.

## Open a URL

```js
NativeBridge.Android.intents.openUrl("https://example.com");
```

Only `http` and `https` URLs are accepted.

## Open application settings

```js
NativeBridge.Android.intents.openAppSettings();
```

Opens Android's application-details settings page for the generated app.

## Receive shares

Incoming share support requires both this API and one or more build-time share targets:

```sh
./build.sh \
    --api intents \
    --share-target 'image/*' \
    --share-target 'application/pdf'
```

`--share-target` without `--api intents` is rejected by the builder.

Use `*/*` only when the app intentionally accepts arbitrary shared content:

```sh
--share-target '*/*'
```

Consume the pending share with:

```js
var share = NativeBridge.Android.intents.consumeShare();
```

The method returns `null` when there is no pending share. Otherwise the object includes `action`, MIME `type`, optional `text`/`subject`, and `files[]` descriptors containing URI and metadata.

KCAPK does not read or copy incoming file contents. Android grants access to the incoming `content://` URI through the share Intent.

The share is consumed once. A second call returns `null` until Android delivers another share.

All public intent methods are synchronous; Android's chooser or settings UI continues independently after the Intent is launched.

## Next step

Continue with [files](files.md).
