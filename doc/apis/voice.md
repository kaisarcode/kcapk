# Voice

Activation:

```sh
--api voice
```

Namespace:

```js
NativeBridge.Android.voice
```

## Speech recognition

```js
const text = await NativeBridge.Android.voice.recognize({
    language: "es-AR",
    prompt: "Dictá tu registro"
});
```

This method launches Android's installed speech recognizer UI and returns a
Promise resolving to the first transcription as a string. If the user cancels
or no recognition is returned, it resolves to `null`. It rejects with
`VOICE_UNAVAILABLE` if there is no matching system recognizer,
`VOICE_FAILED` when launching fails, or `INVALID_ARGUMENT` for invalid JSON
options at the native boundary. The asynchronous lifecycle is tied to the
active WebView page generation.

`language` is an optional BCP-47 locale tag; `prompt` is optional UI text.
The recognizer's availability, language coverage, and internet usage depend on
the Android speech service installed on the device. KCAPK does not itself record
or transmit audio, and offline recognition is not guaranteed.

This API uses a system recognition activity and does not itself manage a raw
microphone stream. For Web Speech in an embedded page, enable the distinct
browser microphone path: `--local-https-assets`, `--api permissions`, and
`--permission microphone`. The app should request the runtime permission
before calling `SpeechRecognition`. Browser support varies by device.

See [WebView](../webview.md) and [Async operations](../async.md).

## Next step

Continue with [External binaries](../external-binaries.md).
