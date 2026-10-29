# Notifications

Activation:

```sh
--api notifications
```

Namespace:

```js
NativeBridge.Android.notifications
```

If the app targets Android 13+ and needs to post notifications, declare notification permission separately:

```sh
--permission notifications
```

Use `--api permissions` as well if the web app itself needs to request that permission at runtime through NativeBridge.

## Check availability

```js
NativeBridge.Android.notifications.canPost();
```

Returns whether notifications can currently be posted.

## Create a channel

```js
NativeBridge.Android.notifications.createChannel({
    id: "tasks",
    name: "Tasks",
    description: "Task notifications",
    importance: "high",
    showBadge: true,
    sound: "default"
});
```

Supported channel options include `id`, `name`, `description`, `importance`, `showBadge`, and `sound`.

Before API 26, channel creation is treated as successful because notification channels do not exist.

On API 26+, sound and importance are channel properties. After Android creates a channel, the user retains final control over its settings.

## Post

```js
NativeBridge.Android.notifications.post({
    id: 10,
    channel: "tasks",
    title: "Review server",
    text: "Check the production logs"
});
```

A non-negative `id` is required.

Common options include `channel`, `channelName`, `title`, `text`, `subText`, `autoCancel`, `ongoing`, `onlyAlertOnce`, `category`, `group`, `groupSummary`, `when`, `number`, `importance`, `sound`, `timeout`, and `progress`.

Progress example:

```js
NativeBridge.Android.notifications.post({
    id: 20,
    channel: "sync",
    title: "Synchronizing",
    text: "23 files",
    ongoing: true,
    onlyAlertOnce: true,
    progress: {
        max: 100,
        value: 42,
        indeterminate: false
    }
});
```

## Cancel

```js
NativeBridge.Android.notifications.cancel(id);
NativeBridge.Android.notifications.cancelAll();
```

All notification methods are synchronous NativeBridge operations.

## Next step

Continue with [Permissions](permissions.md).
