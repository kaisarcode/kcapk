# Network

Activation:

```sh
--api network
```

JavaScript API:

```js
NativeBridge.Android.isOnline();
```

Returns `true` when Android reports an active connected network and `false` otherwise.

Example:

```js
if (NativeBridge.Android.isOnline()) {
    // network currently available
}
```

## Manifest

Enabling this API adds:

```text
android.permission.ACCESS_NETWORK_STATE
```

No runtime permission dialog is required.

## Behavior

The result represents Android's current connectivity state. It does not guarantee that a particular host is reachable or that Internet traffic will succeed.

The method is synchronous.

## Next step

Continue with [Notifications](notifications.md).
