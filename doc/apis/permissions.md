# Permissions

Activation:

```sh
--api permissions
```

Namespace:

```js
NativeBridge.Android.permissions
```

## Build-time declaration vs runtime request

Android permission declaration and runtime permission granting are separate.

Declare optional permissions with repeatable `--permission` options:

```sh
./build.sh \
    --api permissions \
    --permission camera \
    --permission notifications
```

Then query or request them from JavaScript:

```js
NativeBridge.Android.permissions.has("camera");
var granted = await NativeBridge.Android.permissions.request("camera");
```

## Methods

```js
NativeBridge.Android.permissions.has(name);
```

Synchronous. Returns whether the permission or special access is currently available.

```js
await NativeBridge.Android.permissions.request(name);
```

Asynchronous. Resolves to the effective state after Android finishes the relevant flow:

```text
true  -> granted / available
false -> denied / unavailable
```

If Android requires a permission that is not declared in the generated Manifest, the Promise rejects with `PERMISSION_NOT_DECLARED`.

## Supported aliases

```text
notifications
exactAlarm
exactAlarms
camera
microphone
location
locationFine
locationCoarse
```

A full `android.permission.*` name may also be used.

`notifications` maps to `POST_NOTIFICATIONS` and is treated as granted before API 33.

`exactAlarm` and `exactAlarms` map to `SCHEDULE_EXACT_ALARM`. Before API 31 exact-alarm access is treated as available. On newer Android versions KCAPK opens the relevant Settings flow and checks the result when the Activity resumes.

## Concurrency

Only one runtime permission request and one exact-alarm special-access request may be active at a time. A conflicting request rejects with `BUSY`.

## Async lifecycle

Permission requests use KCAPK's shared Promise/page-generation infrastructure. Results from an older WebView page are not delivered into a newer page.

See [Async operations](../async.md).

## Next step

Continue with [notifications](notifications.md).
