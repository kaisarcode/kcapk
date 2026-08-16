#!/bin/sh
# build.sh
# Summary: Manifest-driven Android thin-client APK/AAB builder.
#          Builds a generic WebView shell that provisions kclib native
#          libraries (libjni.so + lib<name>.so) and web assets from a server
#          manifest at runtime, and publishes the app manifest + assets + APK
#          to ../dist/<project>/.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: https://www.gnu.org/licenses/gpl-3.0.html

# Prints the usage message to stdout.
# @return 0 on success.
usage () {
    cat <<'EOF'
Usage:
  ./build.sh PROJECT_NAME

Options:
  -h, --help      Show help
  -c, --clean     Clean temp files and debug keystore first

Output:
  projects/PROJECT_NAME/app/bin/PROJECT_NAME.{apk,aab}
  ../dist/PROJECT_NAME/manifest.json + www/ + .apk
EOF
}

# Extracts a flat JSON value for a key. Prints one item per line
# (string value, scalar value, or one array element per line).
# @param file JSON file (flat).
# @param key  Key name (without quotes).
# @return 0 on success; the value is written to stdout.
json_get () {
    json_file="$1"
    json_key="$2"
    awk -v key="\"$json_key\"" '
    {
        buf = buf " " $0
    }
    END {
        if (match(buf, key "[[:space:]]*:[[:space:]]*")) {
            s = substr(buf, RSTART + RLENGTH)
            first = substr(s, 1, 1)
            if (first == "\"") {
                s = substr(s, 2)
                if (match(s, /^[^"]*/)) {
                    print substr(s, 1, RLENGTH)
                    exit
                }
            } else if (first == "[") {
                s = substr(s, 2)
                sub(/^[[:space:]]*/, "", s)
                if (substr(s, 1, 1) == "]") {
                    exit
                }
                for (;;) {
                    if (substr(s, 1, 1) != "\"") {
                        break
                    }
                    s = substr(s, 2)
                    if (match(s, /^[^"]*/)) {
                        print substr(s, 1, RLENGTH)
                        s = substr(s, RLENGTH + 1)
                    }
                    sub(/^[[:space:]]*/, "", s)
                    if (substr(s, 1, 1) == ",") {
                        s = substr(s, 2)
                        sub(/^[[:space:]]*/, "", s)
                        continue
                    }
                    break
                }
            } else {
                if (match(s, /^[^,}][^,}]*/)) {
                    v = substr(s, 1, RLENGTH)
                    gsub(/[[:space:]]/, "", v)
                    print v
                }
            }
        }
    }' "$json_file"
}

# Computes the SHA-256 digest of a file.
# @param file Path to the file.
# @return 0 on success; the digest is written to stdout.
sha256 () {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "error: no SHA-256 utility found (sha256sum or shasum)" >&2
        exit 1
    fi
}

PROJECT_NAME=""
CLEAN_ALL=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -c|--clean)
            CLEAN_ALL=true
            echo "Argument --clean detected. Forcing KeyStore and temporary files deletion."
            shift
            ;;
        -*)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            [ -z "$PROJECT_NAME" ] || { echo "error: only one PROJECT_NAME allowed" >&2; exit 1; }
            PROJECT_NAME="$1"
            shift
            ;;
    esac
done

[ -n "$PROJECT_NAME" ] || { usage >&2; exit 1; }
APP_DIR="./projects/$PROJECT_NAME"
CONFIG_FILE="$APP_DIR/config.json"

[ -f "$CONFIG_FILE" ] || { echo "error: config not found: $CONFIG_FILE" >&2; exit 1; }

# Reads a config value for the current project.
# @param key Key name (without quotes).
# @return 0 on success; the value is written to stdout.
cfg () {
    json_get "$CONFIG_FILE" "$1"
}

DISPLAY_NAME="$(cfg display_name)"
DISPLAY_NAME="${DISPLAY_NAME:-My App}"
PACKAGE_NAME="$(cfg package_name)"
PACKAGE_NAME="${PACKAGE_NAME:-com.kaisarcode.$PROJECT_NAME}"
ICON_SOURCE_FILE="$(cfg icon)"
ICON_SOURCE_FILE="${ICON_SOURCE_FILE:-icon.svg}"
IS_FULLSCREEN="$(cfg fullscreen)"
IS_FULLSCREEN="${IS_FULLSCREEN:-false}"
VERSION_CODE="$(cfg version_code)"
VERSION_CODE="${VERSION_CODE:-1}"
VERSION_NAME="$(cfg version_name)"
VERSION_NAME="${VERSION_NAME:-1.0}"
MIN_SDK="$(cfg min_sdk)"
MIN_SDK="${MIN_SDK:-24}"
TARGET_SDK="$(cfg target_sdk)"
TARGET_SDK="${TARGET_SDK:-34}"
BUILD_TOOLS_VERSION="$(cfg build_tools_version)"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-35.0.0}"
CMDLINE_TOOLS_VERSION="$(cfg cmdline_tools_version)"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-11076708}"
KCLIB_MANIFEST_URL="$(cfg kclib_manifest_url)"
KCLIB_MANIFEST_URL="${KCLIB_MANIFEST_URL:-https://kaisarcode.com/kclib/dist/manifest.json}"
APP_MANIFEST_URL="$(cfg app_manifest_url)"
APP_MANIFEST_URL="${APP_MANIFEST_URL:-https://kaisarcode.com/kcapk/dist/$PROJECT_NAME/manifest.json}"
RELEASE_KEYSTORE="$(cfg release_keystore)"
RELEASE_KEY_ALIAS="$(cfg release_key_alias)"
RELEASE_STORE_PASS="$(cfg release_store_pass)"
RELEASE_KEY_PASS="$(cfg release_key_pass)"
TRUSTED_ORIGINS="$(cfg trusted_origins)"
TRUSTED_ORIGINS="${TRUSTED_ORIGINS:-file:///}"

APP_SOURCE_MANIFEST="$APP_DIR/manifest.json"
[ -f "$APP_SOURCE_MANIFEST" ] || { echo "error: app manifest not found: $APP_SOURCE_MANIFEST" >&2; exit 1; }
KCLIB_DEPS="$(json_get "$APP_SOURCE_MANIFEST" kclib)"
APP_START="$(json_get "$APP_SOURCE_MANIFEST" start)"
APP_START="${APP_START:-www/index.html}"

PLATFORM_VERSION="android-$TARGET_SDK"

DEFAULT_CMDLINE_PREFIX="commandlinetools"
case "$(uname -s)" in
    Darwin)
        CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/${DEFAULT_CMDLINE_PREFIX}-mac-${CMDLINE_TOOLS_VERSION}_latest.zip"
        ;;
    *)
        CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/${DEFAULT_CMDLINE_PREFIX}-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
        ;;
esac

SDK_ZIP="${DEFAULT_CMDLINE_PREFIX}.zip"

BASE_DIR="$APP_DIR/app"
PACKAGE_SUBPATH="$(echo "$PACKAGE_NAME" | tr . /)"
SRC_DIR="$BASE_DIR/src/main/java/$PACKAGE_SUBPATH"
RES_DIR="$BASE_DIR/res"
LAYOUT_DIR="$RES_DIR/layout"
VALUES_DIR="$RES_DIR/values"
ASSETS_DIR="$BASE_DIR/assets"
ASSETS_SOURCE="$APP_DIR/assets"
COMMON_ASSETS_DIR="assets"
PUBLISH_DIR="../dist/$PROJECT_NAME"

MIPMAP_MDPI_DIR="$RES_DIR/mipmap-mdpi"
MIPMAP_HDPI_DIR="$RES_DIR/mipmap-hdpi"
MIPMAP_XHDPI_DIR="$RES_DIR/mipmap-xhdpi"
MIPMAP_XXHDPI_DIR="$RES_DIR/mipmap-xxhdpi"
MIPMAP_XXXHDPI_DIR="$RES_DIR/mipmap-xxxhdpi"

OUTPUT_DIR="$BASE_DIR/bin"
TEMP_ROOT_DIR="$BASE_DIR/temp"
TEMP_CLASSES_DIR="$TEMP_ROOT_DIR/classes"
FLAT_RES_DIR="$TEMP_ROOT_DIR/resources"
TEMP_BUILD_DATA_DIR="$TEMP_ROOT_DIR/build_data"
AAB_TEMP_DIR="$TEMP_ROOT_DIR/aab_work"

R_PACKAGE_DIR="$TEMP_CLASSES_DIR/$PACKAGE_SUBPATH"
TEMP_JAR_FILE="$TEMP_BUILD_DATA_DIR/classes.jar"
DEX_FILE="$TEMP_BUILD_DATA_DIR/classes.dex"

ANDROID_SDK_ROOT_CFG="$(cfg android_sdk_root)"
if [ -n "$ANDROID_SDK_ROOT_CFG" ]; then
    SDK_BASE="$ANDROID_SDK_ROOT_CFG"
elif [ -n "$ANDROID_SDK_ROOT" ]; then
    SDK_BASE="$ANDROID_SDK_ROOT"
elif [ -n "$ANDROID_HOME" ]; then
    SDK_BASE="$ANDROID_HOME"
else
    SDK_BASE="$HOME/android-sdk"
fi

ANDROID_SDK_ROOT="$SDK_BASE"
ANDROID_HOME="$ANDROID_SDK_ROOT"

CMDLINE_TOOLS_DIR="$ANDROID_SDK_ROOT/cmdline-tools/latest"
BUILD_TOOLS_DIR="$ANDROID_SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION"
PLATFORM_DIR="$ANDROID_SDK_ROOT/platforms/$PLATFORM_VERSION"
SDKMANAGER="$CMDLINE_TOOLS_DIR/bin/sdkmanager"
AAPT2="$BUILD_TOOLS_DIR/aapt2"
DX="$BUILD_TOOLS_DIR/d8"
ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"
ANDROID_JAR="$PLATFORM_DIR/android.jar"
DEBUG_KEYSTORE="$HOME/.android/debug.keystore"

MANIFEST_FILE="$BASE_DIR/AndroidManifest.xml"
MAIN_ACTIVITY_FILE="$SRC_DIR/MainActivity.java"
JS_INTERFACE_FILE="$SRC_DIR/JSBridge.java"
WEBVIEW_CLIENT_FILE="$SRC_DIR/TrustedWebViewClient.java"
PROVISIONER_FILE="$SRC_DIR/Provisioner.java"
KCLIB_BRIDGE_PACKAGE="com.kaisarcode.kclib"
KCLIB_BRIDGE_DIR="$BASE_DIR/src/main/java/com/kaisarcode/kclib"
KCLIB_BRIDGE_FILE="$KCLIB_BRIDGE_DIR/KclibBridge.java"

UNSIGNED_APK_TEMP="$TEMP_ROOT_DIR/unsigned.apk"
ALIGNED_APK_TEMP="$TEMP_ROOT_DIR/aligned.apk"
DEBUG_APK_FILE="$OUTPUT_DIR/$PROJECT_NAME.apk"

BUNDLETOOL_VERSION="1.18.2"
BUNDLETOOL_JAR="$BASE_DIR/bundletool-all-$BUNDLETOOL_VERSION.jar"
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar"
AAB_UNSIGNED_FILE="$TEMP_ROOT_DIR/unsigned.aab"
AAB_SIGNED_FILE="$OUTPUT_DIR/$PROJECT_NAME.aab"
BASE_MODULE_ZIP="$AAB_TEMP_DIR/base.zip"
FINAL_MODULE_DIR="$AAB_TEMP_DIR/final_module"
SIGNING_REQUIRED="false"

if $CLEAN_ALL; then
    if [ -f "$DEBUG_KEYSTORE" ]; then
        rm -f "$DEBUG_KEYSTORE"
        echo "Debug KeyStore deleted: $DEBUG_KEYSTORE"
    else
        echo "Debug KeyStore not found. Skipping deletion."
    fi
fi

# Downloads and configures the Android SDK if missing.
# @return None.
setup_sdk () {
    export ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
    export PATH="$PATH:$CMDLINE_TOOLS_DIR/bin"

    if [ ! -f "$SDKMANAGER" ]; then
        wget -t 5 --show-progress "$CMDLINE_TOOLS_URL" -O "$SDK_ZIP" || { echo "Error: Failed to download SDK." ; exit 1; }
        mkdir -p "$CMDLINE_TOOLS_DIR"
        unzip -q -o "$SDK_ZIP" -d "$CMDLINE_TOOLS_DIR/temp" || { echo "Error: Extraction failed." ; exit 1; }
        mv "$CMDLINE_TOOLS_DIR/temp/cmdline-tools/"* "$CMDLINE_TOOLS_DIR/"
        rm -rf "$CMDLINE_TOOLS_DIR/temp"
        rm "$SDK_ZIP"
    fi

    if [ ! -f "$AAPT2" ] || [ ! -f "$ANDROID_JAR" ]; then
        yes | "$SDKMANAGER" "platforms;$PLATFORM_VERSION" "build-tools;$BUILD_TOOLS_VERSION" --sdk_root="$ANDROID_SDK_ROOT" || { echo "Error: Failed to install SDK." ; exit 1; }
    fi
}

# Downloads bundletool if missing or version mismatch.
# @return None.
download_bundletool () {
    EXPECTED_JAR="$BASE_DIR/bundletool-all-$BUNDLETOOL_VERSION.jar"

    if [ -f "$EXPECTED_JAR" ]; then
        echo "BUNDLETOOL ($BUNDLETOOL_VERSION) found. Skipping download."
        BUNDLETOOL_JAR="$EXPECTED_JAR"
        return
    fi

    EXISTING_JAR=$(find "$BASE_DIR" -maxdepth 1 -name "bundletool-all-*.jar" -print -quit)
    if [ -n "$EXISTING_JAR" ]; then
        echo "Found existing BundleTool JAR ($EXISTING_JAR), but expected version $BUNDLETOOL_VERSION. Deleting and re-downloading."
        rm -f "$EXISTING_JAR"
    fi

    echo "BUNDLETOOL Not Found or Version Mismatch. Downloading $BUNDLETOOL_VERSION..."
    echo "URL: $BUNDLETOOL_URL"
    wget -q --show-progress "$BUNDLETOOL_URL" -O "$EXPECTED_JAR" || { echo "Error: Failed to download bundletool. Check URL or internet connection." ; exit 1; }

    BUNDLETOOL_JAR="$EXPECTED_JAR"
    echo "BUNDLETOOL downloaded successfully."
}

# Checks and sets up release signing credentials.
# @return None.
setup_release_signing () {
    if [ -n "$RELEASE_KEYSTORE" ] && [ -n "$RELEASE_KEY_ALIAS" ] && \
        [ -n "$RELEASE_STORE_PASS" ] && [ -n "$RELEASE_KEY_PASS" ]; then

        if [ ! -f "$RELEASE_KEYSTORE" ]; then
            echo "FATAL ERROR: Release KeyStore file not found at: $RELEASE_KEYSTORE"
            exit 1
        fi

        echo "Release KeyStore credentials found in config."
        SIGNING_REQUIRED="true"
    else
        echo "Release KeyStore credentials NOT found in config. AAB will be generated unsigned."
    fi
}

# Builds the Android App Bundle.
# @return None.
build_aab () {

    setup_release_signing

    case "$BASE_MODULE_ZIP" in
        /*) ABS_BASE_MODULE_ZIP="$BASE_MODULE_ZIP" ;;
        *)  ABS_BASE_MODULE_ZIP="$(pwd)/$BASE_MODULE_ZIP" ;;
    esac

    if [ ! -f "$DEX_FILE" ]; then
        echo "FATAL ERROR: classes.dex (compiled code) not found. Ensure the common build steps ran successfully."
        exit 1
    fi

    mkdir -p "$FINAL_MODULE_DIR"

    echo "Linking resources and manifest into temporary module zip."
    "$AAPT2" link \
        --proto-format \
        -o "$FINAL_MODULE_DIR/base_temp.zip" \
        -I "$ANDROID_JAR" \
        --manifest "$MANIFEST_FILE" \
        -R "$FLAT_RES_DIR/res.zip" \
        -A "$ASSETS_DIR" \
        --min-sdk-version "$MIN_SDK" \
        --target-sdk-version "$TARGET_SDK" \
        --version-code "$VERSION_CODE" \
        --version-name "$VERSION_NAME" \
        --auto-add-overlay || { echo "Error: AAPT2 Protobuf Link failed."; exit 1; }

    unzip -q "$FINAL_MODULE_DIR/base_temp.zip" -d "$FINAL_MODULE_DIR"
    rm "$FINAL_MODULE_DIR/base_temp.zip"

    mkdir -p "$FINAL_MODULE_DIR/manifest"
    mv "$FINAL_MODULE_DIR/AndroidManifest.xml" "$FINAL_MODULE_DIR/manifest/AndroidManifest.xml"

    mkdir -p "$FINAL_MODULE_DIR/dex"
    cp "$DEX_FILE" "$FINAL_MODULE_DIR/dex/classes.dex"

    if [ -d "$FINAL_MODULE_DIR/assets" ]; then
        (cd "$FINAL_MODULE_DIR" && zip -r -q "$ABS_BASE_MODULE_ZIP" manifest res dex resources.pb assets) || { echo "Error: ZIP tool failed to re-package module."; exit 1; }
    else
        (cd "$FINAL_MODULE_DIR" && zip -r -q "$ABS_BASE_MODULE_ZIP" manifest res dex resources.pb) || { echo "Error: ZIP tool failed to re-package module."; exit 1; }
    fi

    java -jar "$BUNDLETOOL_JAR" build-bundle \
        --modules="$BASE_MODULE_ZIP" \
        --output="$AAB_UNSIGNED_FILE" || { echo "Error: bundletool failed to generate AAB."; exit 1; }

    if [ "$SIGNING_REQUIRED" = "true" ]; then
        echo "Signing the AAB using jarsigner..."

        jarsigner -verbose \
            -sigalg SHA256withRSA \
            -digestalg SHA-256 \
            -keystore "$RELEASE_KEYSTORE" \
            -storepass "$RELEASE_STORE_PASS" \
            -keypass "$RELEASE_KEY_PASS" \
            "$AAB_UNSIGNED_FILE" "$RELEASE_KEY_ALIAS" || { echo "Error: jarsigner failed to sign the AAB." ; exit 1; }

        mv "$AAB_UNSIGNED_FILE" "$AAB_SIGNED_FILE"
    else
        mv "$AAB_UNSIGNED_FILE" "$AAB_SIGNED_FILE"
        echo "Skipping signing. Final AAB is generated without a signature (ready for Google Play App Signing)."
    fi

    echo "AAB Output: $AAB_SIGNED_FILE"
    rm -rf "$AAB_TEMP_DIR"
}

# Builds the debug APK.
# @return None.
build_apk () {
    zip -j "$UNSIGNED_APK_TEMP" "$DEX_FILE" || { echo "Error: ZIP tool failed to insert classes.dex." ; exit 1; }

    echo "Generating debug KeyStore if it does not exist..."
    if [ ! -f "$DEBUG_KEYSTORE" ]; then
        mkdir -p "$(dirname "$DEBUG_KEYSTORE")"
        keytool -genkey -v -keystore "$DEBUG_KEYSTORE" \
            -alias androiddebugkey -storepass android -keypass android -keyalg RSA -keysize 2048 \
            -validity 10000 \
            -dname "CN=Android Debug,O=Android,C=US"
        echo "Debug KeyStore successfully generated."
    else
        echo "Debug KeyStore found. Using existing KeyStore."
    fi

    echo "Aligning and Signing the Debug APK (Output: $DEBUG_APK_FILE)..."

    "$ZIPALIGN" -f 4 "$UNSIGNED_APK_TEMP" "$ALIGNED_APK_TEMP" || { echo "Error: ZIPALIGN failed." ; exit 1; }

    "$APKSIGNER" sign --ks "$DEBUG_KEYSTORE" \
        --ks-key-alias androiddebugkey \
        --ks-pass pass:android \
        --key-pass pass:android \
        --out "$DEBUG_APK_FILE" "$ALIGNED_APK_TEMP" || { echo "Error: APKSIGNER failed."; exit 1; }

    echo "APK Output: $DEBUG_APK_FILE"
}

# Publishes the completed app manifest and web assets to ../dist/<project>/.
# @return None.
publish () {
    echo "Publishing app to $PUBLISH_DIR..."

    [ -d "$ASSETS_SOURCE" ] || { echo "error: assets directory not found: $ASSETS_SOURCE" >&2; exit 1; }

    rm -rf "$PUBLISH_DIR"
    mkdir -p "$PUBLISH_DIR/www"

    cp -r "$ASSETS_SOURCE/." "$PUBLISH_DIR/www/"
    if [ -d "$COMMON_ASSETS_DIR" ]; then
        cp -r "$COMMON_ASSETS_DIR/." "$PUBLISH_DIR/www/"
    fi

    APK_PUBLISHED="$PUBLISH_DIR/$PROJECT_NAME.apk"
    if [ -f "$DEBUG_APK_FILE" ]; then
        cp "$DEBUG_APK_FILE" "$APK_PUBLISHED"
    else
        echo "warning: APK not found ($DEBUG_APK_FILE); publishing without apk artifact" >&2
        APK_PUBLISHED=""
    fi

    UPDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    MANIFEST_TMP="$PUBLISH_DIR/manifest.json.tmp"

    {
        printf '{\n'
        printf '  "updated_at": "%s",\n' "$UPDATED_AT"
        printf '  "kclib": ['
        FIRST=1
        for DEP in $KCLIB_DEPS; do
            if [ "$FIRST" -eq 0 ]; then
                printf ', '
            fi
            printf '"%s"' "$DEP"
            FIRST=0
        done
        printf '],\n'
        printf '  "start": "%s",\n' "$APP_START"
        if [ -n "$APK_PUBLISHED" ]; then
            printf '  "apk": {"path": "%s", "size_bytes": %s, "sha256": "%s", "version_code": %s, "version_name": "%s"},\n' \
                "$(basename "$APK_PUBLISHED")" \
                "$(wc -c < "$APK_PUBLISHED" | tr -d '[:space:]')" \
                "$(sha256 "$APK_PUBLISHED")" \
                "$VERSION_CODE" "$VERSION_NAME"
        fi
        printf '  "assets": [\n'
        FIRST=1
        (cd "$PUBLISH_DIR/www" && find . -type f | sort) | while IFS= read -r REL; do
            REL="${REL#./}"
            SIZE="$(wc -c < "$PUBLISH_DIR/www/$REL" | tr -d '[:space:]')"
            SHA="$(sha256 "$PUBLISH_DIR/www/$REL")"
            if [ "$FIRST" -eq 0 ]; then
                printf ',\n'
            fi
            printf '    {"path": "www/%s", "size_bytes": %s, "sha256": "%s"}' "$REL" "$SIZE" "$SHA"
            FIRST=0
        done
        printf '\n'
        printf '  ]\n'
        printf '}\n'
    } > "$MANIFEST_TMP"

    mv "$MANIFEST_TMP" "$PUBLISH_DIR/manifest.json"

    echo "Published manifest: $PUBLISH_DIR/manifest.json"
    echo "Published assets:   $PUBLISH_DIR/www/"
    if [ -n "$APK_PUBLISHED" ]; then
        echo "Published APK:      $APK_PUBLISHED"
    fi
}

setup_sdk

mkdir -p "$SRC_DIR" "$KCLIB_BRIDGE_DIR" "$LAYOUT_DIR" "$VALUES_DIR" "$OUTPUT_DIR" \
    "$MIPMAP_MDPI_DIR" "$MIPMAP_HDPI_DIR" "$MIPMAP_XHDPI_DIR" \
    "$MIPMAP_XXHDPI_DIR" "$MIPMAP_XXXHDPI_DIR"
rm -rf "$TEMP_ROOT_DIR"
mkdir -p "$TEMP_CLASSES_DIR" "$FLAT_RES_DIR" "$R_PACKAGE_DIR" "$TEMP_BUILD_DATA_DIR" "$AAB_TEMP_DIR"

DENSITY_PAIRS="mdpi:48x48 hdpi:72x72 xhdpi:96x96 xxhdpi:144x144 xxxhdpi:192x192"
ICON_TEMP_FILE="$RES_DIR/temp_icon_file_base"

case "$ICON_SOURCE_FILE" in
    http://*|https://*)
        echo "Starting Icon Generation from REMOTE URL ($ICON_SOURCE_FILE)..."
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$ICON_SOURCE_FILE" -o "$ICON_TEMP_FILE" || { echo "Error: Failed to download icon from $ICON_SOURCE_FILE using curl."; exit 1; }
        elif command -v wget >/dev/null 2>&1; then
            wget -q "$ICON_SOURCE_FILE" -O "$ICON_TEMP_FILE" || { echo "Error: Failed to download icon from $ICON_SOURCE_FILE using wget."; exit 1; }
        else
            echo "Error: Neither curl nor wget is available to download remote icons."
            exit 1
        fi
        ;;
    /*)
        echo "Starting Icon Generation from ABSOLUTE FILE ($ICON_SOURCE_FILE)..."
        if [ ! -f "$ICON_SOURCE_FILE" ]; then
            echo "Error: Icon file not found at $ICON_SOURCE_FILE."
            exit 1
        fi
        cp "$ICON_SOURCE_FILE" "$ICON_TEMP_FILE" || { echo "Error: Failed to copy local icon file." ; exit 1; }
        ;;
    *)
        echo "Starting Icon Generation from LOCAL FILE ($APP_DIR/$ICON_SOURCE_FILE)..."
        if [ ! -f "$APP_DIR/$ICON_SOURCE_FILE" ]; then
            echo "Error: Icon file not found at $APP_DIR/$ICON_SOURCE_FILE."
            exit 1
        fi
        cp "$APP_DIR/$ICON_SOURCE_FILE" "$ICON_TEMP_FILE" || { echo "Error: Failed to copy local icon file." ; exit 1; }
        ;;
esac

if command -v convert >/dev/null 2>&1; then
    for PAIR in $DENSITY_PAIRS; do
        DENSITY=$(echo "$PAIR" | cut -d: -f1)
        SIZE=$(echo "$PAIR" | cut -d: -f2)

        MIPMAP_SUBDIR="$RES_DIR/mipmap-$DENSITY"
        ICON_FINAL_PNG="$MIPMAP_SUBDIR/ic_launcher.png"

        convert "$ICON_TEMP_FILE" -resize "$SIZE" "$ICON_FINAL_PNG" || { echo "Error: ImageMagick conversion failed for $DENSITY." ; exit 1; }
    done
else
    echo "Error: 'convert' (ImageMagick) not found. Cannot generate icons."
    rm -f "$ICON_TEMP_FILE"
    exit 1
fi

rm -f "$ICON_TEMP_FILE"

echo "Icon Generation complete."

echo "Staging embedded assets..."
[ -d "$ASSETS_SOURCE" ] || { echo "error: assets directory not found: $ASSETS_SOURCE" >&2; exit 1; }
rm -rf "$ASSETS_DIR"
mkdir -p "$ASSETS_DIR/www"
cp -r "$ASSETS_SOURCE/." "$ASSETS_DIR/www/"
if [ -d "$COMMON_ASSETS_DIR" ]; then
    cp -r "$COMMON_ASSETS_DIR/." "$ASSETS_DIR/www/"
fi

echo "Computing embedded assets fingerprint..."
WWW_VERSION="$( (cd "$ASSETS_DIR/www" && find . -type f | sort | while IFS= read -r F; do printf '%s|%s\n' "${F#./}" "$(sha256 "$F")"; done) | sha256sum | awk '{print $1}' )"
printf '%s\n' "$WWW_VERSION" > "$ASSETS_DIR/www.version"
echo "www fingerprint: $WWW_VERSION"

JAVA_TRUSTED_ORIGINS=""
for ORIGIN in $TRUSTED_ORIGINS; do
    if [ -n "$JAVA_TRUSTED_ORIGINS" ]; then
        JAVA_TRUSTED_ORIGINS="$JAVA_TRUSTED_ORIGINS, "
    fi
    JAVA_TRUSTED_ORIGINS="$JAVA_TRUSTED_ORIGINS\"$ORIGIN\""
done

cat << EOF > "$MANIFEST_FILE"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$PACKAGE_NAME"
    android:versionCode="$VERSION_CODE"
    android:versionName="$VERSION_NAME">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:resizeableActivity="true"
        android:theme="@android:style/Theme.DeviceDefault.NoActionBar">
        <meta-data android:name="android.max_aspect" android:value="2.4" />
        <activity
            android:name="$PACKAGE_NAME.MainActivity"
            android:exported="true"
            android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|keyboardHidden|smallestScreenSize|screenLayout">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
    <uses-sdk android:minSdkVersion="$MIN_SDK" android:targetSdkVersion="$TARGET_SDK" />
</manifest>
EOF

cat << EOF > "$VALUES_DIR/strings.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">$DISPLAY_NAME</string>
    <string name="js_interface_name">AndroidBridge</string>
</resources>
EOF

cat << EOF > "$LAYOUT_DIR/activity_main.xml"
<?xml version="1.0" encoding="utf-8"?>
<WebView xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/webview"
    android:layout_width="match_parent"
    android:layout_height="match_parent" />
EOF

echo "Writing Java Code..."

FULLSCREEN_IMPORTS=""
FULLSCREEN_SETUP=""
if [ "$IS_FULLSCREEN" = "true" ]; then
    FULLSCREEN_IMPORTS="
import android.view.Window;
import android.view.WindowManager;"
    FULLSCREEN_SETUP="
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        getWindow().setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN
        );
"
fi

cat << EOF > "$PROVISIONER_FILE"
package $PACKAGE_NAME;

import android.content.Context;
import android.content.res.AssetManager;
import android.os.Build;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import com.kaisarcode.kclib.KclibBridge;

public class Provisioner {
    private static final String TAG = "Provisioner";

    private static final String KCLIB_MANIFEST_URL = "$KCLIB_MANIFEST_URL";
    private static final String APP_MANIFEST_URL = "$APP_MANIFEST_URL";
    private static final String DEFAULT_START = "$APP_START";
    private static final int CONNECT_TIMEOUT_MS = 15000;
    private static final int READ_TIMEOUT_MS = 30000;

    private static boolean nativeLoaded = false;
    private static String nativeLoadError = null;

    // Receives provisioning progress and warnings from the background thread.
    public interface ProgressListener {
        void onStage(String text);

        void onProgress(long bytesDone, long bytesTotal, String current, long currentDone, long currentTotal);

        void onWarning(String text);
    }

    // One file that needs downloading during this provisioning run.
    private static class Pending {
        final String label;
        final String url;
        final long size;
        final boolean isKclib;
        final String sha;
        final File target;
        final File tmp;

        Pending(String label, String url, long size, boolean isKclib, String sha, File target, File tmp) {
            this.label = label;
            this.url = url;
            this.size = size;
            this.isKclib = isKclib;
            this.sha = sha;
            this.target = target;
            this.tmp = tmp;
        }
    }

    // Aggregates per-file download counts into a global progress report.
    private static class Progress {
        private final ProgressListener listener;
        private final long total;
        private long committed;

        Progress(ProgressListener listener, long total) {
            this.listener = listener;
            this.total = Math.max(0, total);
        }

        void stage(String text) {
            listener.onStage(text);
        }

        void report(String label, long currentTotal, long currentDone) {
            long done = committed + currentDone;
            if (currentTotal > 0 && done > committed + currentTotal) {
                done = committed + currentTotal;
            }
            listener.onProgress(done, total, label, currentDone, currentTotal);
        }

        void commit(long n) {
            committed += n;
        }
    }

    // Provisions the runtime environment into app-private storage and returns
    // the local start URL (file:///...). Network errors fall back to the local
    // cache (embedded assets / previously installed files) and are surfaced as
    // warnings through the listener.
    public static String provision(Context context, ProgressListener listener) {
        File filesDir = context.getFilesDir();
        File nativeDir = context.getCodeCacheDir();
        File wwwDir = new File(filesDir, "www");

        String arch = resolveArch();

        copyEmbeddedWww(context, filesDir, wwwDir);

        String start = DEFAULT_START;
        try {
            listener.onStage("Reading app manifest...");
            JSONObject appManifest = fetchJson(APP_MANIFEST_URL);
            start = appManifest.optString("start", DEFAULT_START);

            listener.onStage("Reading kclib manifest...");
            JSONObject kclibManifest = fetchJson(KCLIB_MANIFEST_URL);

            List<Pending> pending = planWork(kclibManifest, appManifest, nativeDir, filesDir, arch);
            long total = 0;
            for (Pending p : pending) {
                total += Math.max(0, p.size);
            }

            Progress progress = new Progress(listener, total);
            syncPending(pending, progress);
            deleteAbsent(new File(filesDir, "www"), collectExpected(appManifest));
            listener.onStage("Done");
            Log.i(TAG, "provisioning complete");
        } catch (IOException e) {
            Log.w(TAG, "network unavailable; using local cache", e);
            String msg = e.getMessage();
            listener.onWarning("Download problem: " + (msg == null ? "network error" : msg)
                    + " (using local cache)");
        }

        return new File(filesDir, start).toURI().toString();
    }

    // Loads libjni.so from codeCacheDir on first use so that JSBridge can
    // dispatch runner payloads in-process. Returns true once the bridge is
    // available; the failure reason is available through nativeLoadError().
    public static synchronized boolean ensureNative(Context context) {
        if (nativeLoaded) {
            return true;
        }
        File lib = new File(context.getCodeCacheDir(), "libjni.so");
        if (!lib.isFile()) {
            nativeLoadError = "libjni.so not provisioned";
            return false;
        }
        if (!KclibBridge.ensureLoaded(lib.getAbsolutePath())) {
            nativeLoadError = KclibBridge.loadError();
            return false;
        }
        nativeLoaded = true;
        return true;
    }

    public static String nativeLoadError() {
        return nativeLoadError != null ? nativeLoadError : "native bridge unavailable";
    }

    private static String resolveArch() {
        for (String abi : Build.SUPPORTED_ABIS) {
            if ("arm64-v8a".equals(abi)) {
                return "aarch64";
            }
            if ("armeabi-v7a".equals(abi)) {
                return "armv7";
            }
        }
        String primary = Build.SUPPORTED_ABIS.length > 0 ? Build.SUPPORTED_ABIS[0] : "unknown";
        throw new IllegalStateException("unsupported ABI: " + primary);
    }

    // Walks both manifests and returns the files that still need downloading,
    // kclib native libraries first, then asset files.
    private static List<Pending> planWork(JSONObject kclibManifest, JSONObject appManifest,
            File nativeDir, File filesDir, String arch) throws IOException {
        List<Pending> pending = new ArrayList<Pending>();

        JSONArray deps = appManifest.optJSONArray("kclib");
        if (deps != null && deps.length() > 0) {
            nativeDir.mkdirs();

            JSONObject jniRec = findKclibRecord(kclibManifest, "jni.c", "libjni.so", "android", arch);
            String jniSha = jniRec.optString("sha256");
            File jniTarget = new File(nativeDir, "libjni.so");
            if (!isUpToDate(jniTarget, jniSha)) {
                Log.i(TAG, "libjni.so: installing");
                pending.add(new Pending(
                        "libjni.so (" + arch + ")",
                        url(KCLIB_MANIFEST_URL, jniRec.optString("path")),
                        jniRec.optLong("size_bytes", -1),
                        true,
                        jniSha,
                        jniTarget,
                        new File(nativeDir, "libjni.so.tmp")));
            }

            for (int i = 0; i < deps.length(); i++) {
                String dep = deps.optString(i);
                if (dep.isEmpty()) {
                    continue;
                }
                String libName = "lib" + dep + ".so";
                JSONObject rec = findKclibRecord(kclibManifest, dep + ".c", libName, "android", arch);
                String sha = rec.optString("sha256");
                File target = new File(nativeDir, libName);
                if (isUpToDate(target, sha)) {
                    Log.i(TAG, dep + ": up to date");
                    continue;
                }
                Log.i(TAG, dep + ": installing");
                pending.add(new Pending(
                        libName + " (" + arch + ")",
                        url(KCLIB_MANIFEST_URL, rec.optString("path")),
                        rec.optLong("size_bytes", -1),
                        true,
                        sha,
                        target,
                        new File(nativeDir, libName + ".tmp")));
            }
        }

        JSONArray assets = appManifest.optJSONArray("assets");
        if (assets != null) {
            for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.optJSONObject(i);
                if (a == null) {
                    continue;
                }
                String path = a.optString("path");
                if (path.isEmpty()) {
                    continue;
                }
                File target = new File(filesDir, path);
                String sha = a.optString("sha256");
                if (isUpToDate(target, sha)) {
                    continue;
                }
                target.getParentFile().mkdirs();
                Log.i(TAG, "asset to install: " + path);
                pending.add(new Pending(
                        path,
                        url(APP_MANIFEST_URL, path),
                        a.optLong("size_bytes", -1),
                        false,
                        sha,
                        target,
                        new File(target.getParentFile(), target.getName() + ".tmp")));
            }
        }

        return pending;
    }

    // Downloads and installs every pending file in order, reporting progress.
    private static void syncPending(List<Pending> pending, Progress progress) throws IOException {
        for (Pending p : pending) {
            progress.stage("Downloading " + p.label + "...");
            downloadToFile(p.url, p.tmp, p.size, p.label, progress);
            verifyOrThrow(p.tmp, p.size, p.sha, p.label);
            if (p.isKclib) {
                if (!p.tmp.renameTo(p.target)) {
                    throw new IOException("cannot install " + p.label);
                }
                if (!p.target.setExecutable(true, false)) {
                    throw new IOException("cannot chmod " + p.label);
                }
                Log.i(TAG, p.label + ": installed");
            } else {
                if (!p.tmp.renameTo(p.target)) {
                    copyReplace(p.tmp, p.target);
                }
                Log.i(TAG, "asset installed: " + p.label);
            }
        }
    }

    // Returns the set of asset paths the manifest expects, for pruning.
    private static Set<String> collectExpected(JSONObject appManifest) {
        Set<String> expected = new HashSet<String>();
        JSONArray assets = appManifest.optJSONArray("assets");
        if (assets == null) {
            return expected;
        }
        for (int i = 0; i < assets.length(); i++) {
            JSONObject a = assets.optJSONObject(i);
            if (a != null) {
                String path = a.optString("path");
                if (!path.isEmpty()) {
                    expected.add(path);
                }
            }
        }
        return expected;
    }

    private static JSONObject findKclibRecord(JSONObject kclibManifest, String project, String binary,
            String platform, String arch) throws IOException {
        JSONObject projects = kclibManifest.optJSONObject("projects");
        if (projects == null) {
            throw new IOException("kclib manifest has no projects");
        }
        JSONArray variants = projects.optJSONArray(project);
        if (variants == null) {
            throw new IOException("kclib project not in manifest: " + project);
        }
        for (int i = 0; i < variants.length(); i++) {
            JSONObject v = variants.optJSONObject(i);
            if (v != null
                    && platform.equals(v.optString("platform"))
                    && arch.equals(v.optString("arch"))
                    && binary.equals(v.optString("binary"))) {
                return v;
            }
        }
        throw new IOException("no record for " + project + "/" + binary
                + " (" + platform + "/" + arch + ")");
    }

    // Deletes local files under filesDir/www that are not listed in the manifest.
    private static void deleteAbsent(File dir, Set<String> expected) {
        String prefix = dir.getParentFile().getAbsolutePath() + File.separator;
        deleteAbsent(dir, expected, prefix);
    }

    private static void deleteAbsent(File dir, Set<String> expected, String prefix) {
        if (!dir.isDirectory()) {
            return;
        }
        File[] children = dir.listFiles();
        if (children == null) {
            return;
        }
        for (File child : children) {
            if (child.isDirectory()) {
                deleteAbsent(child, expected, prefix);
                if (child.list().length == 0) {
                    child.delete();
                }
            } else {
                String rel = child.getAbsolutePath();
                if (rel.startsWith(prefix)) {
                    rel = rel.substring(prefix.length());
                }
                if (!expected.contains(rel)) {
                    child.delete();
                    Log.i(TAG, "asset removed: " + rel);
                }
            }
        }
    }

    // Copies the embedded www assets from the APK into filesDir/www on first
    // launch or whenever the embedded fingerprint differs.
    private static void copyEmbeddedWww(Context context, File filesDir, File wwwDir) {
        try {
            AssetManager am = context.getAssets();
            String embeddedVersion = readStreamToString(am.open("www.version"));
            String localVersion = readFileToString(new File(filesDir, "www.version"));
            if (embeddedVersion.equals(localVersion)) {
                return;
            }
            deleteRecursive(wwwDir);
            if (wwwDir.mkdirs()) {
                copyAssetDir(am, "www", wwwDir);
                writeStringToFile(new File(filesDir, "www.version"), embeddedVersion);
                Log.i(TAG, "embedded www copied to " + wwwDir);
            }
        } catch (IOException e) {
            Log.e(TAG, "cannot copy embedded assets", e);
        }
    }

    private static void copyAssetDir(AssetManager am, String assetPath, File destDir) throws IOException {
        String[] entries = am.list(assetPath);
        if (entries == null) {
            return;
        }
        for (String entry : entries) {
            String child = assetPath + "/" + entry;
            File out = new File(destDir, entry);
            String[] sub = am.list(child);
            if (sub != null && sub.length > 0) {
                if (!out.mkdirs() && !out.isDirectory()) {
                    throw new IOException("mkdir failed: " + out);
                }
                copyAssetDir(am, child, out);
            } else {
                InputStream in = null;
                FileOutputStream fos = null;
                try {
                    in = am.open(child);
                    fos = new FileOutputStream(out);
                    copy(in, fos);
                } finally {
                    close(in);
                    close(fos);
                }
            }
        }
    }

    private static void downloadToFile(String url, File out, long expected, String label, Progress progress)
            throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        try {
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " for " + url);
            }
            long declared = conn.getContentLength();
            if (declared < 0) {
                declared = expected;
            }
            InputStream in = null;
            FileOutputStream fos = null;
            try {
                in = conn.getInputStream();
                fos = new FileOutputStream(out);
                byte[] buf = new byte[8192];
                long done = 0;
                int n;
                while ((n = in.read(buf)) > 0) {
                    fos.write(buf, 0, n);
                    done += n;
                    progress.report(label, declared, done);
                }
                progress.commit(done);
            } finally {
                close(in);
                close(fos);
            }
        } finally {
            conn.disconnect();
        }
    }

    private static JSONObject fetchJson(String url) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        try {
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " for " + url);
            }
            StringBuilder sb = new StringBuilder();
            BufferedReader reader = null;
            try {
                reader = new BufferedReader(new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8));
                String line;
                while ((line = reader.readLine()) != null) {
                    sb.append(line).append('\n');
                }
            } finally {
                close(reader);
            }
            try {
                return new JSONObject(sb.toString());
            } catch (Exception e) {
                throw new IOException("invalid JSON from " + url, e);
            }
        } finally {
            conn.disconnect();
        }
    }

    private static String url(String manifestUrl, String path) {
        int idx = manifestUrl.lastIndexOf("/manifest.json");
        String base = idx >= 0 ? manifestUrl.substring(0, idx + 1) : manifestUrl;
        if (base.endsWith("/")) {
            return base + path;
        }
        return base + "/" + path;
    }

    private static boolean isUpToDate(File target, String sha) {
        return target.isFile() && !sha.isEmpty() && sha.equals(sha256(target));
    }

    private static void verifyOrThrow(File f, long size, String sha, String name) throws IOException {
        if (size >= 0 && f.length() != size) {
            f.delete();
            throw new IOException("size mismatch for " + name);
        }
        if (!sha.isEmpty() && !sha.equals(sha256(f))) {
            f.delete();
            throw new IOException("sha256 mismatch for " + name);
        }
    }

    private static String sha256(File f) {
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
            StringBuilder sb = new StringBuilder();
            for (byte b : md.digest()) {
                sb.append(String.format("%02x", b & 0xff));
            }
            return sb.toString();
        } catch (Exception e) {
            return "";
        } finally {
            close(in);
        }
    }

    private static void copyReplace(File src, File dst) throws IOException {
        InputStream in = null;
        FileOutputStream fos = null;
        try {
            in = new FileInputStream(src);
            fos = new FileOutputStream(dst);
            copy(in, fos);
        } finally {
            close(in);
            close(fos);
        }
        src.delete();
    }

    private static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
    }

    private static void deleteRecursive(File f) {
        if (!f.exists()) {
            return;
        }
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursive(child);
                }
            }
        }
        f.delete();
    }

    private static String readFileToString(File f) {
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            return readStreamToString(in);
        } catch (IOException e) {
            return "";
        } finally {
            close(in);
        }
    }

    private static String readStreamToString(InputStream in) throws IOException {
        StringBuilder sb = new StringBuilder();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
        }
        return sb.toString();
    }

    private static void writeStringToFile(File f, String s) throws IOException {
        FileOutputStream fos = null;
        try {
            fos = new FileOutputStream(f);
            fos.write(s.getBytes(StandardCharsets.UTF_8));
        } finally {
            close(fos);
        }
    }

    private static void close(InputStream in) {
        if (in != null) {
            try {
                in.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static void close(OutputStream out) {
        if (out != null) {
            try {
                out.close();
            } catch (IOException ignored) {
            }
        }
    }

    private static void close(BufferedReader reader) {
        if (reader != null) {
            try {
                reader.close();
            } catch (IOException ignored) {
            }
        }
    }
}
EOF

cat << EOF > "$WEBVIEW_CLIENT_FILE"
package $PACKAGE_NAME;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class TrustedWebViewClient extends WebViewClient {
    private final Context context;
    private final String[] trustedOrigins;

    public TrustedWebViewClient(Context context, String[] trustedOrigins) {
        this.context = context;
        this.trustedOrigins = trustedOrigins;
    }

    private boolean openExternally(String url) {
        try {
            context.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            return true;
        } catch (Exception ignored) {
            return true;
        }
    }

    private boolean handleNavigation(String url) {
        if (JSBridge.isTrustedUrl(url, trustedOrigins)) {
            return false;
        }

        return openExternally(url);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        if (!request.isForMainFrame()) {
            return false;
        }

        return handleNavigation(request.getUrl().toString());
    }
}
EOF

cat << EOF > "$KCLIB_BRIDGE_FILE"
package $KCLIB_BRIDGE_PACKAGE;

import java.io.File;

// Static facade for the libjni native bridge. libjni.so is provisioned at
// runtime (see Provisioner) and loaded on first use; it registers the native
// "run" method below, which dlopens the provisioned lib<name>.so and calls
// kc_<name>_run with the runner payload.
public final class KclibBridge {
    private static boolean loaded = false;
    private static String loadError = null;

    private KclibBridge() {
    }

    public static synchronized boolean ensureLoaded(String libPath) {
        if (loaded) {
            return true;
        }
        File lib = new File(libPath);
        if (!lib.isFile()) {
            loadError = "libjni.so not provisioned";
            return false;
        }
        try {
            System.load(lib.getAbsolutePath());
            loaded = true;
            loadError = null;
            return true;
        } catch (Throwable t) {
            loadError = "load libjni.so: " + String.valueOf(t.getMessage());
            return false;
        }
    }

    public static String loadError() {
        return loadError != null ? loadError : "unknown";
    }

    public static native String run(String argsJson, String stdinJson);
}
EOF

cat << EOF > "$JS_INTERFACE_FILE"
package $PACKAGE_NAME;

import android.content.Context;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;

import java.net.URI;

import com.kaisarcode.kclib.KclibBridge;

public class JSBridge {
    private static final String LOCAL_ASSET_PREFIX = "file:///android_asset/";
    private final Context context;
    private final WebView webView;
    private final String[] trustedOrigins;
    private volatile String currentUrl = "file:///android_asset/";

    public JSBridge(Context context, WebView webView, String[] trustedOrigins) {
        this.context = context;
        this.webView = webView;
        this.trustedOrigins = trustedOrigins;
    }

    public void setCurrentUrl(String url) {
        this.currentUrl = url;
    }

    public static boolean isTrustedUrl(String url, String[] trustedOrigins) {
        if (url == null || url.isEmpty()) {
            return false;
        }

        if (url.startsWith("file://")) {
            return true;
        }

        try {
            URI parsedUrl = URI.create(url);
            String origin = normalizeOrigin(parsedUrl);

            if (origin == null) {
                return false;
            }

            for (String trustedOrigin : trustedOrigins) {
                try {
                    URI trustedUri = URI.create(trustedOrigin);
                    String normalizedTrusted = normalizeOrigin(trustedUri);
                    if (normalizedTrusted != null && origin.equals(normalizedTrusted)) {
                        return true;
                    }
                } catch (IllegalArgumentException ignored) {
                    if (origin.equals(trustedOrigin)) {
                        return true;
                    }
                }
            }
        } catch (IllegalArgumentException ignored) {
            return false;
        }

        return false;
    }

    private static String normalizeOrigin(URI uri) {
        String scheme = uri.getScheme();
        String host = uri.getHost();

        if (scheme == null || host == null) {
            return null;
        }

        scheme = scheme.toLowerCase();
        host = host.toLowerCase();
        if (host.startsWith("www.")) {
            host = host.substring(4);
        }

        int port = uri.getPort();
        if (port == -1) {
            return scheme + "://" + host;
        }

        return scheme + "://" + host + ":" + port;
    }

    private boolean canUseBridge() {
        String url = currentUrl;
        if (url == null) {
            return false;
        }
        if (url.startsWith("file://")) {
            return true;
        }
        try {
            return isTrustedUrl(url, trustedOrigins);
        } catch (Exception e) {
            return false;
        }
    }

    @JavascriptInterface
    public void showToast(String message) {
        if (!canUseBridge()) {
            return;
        }

        Toast.makeText(context, message, Toast.LENGTH_SHORT).show();
    }

    @JavascriptInterface
    public boolean isOnline() {
        if (!canUseBridge()) {
            return false;
        }

        ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm != null) {
            NetworkInfo netInfo = cm.getActiveNetworkInfo();
            return netInfo != null && netInfo.isConnected();
        }
        return false;
    }

    // Runs a provisioned kclib command in-process through the JNI bridge. No
    // subprocess is spawned: libjni.so is loaded on first use and dispatches
    // the payload to lib<name>.so's kc_<name>_run entry point.
    // payloadJson is the runner payload, e.g.
    // {"lib":"grd","cmd":"split","args":{"w":1920},"handle":0}. Returns the
    // result JSON, or "error: <detail>" on failure.
    @JavascriptInterface
    public String runKclib(String payloadJson, String stdin) {
        if (!canUseBridge()) {
            return "error: untrusted origin";
        }
        if (payloadJson == null || payloadJson.isEmpty()) {
            return "error: missing payload";
        }
        if (!Provisioner.ensureNative(context)) {
            return "error: " + Provisioner.nativeLoadError();
        }
        try {
            return KclibBridge.run(payloadJson, stdin);
        } catch (Throwable t) {
            return "error: " + String.valueOf(t.getMessage());
        }
    }
}
EOF

cat << EOF > "$MAIN_ACTIVITY_FILE"
package $PACKAGE_NAME;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.webkit.WebView;
import android.content.res.Resources;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
$FULLSCREEN_IMPORTS

public class MainActivity extends Activity {
    private static final String TAG = "MainActivity";
    private static final String JS_INTERFACE_NAME = "AndroidBridge";
    private static final String[] TRUSTED_ORIGINS = { $JAVA_TRUSTED_ORIGINS };

    private WebView webView;
    private JSBridge jsBridge;
    private String homeUrl = null;

    @Override
    public void onCreate(Bundle savedInstanceState) {
$FULLSCREEN_SETUP
        super.onCreate(savedInstanceState);
        Resources res = getResources();

        int layoutResId = res.getIdentifier("activity_main", "layout", getPackageName());
        setContentView(layoutResId);

        int webViewResId = res.getIdentifier("webview", "id", getPackageName());
        webView = (WebView) findViewById(webViewResId);

        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setAllowFileAccess(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setUseWideViewPort(true);
        webView.getSettings().setLoadWithOverviewMode(true);
        webView.setVerticalScrollBarEnabled(false);
        jsBridge = new JSBridge(this, webView, TRUSTED_ORIGINS);
        webView.setWebViewClient(new TrustedWebViewClient(this, TRUSTED_ORIGINS) {
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                jsBridge.setCurrentUrl(url);
                if (homeUrl != null && homeUrl.equals(url)) {
                    view.clearHistory();
                    homeUrl = null;
                }
            }
        });
        webView.addJavascriptInterface(jsBridge, JS_INTERFACE_NAME);

        webView.loadDataWithBaseURL(splashBaseUrl(), loadSplashPage(), "text/html", "UTF-8", null);

        final Handler handler = new Handler(Looper.getMainLooper());
        final Activity activity = this;

        new Thread(new Runnable() {
            @Override
            public void run() {
                final String[] result = new String[2];

                Provisioner.ProgressListener listener = new Provisioner.ProgressListener() {
                    @Override
                    public void onStage(final String text) {
                        handler.post(new Runnable() {
                            @Override
                            public void run() {
                                webView.evaluateJavascript(
                                         "if(window.AndroidBridge && window.AndroidBridge.setStatus)window.AndroidBridge.setStatus(\"" + escapeJs(text) + "\");", null);
                            }
                        });
                    }

                    @Override
                    public void onProgress(final long bytesDone, final long bytesTotal, final String current,
                            final long currentDone, final long currentTotal) {
                        handler.post(new Runnable() {
                            @Override
                            public void run() {
                                webView.evaluateJavascript(
                                        "if(window.AndroidBridge && window.AndroidBridge.setProgress)window.AndroidBridge.setProgress(" + bytesDone + "," + bytesTotal
                                                + ",\"" + escapeJs(current) + "\"," + currentDone + ","
                                                + currentTotal + ");", null);
                            }
                        });
                    }

                    @Override
                    public void onWarning(final String text) {
                        handler.post(new Runnable() {
                            @Override
                            public void run() {
                                webView.evaluateJavascript(
                                        "if(window.AndroidBridge && window.AndroidBridge.setWarning)window.AndroidBridge.setWarning(\"" + escapeJs(text) + "\");", null);
                            }
                        });
                    }
                };

                try {
                    result[0] = Provisioner.provision(activity, listener);
                } catch (Exception e) {
                    result[1] = escapeHtml(String.valueOf(e.getMessage()));
                    Log.e(TAG, "provision failed", e);
                }

                handler.post(new Runnable() {
                    @Override
                    public void run() {
                        if (result[0] != null) {
                            homeUrl = result[0];
                            webView.loadUrl(result[0]);
                        } else {
                            webView.loadDataWithBaseURL("file:///android_asset/",
                                    errorPage(result[1]), "text/html", "UTF-8", null);
                            webView.clearHistory();
                        }
                    }
                });
            }
        }).start();
    }

    private String splashBaseUrl() {
        if (new File(getFilesDir(), "www/splash.html").isFile()) {
            return "file://" + getFilesDir() + "/www/";
        }
        return "file:///android_asset/www/";
    }

    private String loadSplashPage() {
        File cached = new File(getFilesDir(), "www/splash.html");
        if (cached.isFile()) {
            return readFile(cached);
        }
        try {
            InputStream is = getAssets().open("www/splash.html");
            return readStream(is);
        } catch (IOException e) {
            Log.e(TAG, "Failed to load splash.html from assets", e);
            return "<html><body>Error loading screen</body></html>";
        }
    }

    private static String readFile(File f) {
        try {
            return readStream(new FileInputStream(f));
        } catch (IOException e) {
            Log.e(TAG, "Failed to read " + f.getAbsolutePath(), e);
            return null;
        }
    }

    private static String readStream(InputStream is) throws IOException {
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append('\n');
            }
            return sb.toString();
        } finally {
            if (reader != null) {
                reader.close();
            }
        }
    }

    private static String escapeJs(String s) {
        if (s == null) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\\\\') {
                sb.append('\\\\').append('\\\\');
            } else if (c == '"') {
                sb.append('\\\\').append('"');
            } else if (c == '\'') {
                sb.append('\\\\').append('\'');
            } else if (c == '\n') {
                sb.append('\\\\').append('n');
            } else if (c == '\r') {
                sb.append('\\\\').append('r');
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    private static String errorPage(String error) {
        return "<html><body style='margin:0;background:#101418;color:#dde3ea;"
                + "font-family:sans-serif;padding:2rem;'>"
                + "<h2>KaisarCode runtime error</h2><p style='color:#f0883e;'>" + error
                + "</p></body></html>";
    }

    private static String escapeHtml(String s) {
        if (s == null) {
            return "";
        }
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    @Override
    public void onBackPressed() {
        if (homeUrl != null && !homeUrl.equals(webView.getUrl())) {
            super.onBackPressed();
            return;
        }
        if (webView.canGoBack()) { webView.goBack(); } else { super.onBackPressed(); }
    }
}
EOF

echo "Compiling Resources with AAPT2..."
"$AAPT2" compile --dir "$RES_DIR" -o "$FLAT_RES_DIR/res.zip" || { echo "Error: AAPT2 Compile failed."; exit 1; }

echo "Linking Resources, Manifest, and Generating R.java..."
"$AAPT2" link \
    --output-text-symbols "$TEMP_CLASSES_DIR/R.txt" \
    -I "$ANDROID_JAR" \
    --manifest "$MANIFEST_FILE" \
    -R "$FLAT_RES_DIR/res.zip" \
    -A "$ASSETS_DIR" \
    -o "$UNSIGNED_APK_TEMP" \
    --java "$TEMP_CLASSES_DIR" \
    --auto-add-overlay || { echo "Error: AAPT2 Link failed."; exit 1; }

echo "Compiling Source Code..."
javac -g:none --release 11 \
    -classpath "$ANDROID_JAR" \
    -d "$TEMP_CLASSES_DIR" \
    "$R_PACKAGE_DIR/R.java" \
    "$WEBVIEW_CLIENT_FILE" \
    "$MAIN_ACTIVITY_FILE" \
    "$JS_INTERFACE_FILE" \
    "$KCLIB_BRIDGE_FILE" \
    "$PROVISIONER_FILE" || { echo "Error: JAVAC failed."; exit 1; }

echo "Packaging .class files into temporary JAR..."
CURRENT_DIR=$(pwd)
case "$TEMP_JAR_FILE" in
    /*) ABS_TEMP_JAR_FILE="$TEMP_JAR_FILE" ;;
    *)  ABS_TEMP_JAR_FILE="$CURRENT_DIR/$TEMP_JAR_FILE" ;;
esac
(cd "$TEMP_CLASSES_DIR" && jar cf "$ABS_TEMP_JAR_FILE" .) || { echo "Error: JAR creation failed."; exit 1; }

echo "Generating Dalvik/ART bytecode..."
TEMP_DEX_WORK_DIR="$TEMP_BUILD_DATA_DIR/temp_dex_work"
mkdir -p "$TEMP_DEX_WORK_DIR"
"$DX" --output "$TEMP_DEX_WORK_DIR" "$ABS_TEMP_JAR_FILE" --min-api "$MIN_SDK" || { rm -rf "$TEMP_DEX_WORK_DIR"; echo "Error: D8/DX failed." ; exit 1; }
mv "$TEMP_DEX_WORK_DIR/classes.dex" "$DEX_FILE"
rm -rf "$TEMP_DEX_WORK_DIR"

download_bundletool
build_aab

build_apk

rm -f "$RES_DIR/temp_icon_file_base"
rm -rf "$TEMP_ROOT_DIR"

publish

echo "BUILD COMPLETE for $DISPLAY_NAME. Both files are in $OUTPUT_DIR/."
echo "APK Output: $DEBUG_APK_FILE"
echo "AAB Output: $AAB_SIGNED_FILE"
echo "INSTALL: adb install -r -t $DEBUG_APK_FILE"
echo "UNINSTALL: adb uninstall $PACKAGE_NAME"
