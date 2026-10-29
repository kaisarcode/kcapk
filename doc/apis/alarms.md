# Alarms

Activation:

```sh
--api alarms
```

Namespace:

```js
NativeBridge.Android.alarms
```

Enabling alarms adds the native alarm classes, alarm receivers, boot restore support, and `RECEIVE_BOOT_COMPLETED` to the generated Manifest.

The current native alarm action is a notification. KCAPK includes the notification internals required by alarms automatically; this does not expose `NativeBridge.Android.notifications` unless `--api notifications` is also enabled.

## Exact-alarm access

```js
NativeBridge.Android.alarms.canScheduleExact();
```

On API 31+, exact alarms may require Android's Alarms & reminders special access.

If exact scheduling is needed, declare:

```sh
--permission exactAlarm
```

Use `--api permissions` if the web app needs to drive the special-access request flow itself.

## Schedule

```js
NativeBridge.Android.alarms.schedule({
    id: 10,
    at: Date.now() + 60000,
    exact: true,
    action: {
        type: "notification",
        channel: "tasks",
        title: "Review server",
        text: "Check the production logs"
    }
});
```

Options:

- `id`: required non-negative alarm ID.
- `at`: required Unix epoch milliseconds.
- `exact`: defaults to `false`.
- `allowWhileIdle`: defaults to the value of `exact`.
- `action`: required native action object.

If the notification action has no `id`, KCAPK uses the alarm ID.

## Persistence and reboot

Scheduled definitions are stored in `SharedPreferences`. Future alarms are restored after device boot. For recurring alarms whose old time elapsed while Android was stopped, KCAPK advances to the next future local occurrence and persists that timestamp. One-time alarms in the past are discarded.

The alarm fires natively even if the WebView is not alive.

## Recurrence

KCAPK supports two optional repeat modes in `recurrence`: `daily` and `weekdays`, each with numeric `hour` (0–23) and `minute` (0–59). The application selects and persists the schedule policy when submitting an alarm. On delivery, KCAPK posts the notification and schedules the next local-day occurrence without requiring the WebView to remain open.

```js
NativeBridge.Android.alarms.schedule({
    id: 20,
    at: nextOccurrenceInMilliseconds,
    exact: NativeBridge.Android.alarms.canScheduleExact(),
    allowWhileIdle: true,
    recurrence: { mode: "weekdays", hour: 9, minute: 30 },
    action: { type: "notification", channel: "tasks", title: "Review tasks" }
});
```

An alarm without `recurrence` remains one-time. Scheduling exactness depends on Android special access and can fall back to a permitted inexact alarm.

## Cancel

```js
NativeBridge.Android.alarms.cancel(id);
NativeBridge.Android.alarms.cancelAll();
```

The public alarm methods are synchronous.

## Next step

Continue with [Apps](apps.md).
