# Build configuration, CLI parsing, and derived paths.

# Initializes build defaults, parses public arguments, and derives build paths.
# @param $@ Forwarded build arguments.
# @return None.
configure_build () {
    DISPLAY_NAME="${DISPLAY_NAME:-My App}"
    PROJECT_NAME="${PROJECT_NAME:-myapp}"
    OUTPUT_PATH="${OUTPUT_PATH:-}"
    PACKAGE_NAME="${PACKAGE_NAME:-com.kaisarcode.myapp}"
    WEBVIEW_URL="${WEBVIEW_URL:-https://google.com/}"
    ICON_SOURCE_FILE="${ICON_SOURCE_FILE:-$KCAPK_SRC_DIR/assets/icon.svg}"
    ICON_BACKGROUND="${ICON_BACKGROUND:-#000000}"
    BACKGROUND="${BACKGROUND:-#101010}"
    TRUSTED_ORIGINS="${TRUSTED_ORIGINS:-}"
    IS_FULLSCREEN="${IS_FULLSCREEN:-false}"
    VERSION_CODE="${VERSION_CODE:-1}"
    VERSION_NAME="${VERSION_NAME:-1.0}"
    TARGET_SDK="36"
    MIN_SDK="24"
    BUILD_TOOLS_VERSION="36.0.0"
    PLATFORM_VERSION="android-$TARGET_SDK"
    CMDLINE_TOOLS_VERSION="11076708"
    DEFAULT_CMDLINE_PREFIX="commandlinetools"

    if [ -z "$CMDLINE_TOOLS_URL" ]; then
        case "$(uname -s)" in
            Darwin)
                CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/${DEFAULT_CMDLINE_PREFIX}-mac-${CMDLINE_TOOLS_VERSION}_latest.zip"
                ;;
            *)
                CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/${DEFAULT_CMDLINE_PREFIX}-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
                ;;
        esac
    fi

    SDK_ZIP="${SDK_ZIP:-${DEFAULT_CMDLINE_PREFIX}.zip}"

    if [ -n "$ANDROID_SDK_ROOT" ]; then
        SDK_BASE="$ANDROID_SDK_ROOT"
    elif [ -n "$ANDROID_HOME" ]; then
        SDK_BASE="$ANDROID_HOME"
    else
        SDK_BASE="$HOME/android-sdk"
    fi

    ANDROID_SDK_ROOT="$SDK_BASE"
    if [ -z "$ANDROID_HOME" ]; then
        ANDROID_HOME="$ANDROID_SDK_ROOT"
    fi

    CLEAN_ALL=false
    RELEASE_MODE=false
    EXECUTABLES=""
    PERMISSIONS=""
    SHARE_TARGETS=""
    CLI_TRUSTED_ORIGINS_SET=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --display-name)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --display-name requires a value." >&2; exit 1; }
                DISPLAY_NAME="$1"
                shift
                ;;
            --project-name)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --project-name requires a value." >&2; exit 1; }
                PROJECT_NAME="$1"
                shift
                ;;
            --output-path)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --output-path requires a value." >&2; exit 1; }
                OUTPUT_PATH="$1"
                shift
                ;;
            --package-name)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --package-name requires a value." >&2; exit 1; }
                PACKAGE_NAME="$1"
                shift
                ;;
            --webview-url)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --webview-url requires a value." >&2; exit 1; }
                WEBVIEW_URL="$1"
                shift
                ;;
            --icon)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --icon requires a path or URL." >&2; exit 1; }
                ICON_SOURCE_FILE="$1"
                shift
                ;;
            --icon-background)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --icon-background requires a color." >&2; exit 1; }
                ICON_BACKGROUND="$1"
                shift
                ;;
            --background)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --background requires a color." >&2; exit 1; }
                BACKGROUND="$1"
                shift
                ;;
            --trusted-origin)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --trusted-origin requires an origin." >&2; exit 1; }
                if ! $CLI_TRUSTED_ORIGINS_SET; then
                    TRUSTED_ORIGINS=""
                    CLI_TRUSTED_ORIGINS_SET=true
                fi
                if [ -n "$TRUSTED_ORIGINS" ]; then
                    TRUSTED_ORIGINS="$TRUSTED_ORIGINS
$1"
                else
                    TRUSTED_ORIGINS="$1"
                fi
                shift
                ;;
            --permission)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --permission requires a value." >&2; exit 1; }
                if [ -n "$PERMISSIONS" ]; then
                    PERMISSIONS="$PERMISSIONS
$1"
                else
                    PERMISSIONS="$1"
                fi
                shift
                ;;
            --share-target)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --share-target requires a MIME type." >&2; exit 1; }
                if [ -n "$SHARE_TARGETS" ]; then
                    SHARE_TARGETS="$SHARE_TARGETS
$1"
                else
                    SHARE_TARGETS="$1"
                fi
                shift
                ;;
            --fullscreen)
                IS_FULLSCREEN=true
                shift
                ;;
            --version-code)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --version-code requires a value." >&2; exit 1; }
                VERSION_CODE="$1"
                shift
                ;;
            --version-name)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --version-name requires a value." >&2; exit 1; }
                VERSION_NAME="$1"
                shift
                ;;
            --clean)
                CLEAN_ALL=true
                echo "Argument --clean detected. Forcing KeyStore and temporary files deletion."
                shift
                ;;
            --release)
                RELEASE_MODE=true
                echo "Argument --release detected. Preparing for DUAL AAB/APK build."
                shift
                ;;
            --exec)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --exec requires a path." >&2; exit 1; }
                if [ -n "$EXECUTABLES" ]; then
                    EXECUTABLES="$EXECUTABLES
$1"
                else
                    EXECUTABLES="$1"
                fi
                shift
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                exit 1
                ;;
        esac
    done

    if [ -n "$BACKGROUND" ]; then
        if ! printf '%s\n' "$BACKGROUND" | grep -Eq '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$'; then
            printf 'Error: --background must use \043RRGGBB or \043AARRGGBB.\n' >&2
            exit 1
        fi
    fi

    BASE_DIR="${OUTPUT_PATH:-./build/$PROJECT_NAME}"
    PACKAGE_SUBPATH="$(echo "$PACKAGE_NAME" | tr . /)"
    SRC_DIR="$BASE_DIR/src/main/java/$PACKAGE_SUBPATH"
    RES_DIR="$BASE_DIR/res"
    LAYOUT_DIR="$RES_DIR/layout"
    VALUES_DIR="$RES_DIR/values"
    ASSETS_DIR="$BASE_DIR/assets"

    MIPMAP_MDPI_DIR="$RES_DIR/mipmap-mdpi"
    MIPMAP_HDPI_DIR="$RES_DIR/mipmap-hdpi"
    MIPMAP_XHDPI_DIR="$RES_DIR/mipmap-xhdpi"
    MIPMAP_XXHDPI_DIR="$RES_DIR/mipmap-xxhdpi"
    MIPMAP_XXXHDPI_DIR="$RES_DIR/mipmap-xxxhdpi"
    MIPMAP_ANYDPI_V26_DIR="$RES_DIR/mipmap-anydpi-v26"

    OUTPUT_DIR="$BASE_DIR/bin"
    TEMP_ROOT_DIR="$BASE_DIR/temp"
    TEMP_CLASSES_DIR="$TEMP_ROOT_DIR/classes"
    FLAT_RES_DIR="$TEMP_ROOT_DIR/resources"
    TEMP_BUILD_DATA_DIR="$TEMP_ROOT_DIR/build_data"
    AAB_TEMP_DIR="$TEMP_ROOT_DIR/aab_work"
    NATIVE_LIBS_DIR="$TEMP_ROOT_DIR/native_libs"

    R_PACKAGE_DIR="$TEMP_CLASSES_DIR/$PACKAGE_SUBPATH"
    TEMP_JAR_FILE="$TEMP_BUILD_DATA_DIR/classes.jar"
    DEX_FILE="$TEMP_BUILD_DATA_DIR/classes.dex"

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
            echo "Old debug KeyStore deleted: $DEBUG_KEYSTORE"
        else
            echo "Debug KeyStore not found. Skipping deletion."
        fi
    fi
}
