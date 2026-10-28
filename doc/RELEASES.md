# Release builds

KCAPK can produce an Android App Bundle in addition to the normal debug APK.

## Build APK and AAB

```sh
./build.sh --release
```

The final artifacts are written under:

```text
build/<project>/bin/
```

For example:

```text
build/myapp/bin/myapp.apk
build/myapp/bin/myapp.aab
```

The APK produced by the current release flow remains a debug-signed APK intended for installation and testing. The AAB is the Play Store-oriented artifact.

## BundleTool

KCAPK uses Google's BundleTool to create the AAB.

The expected BundleTool version is downloaded automatically into the generated project directory when it is missing.

If a different `bundletool-all-*.jar` is found in that directory, KCAPK replaces it with the expected version.

## Unsigned AAB

When no release signing credentials are configured, KCAPK still generates the AAB and leaves it unsigned.

This is suitable for workflows that rely on Google Play App Signing.

## Signed AAB

Define all four release signing variables before running the build:

```sh
export RELEASE_KEYSTORE="/path/to/keystore.jks"
export RELEASE_KEY_ALIAS="mykey"
export RELEASE_STORE_PASS="storepassword"
export RELEASE_KEY_PASS="keypassword"
```

Then run:

```sh
./build.sh --release
```

When all values are present, KCAPK signs the generated AAB with `jarsigner`.

If `RELEASE_KEYSTORE` points to a missing file, the build fails instead of silently producing a different result.

## Create a keystore

One way to create a release keystore is:

```sh
keytool -genkeypair -v \
    -keystore my-release-key.jks \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias mykey \
    -storepass storepassword \
    -keypass keypassword \
    -dname "CN=MyCompany, OU=Dev, O=MyCompany, L=City, S=State, C=US"
```

Protect release keystores and passwords outside the repository.

## Versioning

Set Android version values through:

```sh
./build.sh \
    --version-code 12 \
    --version-name 1.2.0 \
    --release
```

Equivalent environment variables are:

```sh
VERSION_CODE=12
VERSION_NAME=1.2.0
```

`VERSION_CODE` must follow Android/Play Store version-code requirements for subsequent uploads.

## Output project

The AAB build reuses the same generated Android sources, resources, assets, DEX output, and packaged native libraries as the APK build.

This keeps both artifacts based on the same KCAPK configuration.

## Next step

- [Testing](TESTING.md) - validate generated artifacts and device behavior.
- [Project README](../README.md) - return to the main documentation.
