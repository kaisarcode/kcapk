# Getting started

KCAPK builds Android applications directly from the command line, mainly for WebView-based projects. A generated app can load packaged local web content or a remote web application, and it can optionally expose selected Android functionality through `NativeBridge`.

## Clone KCAPK

```sh
git clone https://github.com/kaisarcode/kcapk.git
cd kcapk
chmod +x build.sh
```

KCAPK requires a Java JDK, Android SDK build tools, ImageMagick, and standard command-line utilities. If no Android SDK location is configured, KCAPK can bootstrap the required command-line tools under `~/android-sdk`.

For complete requirements and platform notes, see [Building](building.md).

## Create a web application

A local application can be as small as:

```html
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>My App</title>
</head>
<body>
    <h1>Hello Android</h1>
</body>
</html>
```

Save it as `web/index.html`.

When a local HTML file is used as the WebView entry point, KCAPK packages the complete containing directory. CSS, JavaScript, images, fonts, and subdirectories next to the entry file are copied into the generated Android assets.

## Build the APK

```sh
./build.sh \
    --display-name "My App" \
    --project-name myapp \
    --package-name com.example.myapp \
    --webview-url ./web/index.html
```

The generated debug APK is written to:

```text
build/myapp/bin/myapp.apk
```

The generated Android project is kept under `build/myapp/`, so it can be inspected after the build.

## Install the application

With Android Debug Bridge available and a device connected:

```sh
adb install -r -t build/myapp/bin/myapp.apk
```

To remove it later:

```sh
adb uninstall com.example.myapp
```

## Remote web applications

The same builder can point directly at a remote application:

```sh
./build.sh \
    --display-name "My App" \
    --project-name myapp \
    --package-name com.example.myapp \
    --webview-url https://app.example.com
```

Remote content should be combined with an explicit trusted-origin policy when additional origins need access to `NativeBridge`. See [WebView and trusted origins](webview.md).

## Next step

- [Configuration](configuration.md) - customize the app and select optional capabilities.
