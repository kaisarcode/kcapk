# KCAPK

**Android WebView App Builder**

KCAPK builds Android applications from the command line without requiring Android Studio or Gradle. Use local HTML, CSS, and JavaScript or load a remote web application. The builder generates the Android project and packages an installable APK.

Applications can optionally access Android capabilities such as notifications, alarms, permissions, file selection, clipboard, device information, haptics, sharing, and voice recognition. They can also include app-owned Java extensions or package native executables. These features are independent: start with a WebView and add only what the application needs.

KCAPK currently targets Android SDK 24-36.

## Example

Build an application from a local web page at `web/index.html`:

```sh
./build.sh \
    --display-name "My App" \
    --project-name myapp \
    --package-name com.example.myapp \
    --webview-url ./web/index.html
```

The APK is written to `build/myapp/bin/myapp.apk`. KCAPK packages the entry file's containing directory, including adjacent assets.

For the first setup and device installation, follow [Getting started](doc/getting-started.md).

## Documentation

Start with the task you want to complete:

- [Getting started](doc/getting-started.md) - build and install a first app.
- [Building](doc/building.md) - install the required tools and understand build output.
- [Configuration](doc/configuration.md) - choose application names, appearance, APIs, permissions, and options.
- [WebView](doc/webview.md) - use local or remote pages and configure trusted origins.
- [Android APIs](doc/android-apis.md) - enable optional native capabilities and find individual API references.
- [External binaries](doc/external-binaries.md) - package executables and invoke them from JavaScript.
- [Release builds](doc/releases.md) - produce and sign an Android App Bundle.
- [Advanced documentation](doc/advanced/index.md) - architecture, bridge internals, asynchronous lifecycle, native extensions, and testing.

The [Android API reference](doc/apis/readme.md) lists methods, permissions, and platform-specific behavior.

## License

[![LGPLv3](https://www.gnu.org/graphics/lgplv3-147x51.png)](https://www.gnu.org/licenses/lgpl-3.0.html)

KCAPK is distributed under the **GNU Lesser General Public License version 3 (LGPLv3)**.
