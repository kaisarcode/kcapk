#!/bin/sh
# build.sh
# Summary: Manifest-driven Android thin-client APK/AAB builder.
#          Generates the common kclib bridge, packages native dependencies,
#          and publishes the app manifest, assets, and APK to ../dist/<project>/.
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
                        s = substr(s, RLENGTH + 2)
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
ICON_BACKGROUND="$(cfg icon_background)"
ICON_BACKGROUND="${ICON_BACKGROUND:-#1a1a1a}"
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
APP_MANIFEST_URL="$(cfg app_manifest_url)"
APP_MANIFEST_URL="${APP_MANIFEST_URL:-https://kaisarcode.com/kcapk/dist/$PROJECT_NAME/manifest.json}"
RELEASE_KEYSTORE="$(cfg release_keystore)"
RELEASE_KEY_ALIAS="$(cfg release_key_alias)"
RELEASE_STORE_PASS="$(cfg release_store_pass)"
RELEASE_KEY_PASS="$(cfg release_key_pass)"
TRUSTED_ORIGINS="$(cfg trusted_origins)"
TRUSTED_ORIGINS="${TRUSTED_ORIGINS:-}"
WEBVIEW_DEBUG="$(cfg webview_debug)"
WEBVIEW_DEBUG="${WEBVIEW_DEBUG:-false}"

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
NATIVE_SOURCE_DIR="$APP_DIR/native"
NATIVE_C_SOURCE="$NATIVE_SOURCE_DIR/bridge.c"
COMMON_ASSETS_DIR="assets"
PUBLISH_DIR="../dist/$PROJECT_NAME"

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
KCLIB_WORK_DIR="$TEMP_ROOT_DIR/kclib"
NATIVE_PACKAGE_DIR="$TEMP_ROOT_DIR/native_package"

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
NATIVE_BRIDGE_FILE="$SRC_DIR/NativeBridge.java"
NATIVE_DISPATCHER_FILE="$BASE_DIR/native-bridge.c"
NATIVE_FACADE_FILE="$ASSETS_DIR/www/js/native-bridge.js"
BRIDGE_FUNCTIONS_FILE="$KCLIB_WORK_DIR/functions.tsv"
BRIDGE_CASES_FILE="$KCLIB_WORK_DIR/cases.c"

KCLIB_DIST_DIR="$(cfg kclib_dist_dir)"
KCLIB_DIST_DIR="${KCLIB_DIST_DIR:-../../kclib/dist}"
ANDROID_NDK_ROOT_CFG="$(cfg android_ndk_root)"
if [ -n "$ANDROID_NDK_ROOT_CFG" ]; then
    ANDROID_NDK_ROOT="$ANDROID_NDK_ROOT_CFG"
elif [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    ANDROID_NDK_ROOT="$HOME/.local/share/android-sdk/ndk/27.2.12479018"
fi
NDK_TOOLCHAIN="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64"

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

# Rejects a manifest dependency name that cannot safely name a kclib package.
# @param name Candidate kclib name.
# @return 0 when the name is lowercase alphanumeric with optional underscores.
valid_kclib_name () {
    case "$1" in
        *[!abcdefghijklmnopqrstuvwxyz0123456789_]*|'') return 1 ;;
        *) return 0 ;;
    esac
}

# Prepares declared kclib headers and Android shared libraries.
# @return 0 when every declared dependency is ready.
prepare_kclib_dependencies () {
    [ -d "$KCLIB_DIST_DIR" ] || { echo "error: kclib dist directory not found: $KCLIB_DIST_DIR" >&2; exit 1; }

    for DEP in $KCLIB_DEPS; do
        valid_kclib_name "$DEP" || { echo "error: invalid kclib name: $DEP" >&2; exit 1; }
    done

    for DEP in $KCLIB_DEPS; do
        DEP_DIST_DIR="$KCLIB_DIST_DIR/$DEP.c"
        DEP_ZIP="$DEP_DIST_DIR/source.zip"
        DEP_WORK_DIR="$KCLIB_WORK_DIR/$DEP"
        DEP_HEADER_DIR="$DEP_WORK_DIR/$DEP.c/src"

        [ -f "$DEP_ZIP" ] || { echo "error: kclib source package not found: $DEP_ZIP" >&2; exit 1; }
        unzip -q "$DEP_ZIP" -d "$DEP_WORK_DIR" || { echo "error: failed to extract: $DEP_ZIP" >&2; exit 1; }
        DEP_HEADER="$DEP_HEADER_DIR/lib$DEP.h"
        [ -f "$DEP_HEADER" ] || { echo "error: kclib public header not found: $DEP_HEADER" >&2; exit 1; }

        for KCLIB_ARCH in aarch64 armv7; do
            case "$KCLIB_ARCH" in
                aarch64) ANDROID_ABI="arm64-v8a" ;;
                armv7) ANDROID_ABI="armeabi-v7a" ;;
            esac
            DEP_SO="$DEP_DIST_DIR/$KCLIB_ARCH/android/lib$DEP.so"
            [ -f "$DEP_SO" ] || { echo "error: kclib Android library not found: $DEP_SO" >&2; exit 1; }
            mkdir -p "$NATIVE_PACKAGE_DIR/lib/$ANDROID_ABI"
            cp "$DEP_SO" "$NATIVE_PACKAGE_DIR/lib/$ANDROID_ABI/lib$DEP.so"
        done

    done
}

# Discovers selected public functions through the NDK Clang AST.
# @return 0 when every selected declaration was discovered.
discover_kclib_functions () {
    : > "$BRIDGE_FUNCTIONS_FILE"
    [ -x "$NDK_TOOLCHAIN/bin/aarch64-linux-android$MIN_SDK-clang" ] || { echo "error: Android NDK compiler not found under: $NDK_TOOLCHAIN" >&2; exit 1; }
    for DEP in $KCLIB_DEPS; do
        DEP_HEADER="$KCLIB_WORK_DIR/$DEP/$DEP.c/src/lib$DEP.h"
        DEP_AST="$KCLIB_WORK_DIR/$DEP.ast"
        "$NDK_TOOLCHAIN/bin/aarch64-linux-android$MIN_SDK-clang" -fsyntax-only -I"$KCLIB_WORK_DIR/$DEP/$DEP.c/src" -Xclang -ast-dump=json -x c "$DEP_HEADER" > "$DEP_AST" 2>/dev/null || { echo "error: cannot inspect public header: $DEP_HEADER" >&2; exit 1; }
        jq -c --arg library "$DEP" --arg source "$KCLIB_WORK_DIR/$DEP/$DEP.c/src/" '
            def clean: gsub("\\b(const|volatile|restrict)\\b"; "") | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");
            def aliases: reduce (.. | objects | select(.kind? == "TypedefDecl" and .name? and .type? and .type.qualType?)) as $d ({}; .[$d.name] = ($d.type.desugaredQualType // $d.type.qualType));
            def type_model($types):
                . as $source | ($source | clean) as $q
                | if ($q | test("\\(\\*\\)")) then
                    ($source | capture("^(?<return>.*) \\(\\*\\)\\((?<parameters>.*)\\)$")) as $callback
                    | {qual: $source, canonical: $q, pointer_depth: 1, const: false, category: "callback", callback: {return: ($callback.return | type_model($types)), parameters: ($callback.parameters | if . == "void" or . == "" then [] else split(", ") | map(type_model($types)) end)}}
                else
                    ([$q | scan("\\*")] | length) as $depth
                    | ($q | sub("\\*.*$"; "") | clean) as $base
                    | ($types[$base] // $base) as $canonical_base
                    | {qual: $source, canonical: ($canonical_base + (" *" * $depth)), pointer_depth: $depth, const: ($source | test("(^| )const ")), base: $canonical_base}
                    | if $depth == 0 then .category = (if .base == "void" then "void" elif .base == "_Bool" or .base == "bool" then "bool" elif (.base | test("^(signed )?(char|short|int|long|long long)$")) then "signed" elif (.base | test("^unsigned (char|short|int|long|long long)$")) then "unsigned" elif .base == "float" or .base == "double" then "float" elif (.base | startswith("enum ")) then "enum" else "value" end)
                    elif $depth == 1 and .base == "char" then .category = (if .const then "string" else "string_out" end)
                    elif $depth == 1 and .base == "void" then .category = "void_pointer"
                    elif $depth == 1 then .category = "opaque"
                    elif $depth == 2 then .category = "opaque_out"
                    else .category = "unsupported" end
                end;
            aliases as $types
            | .. | objects | select(.kind? == "FunctionDecl" and .name? and .loc != null)
            | select((.loc.file? == null and (.loc.includedFrom? == null)) or (.loc.file? != null and (.loc.file | startswith($source))))
            | (.type.qualType | capture("^(?<return>.*) \\(").return | type_model($types)) as $return_model
            | {library: $library, name: .name, result: $return_model, parameters: [.inner[]? | select(.kind == "ParmVarDecl") | (.type.desugaredQualType // .type.qualType | type_model($types))]}
        ' "$DEP_AST" >> "$BRIDGE_FUNCTIONS_FILE" || { echo "error: cannot read public declarations: $DEP_HEADER" >&2; exit 1; }
    done
}

# Stops generation for an unsupported typed declaration.
# @param library Manifest-selected library name.
# @param name Public function name.
# @param position Parameter or return position.
# @param type Unsupported canonical type.
# @return Does not return successfully.
bridge_unsupported_type () {
    echo "error: unsupported bridge type: library=$1 function=$2 $3 type=$4" >&2
    exit 1
}

# Emits one typed call from structured Clang declaration metadata.
# @param declaration One JSON declaration record.
# @return 0 when the declaration is supported.
emit_bridge_case () {
    declaration="$1"
    library=$(printf '%s' "$declaration" | jq -r '.library')
    name=$(printf '%s' "$declaration" | jq -r '.name')
    result_type=$(printf '%s' "$declaration" | jq -r '.result.qual')
    result_category=$(printf '%s' "$declaration" | jq -r '.result.category')
    case "$result_category" in void|bool|signed|unsigned|float|enum|string|opaque|value) ;; *) bridge_unsupported_type "$library" "$name" return "$(printf '%s' "$declaration" | jq -r '.result.canonical')" ;; esac
    count=$(printf '%s' "$declaration" | jq '.parameters | length')
    declarations='' checks='' assignments='' allocations='' post_call='' call_args='' cleanup='' js_index=0
    output_kind='' output_index='' callback_index=''
    index=0
    while [ "$index" -lt "$count" ]; do
        parameter=$(printf '%s' "$declaration" | jq -c ".parameters[$index]")
        type=$(printf '%s' "$parameter" | jq -r '.qual')
        canonical=$(printf '%s' "$parameter" | jq -r '.canonical')
        category=$(printf '%s' "$parameter" | jq -r '.category')
        case "$category" in
            signed|enum|bool) declarations="$declarations        int64_t raw_$index = 0;\n        $type arg_$index;\n"; checks="$checks !bridge_json_i64(args, $js_index, &raw_$index) ||"; assignments="$assignments        arg_$index = ($type)raw_$index;\n"; call_args="$call_args${call_args:+, }arg_$index"; js_index=$((js_index + 1)) ;;
            unsigned) declarations="$declarations        uint64_t raw_$index = 0;\n        $type arg_$index;\n"; checks="$checks !bridge_json_u64(args, $js_index, &raw_$index) ||"; assignments="$assignments        arg_$index = ($type)raw_$index;\n"; call_args="$call_args${call_args:+, }arg_$index"; js_index=$((js_index + 1)) ;;
            float) declarations="$declarations        double raw_$index = 0;\n        $type arg_$index;\n"; checks="$checks !bridge_json_double(args, $js_index, &raw_$index) ||"; assignments="$assignments        arg_$index = ($type)raw_$index;\n"; call_args="$call_args${call_args:+, }arg_$index"; js_index=$((js_index + 1)) ;;
            string) declarations="$declarations        char *arg_$index = NULL;\n"; checks="$checks !bridge_json_string(args, $js_index, &arg_$index) ||"; cleanup="$cleanup        free(arg_$index);\n"; call_args="$call_args${call_args:+, }arg_$index"; js_index=$((js_index + 1)) ;;
            opaque) declarations="$declarations        uint64_t handle_$index = 0;\n        $type arg_$index;\n"; checks="$checks !bridge_json_u64(args, $js_index, &handle_$index) || (arg_$index = ($type)bridge_handle_get(handle_$index)) == NULL ||"; call_args="$call_args${call_args:+, }arg_$index"; js_index=$((js_index + 1)) ;;
            opaque_out) [ -z "$output_kind" ] || bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical"; pointee=$(printf '%s' "$type" | sed 's/[[:space:]]*\*\([[:space:]]*\)\?$//'); declarations="$declarations        $pointee arg_$index = NULL;\n        uint64_t out_$index = 0;\n"; post_call="$post_call        out_$index = bridge_handle_put(arg_$index);\n"; call_args="$call_args${call_args:+, }&arg_$index"; output_kind=handle; output_index=$index ;;
            string_out) [ "$index" -lt $((count - 1)) ] || bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical"; [ -z "$output_kind" ] || bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical"; next_category=$(printf '%s' "$declaration" | jq -r ".parameters[$((index + 1))].category"); [ "$next_category" = unsigned ] || bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical"; declarations="$declarations        char *arg_$index = NULL;\n"; allocations="$allocations        if (raw_$((index + 1)) == 0 || raw_$((index + 1)) > 65536) { strcpy(output, \"{\\\"error\\\":\\\"invalid arguments\\\"}\"); return bridge_response(env, output); }\n        arg_$index = calloc((size_t)raw_$((index + 1)), 1);\n        if (arg_$index == NULL) { strcpy(output, \"{\\\"error\\\":\\\"out of memory\\\"}\"); return bridge_response(env, output); }\n"; cleanup="$cleanup        free(arg_$index);\n"; call_args="$call_args${call_args:+, }arg_$index"; output_kind=string; output_index=$index ;;
            callback) callback_return=$(printf '%s' "$parameter" | jq -r '.callback.return.category'); callback_first=$(printf '%s' "$parameter" | jq -r '.callback.parameters[0].category'); callback_second=$(printf '%s' "$parameter" | jq -r '.callback.parameters[1].category'); callback_params=$(printf '%s' "$parameter" | jq -r '.callback.parameters | length'); userdata_category=$(printf '%s' "$declaration" | jq -r ".parameters[$((index + 1))].category"); if [ "$callback_return" != void ] || [ "$callback_params" -ne 2 ] || [ "$callback_first" != string ] || [ "$callback_second" != void_pointer ] || [ "$userdata_category" != void_pointer ]; then bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical"; fi; [ -z "$output_kind" ] || bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical"; declarations="$declarations        bridge_callback_list_t list_$index = {{0}, 0, 0};\n"; call_args="$call_args${call_args:+, }bridge_callback_collect, &list_$index"; output_kind=items; output_index=$index; callback_index=$js_index; index=$((index + 1)) ;;
            void_pointer) bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical" ;;
            *) bridge_unsupported_type "$library" "$name" "parameter $index" "$canonical" ;;
        esac
        index=$((index + 1))
    done
    if [ -n "$output_kind" ] && [ "$result_category" != bool ] && [ "$result_category" != signed ] && [ "$result_category" != unsigned ] && [ "$result_category" != float ] && [ "$result_category" != enum ]; then
        bridge_unsupported_type "$library" "$name" return "$result_type with output parameter"
    fi
    cat >> "$BRIDGE_CASES_FILE" <<EOF
    if (strcmp(library, "$library") == 0 && strcmp(name, "$name") == 0) {
$(printf '%b' "$declarations")        if (${checks:-0 || } !bridge_json_done(args, $js_index)) { strcpy(output, "{\\"error\\":\\"invalid arguments\\"}");
$(printf '%b' "$cleanup")            return bridge_response(env, output); }
EOF
    printf '%b' "$assignments$allocations" >> "$BRIDGE_CASES_FILE"
    if [ "$result_category" = void ]; then
        printf '        %s(%s);\n' "$name" "$call_args" >> "$BRIDGE_CASES_FILE"
        printf '        bridge_result_null(output, sizeof(output));\n' >> "$BRIDGE_CASES_FILE"
    elif [ "$result_category" = string ]; then
        printf '        %s result = %s(%s);\n        bridge_result_string(output, sizeof(output), result);\n' "$result_type" "$name" "$call_args" >> "$BRIDGE_CASES_FILE"
    elif [ "$result_category" = opaque ]; then
        printf '        %s result = %s(%s);\n        bridge_result_handle(output, sizeof(output), bridge_handle_put(result));\n' "$result_type" "$name" "$call_args" >> "$BRIDGE_CASES_FILE"
    elif [ "$result_category" = value ]; then
        printf '        %s *result = malloc(sizeof(*result));\n        if (result == NULL) { strcpy(output, "{\\"error\\":\\"out of memory\\"}"); return bridge_response(env, output); }\n        *result = %s(%s);\n        bridge_result_handle(output, sizeof(output), bridge_handle_put(result));\n' "$result_type" "$name" "$call_args" >> "$BRIDGE_CASES_FILE"
    else
        printf '        %s result = %s(%s);\n' "$result_type" "$name" "$call_args" >> "$BRIDGE_CASES_FILE"
        printf '%b' "$post_call" >> "$BRIDGE_CASES_FILE"
        case "$output_kind" in
            handle) printf '        bridge_result_number_handle(output, sizeof(output), (double)result, out_%s);\n' "$output_index" >> "$BRIDGE_CASES_FILE" ;;
            string) printf '        bridge_result_number_string(output, sizeof(output), (double)result, arg_%s);\n' "$output_index" >> "$BRIDGE_CASES_FILE" ;;
            items) printf '        bridge_result_number_items(output, sizeof(output), (double)result, list_%s.text);\n' "$output_index" >> "$BRIDGE_CASES_FILE" ;;
            '') printf '        bridge_result_number(output, sizeof(output), (double)result);\n' >> "$BRIDGE_CASES_FILE" ;;
        esac
    fi
    printf '%b' "$cleanup" >> "$BRIDGE_CASES_FILE"
    cat >> "$BRIDGE_CASES_FILE" <<'EOF'
        return bridge_response(env, output);
    }
EOF
    BRIDGE_FUNCTION_ROWS="$BRIDGE_FUNCTION_ROWS
    {\"$library\", \"$name\"},"
    if [ -n "$callback_index" ]; then
        BRIDGE_FACADE_ROWS="$BRIDGE_FACADE_ROWS
    bridge.$library = bridge.$library || {};
    bridge.$library.$name = function () { var values = Array.prototype.slice.call(arguments); var callback = values.splice($callback_index, 1)[0]; if (typeof callback !== \"function\") return Promise.reject(new Error(\"invalid callback\")); return call(\"$library\", \"$name\", values).then(function (value) { value.items.forEach(callback); return Object.prototype.hasOwnProperty.call(value, \"out\") ? value.out : value.result; }); };"
    else
        BRIDGE_FACADE_ROWS="$BRIDGE_FACADE_ROWS
    bridge.$library = bridge.$library || {};
    bridge.$library.$name = function () { var values = Array.prototype.slice.call(arguments); return call(\"$library\", \"$name\", values).then(function (value) { return Object.prototype.hasOwnProperty.call(value, \"out\") ? value.out : value.result; }); };"
    fi
}

# Generates JavaScript, JNI, and typed C calls from the discovered declarations.
# @return 0 when generated sources are complete.
generate_common_bridge () {
    PROJECT_NATIVE_LIBRARY_LOAD=""
    [ -f "$NATIVE_C_SOURCE" ] && PROJECT_NATIVE_LIBRARY_LOAD='        System.loadLibrary("projectbridge");'
    : > "$BRIDGE_CASES_FILE"
    BRIDGE_HEADERS=""
    BRIDGE_LIBRARIES=""
    BRIDGE_FUNCTION_ROWS=""
    BRIDGE_FACADE_ROWS=""
    for DEP in $KCLIB_DEPS; do
        BRIDGE_HEADERS="$BRIDGE_HEADERS
$(printf '%s\n' "#include \"lib$DEP.h\"")"
        BRIDGE_LIBRARIES="$BRIDGE_LIBRARIES
    \"$DEP\","
    done
    while IFS= read -r declaration; do
        [ -n "$declaration" ] || continue
        emit_bridge_case "$declaration"
    done < "$BRIDGE_FUNCTIONS_FILE"
    cat <<EOF > "$NATIVE_BRIDGE_FILE"
package $PACKAGE_NAME;

import android.content.Context;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

public final class NativeBridge {
    static {
        System.loadLibrary("kcapkbridge");
$PROJECT_NATIVE_LIBRARY_LOAD
    }

    private final JSBridge jsBridge;

    public NativeBridge(Context context, WebView webView, JSBridge jsBridge) {
        this.jsBridge = jsBridge;
    }

    @JavascriptInterface
    public String dispatch(String token, String library, String function, String args) {
        if (!jsBridge.isTrustedCall(token)) {
            return "{\"error\":\"unauthorized\"}";
        }
        if (library == null || function == null) {
            return "{\"error\":\"invalid arguments\"}";
        }
        return nativeDispatch(library, function, args == null ? "[]" : args);
    }

    @JavascriptInterface
    public String queryLibraries(String token) {
        return jsBridge.isTrustedCall(token) ? nativeQueryLibraries() : "[]";
    }

    @JavascriptInterface
    public String queryFunctions(String token, String library) {
        return jsBridge.isTrustedCall(token) && library != null ? nativeQueryFunctions(library) : "[]";
    }

    private static native String nativeDispatch(String library, String function, String args);
    private static native String nativeQueryLibraries();
    private static native String nativeQueryFunctions(String library);
}
EOF
    cat <<EOF > "$NATIVE_DISPATCHER_FILE"
/**
 * native-bridge.c - Generated typed kclib JNI bridge.
 * Summary: Invokes Clang-discovered functions without inferring handle lifetime.
 *
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: https://www.gnu.org/licenses/gpl-3.0.html
 */

#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
$BRIDGE_HEADERS

typedef struct {
    const char *library;
    const char *name;
} bridge_function_t;

static const char *const bridge_libraries[] = {$BRIDGE_LIBRARIES
    NULL
};
static const bridge_function_t bridge_functions[] = {$BRIDGE_FUNCTION_ROWS
    {NULL, NULL}
};
static void *bridge_handles[256];

typedef struct {
    char text[16384];
    size_t written;
    int count;
} bridge_callback_list_t;

/**
 * Collects one string callback value for a generated result.
 * @param value Callback string value.
 * @param userdata Generated callback collection.
 * @return None.
 */
static void bridge_callback_collect(const char *value, void *userdata) {
    bridge_callback_list_t *list = userdata;
    int result;
    if (list == NULL || value == NULL || list->written >= sizeof(list->text)) return;
    result = snprintf(list->text + list->written, sizeof(list->text) - list->written, "%s%c%s%c", list->count++ == 0 ? "" : ",", 34, value, 34);
    if (result >= 0 && (size_t)result < sizeof(list->text) - list->written) list->written += (size_t)result;
}

/**
 * Stores one native value behind a generated opaque handle.
 * @param value Native value to store.
 * @return Nonzero handle or zero when storage is unavailable.
 */
static uint64_t bridge_handle_put(void *value) {
    size_t index;
    if (value == NULL) return 0;
    for (index = 1; index < sizeof(bridge_handles) / sizeof(bridge_handles[0]); index++) {
        if (bridge_handles[index] == NULL) {
            bridge_handles[index] = value;
            return index;
        }
    }
    return 0;
}

/**
 * Resolves one generated opaque handle.
 * @param value Opaque handle value.
 * @return Stored native value or NULL.
 */
static void *bridge_handle_get(uint64_t value) {
    if (value == 0 || value >= sizeof(bridge_handles) / sizeof(bridge_handles[0])) return NULL;
    return bridge_handles[value];
}

/**
 * Creates a Java string from one JSON response.
 * @param env JNI environment.
 * @param text JSON response text.
 * @return New Java string.
 */
static jstring bridge_response(JNIEnv *env, const char *text) {
    return (*env)->NewStringUTF(env, text);
}

/**
 * Tests whether JSON input is an empty argument array.
 * @param text JSON text.
 * @return Nonzero when the array is empty.
 */
static int bridge_json_empty(const char *text) {
    while (*text == ' ' || *text == '\\t' || *text == '\\n' || *text == '\\r') text++;
    return text[0] == '[' && text[1] == ']' && text[2] == '\\0';
}

/**
 * Locates one positional scalar or string token in a JSON array.
 * @param text JSON array text.
 * @param index Requested value position.
 * @param start Receives token start.
 * @param end Receives token end.
 * @return Nonzero when the requested token is present and complete.
 */
static int bridge_json_value(const char *text, int index, const char **start, const char **end) {
    const char *p = text;
    int current = 0;
    while (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r') p++;
    if (*p++ != '[') return 0;
    for (;;) {
        const char *token;
        while (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r') p++;
        if (*p == ']') return 0;
        token = p;
        if (*p == '\"') {
            p++;
            while (*p && *p != '\"') {
                if (*p++ == '\\\\' && *p) p++;
            }
            if (*p++ != '\"') return 0;
        } else {
            while (*p && *p != ',' && *p != ']') p++;
            if (p == token) return 0;
        }
        if (current == index) {
            const char *limit = p;
            while (limit > token && (limit[-1] == ' ' || limit[-1] == '\\t' || limit[-1] == '\\n' || limit[-1] == '\\r')) limit--;
            *start = token;
            *end = limit;
            return 1;
        }
        while (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r') p++;
        if (*p++ != ',') return 0;
        current++;
    }
}

/**
 * Reads one string argument from a JSON array.
 * @param text JSON text.
 * @param index Argument position.
 * @param out Receives allocated text.
 * @return Nonzero on success.
 */
static int bridge_json_string(const char *text, int index, char **out) {
    const char *start;
    const char *end;
    size_t size = 0;
    char *value;
    if (!bridge_json_value(text, index, &start, &end) || end - start < 2 || *start++ != '\"' || end[-1] != '\"') return 0;
    end--;
    value = malloc((size_t)(end - start) + 1);
    if (value == NULL) return 0;
    while (start < end) {
        if (*start == '\\\\' && start + 1 < end) start++;
        value[size++] = *start++;
    }
    value[size] = '\\0';
    *out = value;
    return 1;
}

/**
 * Reads one unsigned integer from a JSON array.
 * @param text JSON text.
 * @param index Argument position.
 * @param out Receives the integer.
 * @return Nonzero on success.
 */
static int bridge_json_u64(const char *text, int index, uint64_t *out) {
    const char *start;
    const char *limit;
    char *end;
    if (!bridge_json_value(text, index, &start, &limit)) return 0;
    *out = strtoull(start, &end, 10);
    return end != start && end == limit;
}

/**
 * Reads one signed integer from a JSON array.
 * @param text JSON text.
 * @param index Argument position.
 * @param out Receives the integer.
 * @return Nonzero on success.
 */
static int bridge_json_i64(const char *text, int index, int64_t *out) {
    const char *start;
    const char *limit;
    char *end;
    if (!bridge_json_value(text, index, &start, &limit)) return 0;
    *out = strtoll(start, &end, 10);
    return end != start && end == limit;
}

/**
 * Reads one floating-point value from a JSON array.
 * @param text JSON text.
 * @param index Argument position.
 * @param out Receives the value.
 * @return Nonzero on success.
 */
static int bridge_json_double(const char *text, int index, double *out) {
    const char *start;
    const char *limit;
    char *end;
    if (!bridge_json_value(text, index, &start, &limit)) return 0;
    *out = strtod(start, &end);
    return end != start && end == limit;
}

/**
 * Verifies the number of JSON array values.
 * @param text JSON text.
 * @param count Expected value count.
 * @return Nonzero on success.
 */
static int bridge_json_done(const char *text, int count) {
    const char *p = text;
    int seen = 0;
    while (*p && *p != '[') p++;
    if (*p++ != '[') return 0;
    while (*p && *p != ']') {
        if (*p == '\"') { p++; while (*p && *p != '\"') { if (*p++ == '\\\\' && *p) p++; } if (*p) p++; }
        else p++;
        if (*p == ',') seen++;
    }
    return *p == ']' && (count == 0 || seen == count - 1);
}

/**
 * Writes one numeric JSON response.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @param value Numeric result.
 * @return None.
 */
static void bridge_result_number(char *output, size_t cap, double value) {
    snprintf(output, cap, "{\"result\":%.17g}", value);
}

/**
 * Writes a numeric result and an opaque output handle.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @param value Numeric result.
 * @param handle Opaque output handle.
 * @return None.
 */
static void bridge_result_number_handle(char *output, size_t cap, double value, uint64_t handle) {
    snprintf(output, cap, "{\"result\":%.17g,\"out\":%llu}", value, (unsigned long long)handle);
}

/**
 * Writes one null JSON response.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @return None.
 */
static void bridge_result_null(char *output, size_t cap) {
    snprintf(output, cap, "{\"result\":null}");
}

/**
 * Writes one opaque-handle JSON response.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @param value Opaque handle.
 * @return None.
 */
static void bridge_result_handle(char *output, size_t cap, uint64_t value) {
    snprintf(output, cap, "{\"result\":%llu}", (unsigned long long)value);
}

/**
 * Writes one escaped string JSON response.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @param value String result.
 * @return None.
 */
static void bridge_result_string(char *output, size_t cap, const char *value) {
    size_t written = 0;
    const unsigned char *p = (const unsigned char *)(value == NULL ? "" : value);
    written += (size_t)snprintf(output + written, cap - written, "{\"result\":\"");
    while (*p && written + 8 < cap) {
        if (*p == '\\"' || *p == '\\\\') output[written++] = '\\\\';
        output[written++] = (char)*p++;
    }
    snprintf(output + written, cap - written, "\"}");
}

/**
 * Writes a numeric result and an escaped output string.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @param value Numeric result.
 * @param text Output string.
 * @return None.
 */
static void bridge_result_number_string(char *output, size_t cap, double value, const char *text) {
    size_t written = (size_t)snprintf(output, cap, "{\"result\":%.17g,\"out\":\"", value);
    const unsigned char *p = (const unsigned char *)(text == NULL ? "" : text);
    while (*p && written + 8 < cap) {
        if (*p == '\\"' || *p == '\\\\') output[written++] = '\\\\';
        output[written++] = (char)*p++;
    }
    snprintf(output + written, cap - written, "\"}");
}

/**
 * Writes a numeric result and collected callback items.
 * @param output Response buffer.
 * @param cap Response buffer capacity.
 * @param value Numeric result.
 * @param items JSON item values.
 * @return None.
 */
static void bridge_result_number_items(char *output, size_t cap, double value, const char *items) {
    snprintf(output, cap, "{\"result\":%.17g,\"items\":[%s]}", value, items == NULL ? "" : items);
}

/**
 * Lists manifest-selected libraries for the internal transport.
 * @param env JNI environment.
 * @param type Native class.
 * @return JSON library array.
 */
static jstring bridge_query_libraries(JNIEnv *env, jclass type) {
    char output[4096] = "[";
    size_t index;
    (void)type;
    for (index = 0; bridge_libraries[index] != NULL; index++) {
        snprintf(output + strlen(output), sizeof(output) - strlen(output), "%s\"%s\"", index == 0 ? "" : ",", bridge_libraries[index]);
    }
    strcat(output, "]");
    return bridge_response(env, output);
}

/**
 * Lists discovered functions for one selected library.
 * @param env JNI environment.
 * @param type Native class.
 * @param library_name Requested library.
 * @return JSON function array.
 */
static jstring bridge_query_functions(JNIEnv *env, jclass type, jstring library_name) {
    const char *library = (*env)->GetStringUTFChars(env, library_name, NULL);
    char output[16384] = "[";
    size_t index;
    int count = 0;
    (void)type;
    if (library == NULL) return bridge_response(env, "[]");
    for (index = 0; bridge_functions[index].library != NULL; index++) {
        if (strcmp(library, bridge_functions[index].library) == 0) {
            snprintf(output + strlen(output), sizeof(output) - strlen(output), "%s\"%s\"", count++ == 0 ? "" : ",", bridge_functions[index].name);
        }
    }
    (*env)->ReleaseStringUTFChars(env, library_name, library);
    strcat(output, "]");
    return bridge_response(env, output);
}

/**
 * Dispatches one generated typed native call.
 * @param env JNI environment.
 * @param type Native class.
 * @param library_name Selected library.
 * @param function_name Discovered function.
 * @param arguments JSON argument array.
 * @return JSON call result.
 */
static jstring bridge_dispatch(JNIEnv *env, jclass type, jstring library_name, jstring function_name, jstring arguments) {
    const char *library = (*env)->GetStringUTFChars(env, library_name, NULL);
    const char *name = (*env)->GetStringUTFChars(env, function_name, NULL);
    const char *args = (*env)->GetStringUTFChars(env, arguments, NULL);
    char output[65536] = "{\"error\":\"unknown function\"}";
    (void)type;
    if (library == NULL || name == NULL || args == NULL) strcpy(output, "{\"error\":\"invalid arguments\"}");
    else {
$(cat "$BRIDGE_CASES_FILE")
    }
    if (library != NULL) (*env)->ReleaseStringUTFChars(env, library_name, library);
    if (name != NULL) (*env)->ReleaseStringUTFChars(env, function_name, name);
    if (args != NULL) (*env)->ReleaseStringUTFChars(env, arguments, args);
    return bridge_response(env, output);
}

/**
 * Registers generated JNI methods for the internal transport.
 * @param vm Java virtual machine.
 * @param reserved Unused JNI value.
 * @return JNI version or JNI_ERR.
 */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    JNIEnv *env;
    jclass type;
    static const JNINativeMethod methods[] = {
        {"nativeDispatch", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", (void *)bridge_dispatch},
        {"nativeQueryLibraries", "()Ljava/lang/String;", (void *)bridge_query_libraries},
        {"nativeQueryFunctions", "(Ljava/lang/String;)Ljava/lang/String;", (void *)bridge_query_functions}
    };
    (void)reserved;
    if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    type = (*env)->FindClass(env, "$PACKAGE_SUBPATH/NativeBridge");
    if (type == NULL || (*env)->RegisterNatives(env, type, methods, (jint)(sizeof(methods) / sizeof(methods[0]))) != JNI_OK) return JNI_ERR;
    return JNI_VERSION_1_6;
}
EOF
    cat <<'EOF' > "$NATIVE_FACADE_FILE"
/**
 * native-bridge.js - Generated NativeBridge facade.
 * Summary: Exposes Android host methods and generated typed kclib functions.
 * Author: KaisarCode
 * Website: https://kaisarcode.com
 * License: https://www.gnu.org/licenses/gpl-3.0.html
 */

(function () {
    'use strict';
    var transport = window.__kcNativeTransport;
    window.NativeBridge = window.NativeBridge || {};
    window.NativeBridge.KcLib = window.NativeBridge.KcLib || {};
    var bridge = window.NativeBridge.KcLib;

    /**
     * Sends one facade call through the trusted internal transport.
     * @param library Selected kclib namespace.
     * @param name Discovered C function name.
     * @param args JavaScript arguments.
     * @return Promise resolving to the internal typed result.
     */
    function call(library, name, args) {
        return new Promise(function (resolve, reject) {

            /**
             * Delays dispatch until the trusted page token is available.
             * @return None.
             */
            function dispatch() {
                var token = window.__kcBridgeToken;
                var response;
                var value;
                if (!token) {
                    window.setTimeout(dispatch, 0);
                    return;
                }
                try {
                    response = transport.dispatch(token, library, name, JSON.stringify(args));
                    value = JSON.parse(response);
                } catch (error) {
                    reject(error);
                    return;
                }
                if (value.error) {
                    reject(new Error(value.error));
                    return;
                }
                resolve(value);
            }
            dispatch();
        });
    }

    /**
     * Sends one host method call through the internal host transport.
     * @param method Internal host transport method name.
     * @param args JavaScript arguments.
     * @return Promise resolving to the internal host result.
     */
    function callHost(method, args) {
        return new Promise(function (resolve, reject) {

            /**
             * Delays dispatch until the trusted page token is available.
             * @return None.
             */
            function dispatch() {
                var host = window.__kcHostTransport;
                var token = window.__kcBridgeToken;
                if (!token) {
                    window.setTimeout(dispatch, 0);
                    return;
                }
                try {
                    resolve(host[method].apply(host, [token].concat(args)));
                } catch (error) {
                    reject(error);
                }
            }
            dispatch();
        });
    }
EOF
    printf '%b\n' "$BRIDGE_FACADE_ROWS" >> "$NATIVE_FACADE_FILE"
    cat <<'EOF' >> "$NATIVE_FACADE_FILE"

    if (window.__kcHostTransport) {
        window.NativeBridge.showToast = function (message) {
            return callHost("showToast", [message]);
        };
        window.NativeBridge.isOnline = function () {
            return callHost("isOnline", []);
        };
        window.NativeBridge.getFilesDir = function () {
            return callHost("getFilesDir", []);
        };
    }
})();
EOF
}

# Injects the generated facade before the selected application document scripts.
# @return 0 when the application start document references the facade.
inject_native_facade () {
    START_DOCUMENT="$ASSETS_DIR/$APP_START"
    START_DIR=$(dirname "${APP_START#www/}")
    FACADE_PATH="js/native-bridge.js"
    while [ "$START_DIR" != "." ] && [ "$START_DIR" != "/" ]; do
        FACADE_PATH="../$FACADE_PATH"
        START_DIR=$(dirname "$START_DIR")
    done
    [ -f "$START_DOCUMENT" ] || { echo "error: app start document not found: $START_DOCUMENT" >&2; exit 1; }
    awk -v source="$FACADE_PATH" '
        { print }
        !inserted && /<[Hh][Ee][Aa][Dd][^>]*>/ {
            print "  <script src=\"" source "\"></script>"
            inserted = 1
        }
        END { if (!inserted) exit 1 }
    ' "$START_DOCUMENT" > "$START_DOCUMENT.generated" \
        || { echo "error: cannot inject NativeBridge facade into: $START_DOCUMENT" >&2; exit 1; }
    mv "$START_DOCUMENT.generated" "$START_DOCUMENT"
}

# Builds the generated common kclib bridge for both supported Android ABIs.
# @return 0 when both generated bridge outputs compile.
build_common_native () {
    [ -x "$NDK_TOOLCHAIN/bin/aarch64-linux-android$MIN_SDK-clang" ] || { echo "error: Android NDK compiler not found under: $NDK_TOOLCHAIN" >&2; exit 1; }
    for KCLIB_ARCH in aarch64 armv7; do
        case "$KCLIB_ARCH" in
            aarch64) ANDROID_ABI="arm64-v8a"; NDK_CC="$NDK_TOOLCHAIN/bin/aarch64-linux-android$MIN_SDK-clang" ;;
            armv7) ANDROID_ABI="armeabi-v7a"; NDK_CC="$NDK_TOOLCHAIN/bin/armv7a-linux-androideabi$MIN_SDK-clang" ;;
        esac
        set -- "$NDK_CC" -shared -fPIC -L"$NATIVE_PACKAGE_DIR/lib/$ANDROID_ABI" "-Wl,-rpath,\$ORIGIN" \
            -o "$NATIVE_PACKAGE_DIR/lib/$ANDROID_ABI/libkcapkbridge.so" "$NATIVE_DISPATCHER_FILE"
        for DEP in $KCLIB_DEPS; do
            set -- "$@" -I"$KCLIB_WORK_DIR/$DEP/$DEP.c/src"
        done
        for DEP in $KCLIB_DEPS; do
            set -- "$@" -l"$DEP"
        done
        "$@" || { echo "error: common bridge compilation failed for $KCLIB_ARCH" >&2; exit 1; }
    done
}

# Builds project JNI code for the Android ABIs supported by kcapk.
# @return 0 when no project native code exists or both outputs compile.
build_project_native () {
    [ -f "$NATIVE_C_SOURCE" ] || return 0
    [ -x "$NDK_TOOLCHAIN/bin/aarch64-linux-android$MIN_SDK-clang" ] || { echo "error: Android NDK compiler not found under: $NDK_TOOLCHAIN" >&2; exit 1; }

    for KCLIB_ARCH in aarch64 armv7; do
        case "$KCLIB_ARCH" in
            aarch64)
                ANDROID_ABI="arm64-v8a"
                NDK_CC="$NDK_TOOLCHAIN/bin/aarch64-linux-android$MIN_SDK-clang"
                ;;
            armv7)
                ANDROID_ABI="armeabi-v7a"
                NDK_CC="$NDK_TOOLCHAIN/bin/armv7a-linux-androideabi$MIN_SDK-clang"
                ;;
        esac
        set -- "$NDK_CC" -shared -fPIC -I"$NATIVE_SOURCE_DIR" -L"$NATIVE_PACKAGE_DIR/lib/$ANDROID_ABI" \
            "-Wl,-rpath,\$ORIGIN" -o "$NATIVE_PACKAGE_DIR/lib/$ANDROID_ABI/libprojectbridge.so" "$NATIVE_C_SOURCE"
        for DEP in $KCLIB_DEPS; do
            [ -n "$DEP" ] || continue
            set -- "$@" -I"$KCLIB_WORK_DIR/$DEP/$DEP.c/src"
        done
        for DEP in $KCLIB_DEPS; do
            [ -n "$DEP" ] || continue
            set -- "$@" -l"$DEP"
        done
        "$@" || { echo "error: project native compilation failed for $KCLIB_ARCH" >&2; exit 1; }
    done
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

    if [ -d "$NATIVE_PACKAGE_DIR/lib" ]; then
        cp -R "$NATIVE_PACKAGE_DIR/lib" "$FINAL_MODULE_DIR/lib"
    fi
    if [ -d "$FINAL_MODULE_DIR/assets" ] && [ -d "$FINAL_MODULE_DIR/lib" ]; then
        (cd "$FINAL_MODULE_DIR" && zip -r -q "$ABS_BASE_MODULE_ZIP" manifest res dex resources.pb assets lib) || { echo "Error: ZIP tool failed to re-package module."; exit 1; }
    elif [ -d "$FINAL_MODULE_DIR/assets" ]; then
        (cd "$FINAL_MODULE_DIR" && zip -r -q "$ABS_BASE_MODULE_ZIP" manifest res dex resources.pb assets) || { echo "Error: ZIP tool failed to re-package module."; exit 1; }
    elif [ -d "$FINAL_MODULE_DIR/lib" ]; then
        (cd "$FINAL_MODULE_DIR" && zip -r -q "$ABS_BASE_MODULE_ZIP" manifest res dex resources.pb lib) || { echo "Error: ZIP tool failed to re-package module."; exit 1; }
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
    if [ -d "$NATIVE_PACKAGE_DIR/lib" ]; then
        case "$UNSIGNED_APK_TEMP" in
            /*) ABS_UNSIGNED_APK_TEMP="$UNSIGNED_APK_TEMP" ;;
            *) ABS_UNSIGNED_APK_TEMP="$(pwd)/$UNSIGNED_APK_TEMP" ;;
        esac
        (cd "$NATIVE_PACKAGE_DIR" && zip -r -q "$ABS_UNSIGNED_APK_TEMP" lib) || { echo "Error: ZIP tool failed to package native libraries."; exit 1; }
    fi

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

if [ -d "$COMMON_ASSETS_DIR" ]; then
    cp -r "$COMMON_ASSETS_DIR/." "$PUBLISH_DIR/www/"
fi
cp -r "$ASSETS_SOURCE/." "$PUBLISH_DIR/www/"

    APK_PUBLISHED="$PUBLISH_DIR/$PROJECT_NAME.apk"
    if [ -f "$DEBUG_APK_FILE" ]; then
        cp "$DEBUG_APK_FILE" "$APK_PUBLISHED"
    else
        echo "warning: APK not found ($DEBUG_APK_FILE); publishing without apk artifact" >&2
        APK_PUBLISHED=""
    fi

    BUILD_TIMESTAMP="$(date -u +%s)"
    MANIFEST_TMP="$PUBLISH_DIR/manifest.json.tmp"

    {
        printf '{\n'
        printf '  "timestamp": %s,\n' "$BUILD_TIMESTAMP"
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

rm -rf "$BASE_DIR/src/main/java"
mkdir -p "$SRC_DIR" "$LAYOUT_DIR" "$VALUES_DIR" "$OUTPUT_DIR" \
    "$MIPMAP_MDPI_DIR" "$MIPMAP_HDPI_DIR" "$MIPMAP_XHDPI_DIR" \
    "$MIPMAP_XXHDPI_DIR" "$MIPMAP_XXXHDPI_DIR" "$MIPMAP_ANYDPI_V26_DIR"
rm -rf "$TEMP_ROOT_DIR"
mkdir -p "$TEMP_CLASSES_DIR" "$FLAT_RES_DIR" "$R_PACKAGE_DIR" "$TEMP_BUILD_DATA_DIR" "$AAB_TEMP_DIR" \
    "$KCLIB_WORK_DIR" "$NATIVE_PACKAGE_DIR"

DENSITY_PAIRS="mdpi:48x48 hdpi:72x72 xhdpi:96x96 xxhdpi:144x144 xxxhdpi:192x192"
FOREGROUND_DENSITY_PAIRS="mdpi:108x108 hdpi:162x162 xhdpi:216x216 xxhdpi:324x324 xxxhdpi:432x432"
ICON_TEMP_FILE="$RES_DIR/temp_icon_file_base"
ICON_RENDER_FILE="$RES_DIR/temp_icon_render.png"

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

ICON_RENDER_SOURCE="$ICON_TEMP_FILE"
case "$ICON_SOURCE_FILE" in
    *.svg|*.SVG)
        if command -v rsvg-convert >/dev/null 2>&1; then
            rsvg-convert -w 432 -h 432 -o "$ICON_RENDER_FILE" "$ICON_TEMP_FILE" || { echo "Error: SVG icon conversion failed." ; exit 1; }
            ICON_RENDER_SOURCE="$ICON_RENDER_FILE"
        fi
        ;;
esac

if command -v convert >/dev/null 2>&1; then
    for PAIR in $DENSITY_PAIRS; do
        DENSITY=$(echo "$PAIR" | cut -d: -f1)
        SIZE=$(echo "$PAIR" | cut -d: -f2)

        MIPMAP_SUBDIR="$RES_DIR/mipmap-$DENSITY"
        ICON_FINAL_PNG="$MIPMAP_SUBDIR/ic_launcher.png"

        convert -size "$SIZE" "xc:$ICON_BACKGROUND" "$ICON_RENDER_SOURCE" -resize "$SIZE" -gravity center -composite "$ICON_FINAL_PNG" || { echo "Error: ImageMagick fallback icon generation failed for $DENSITY." ; exit 1; }
    done
    for PAIR in $FOREGROUND_DENSITY_PAIRS; do
        DENSITY=$(echo "$PAIR" | cut -d: -f1)
        SIZE=$(echo "$PAIR" | cut -d: -f2)
        MIPMAP_SUBDIR="$RES_DIR/mipmap-$DENSITY"
        FOREGROUND_FINAL_PNG="$MIPMAP_SUBDIR/ic_launcher_foreground.png"

        convert -background none "$ICON_RENDER_SOURCE" -resize "$SIZE" -gravity center -extent "$SIZE" "$FOREGROUND_FINAL_PNG" || { echo "Error: ImageMagick adaptive icon generation failed for $DENSITY." ; exit 1; }
    done
else
    echo "Error: 'convert' (ImageMagick) not found. Cannot generate icons."
    rm -f "$ICON_TEMP_FILE"
    exit 1
fi

rm -f "$ICON_TEMP_FILE" "$ICON_RENDER_FILE"

echo "Icon Generation complete."

echo "Staging embedded assets..."
[ -d "$ASSETS_SOURCE" ] || { echo "error: assets directory not found: $ASSETS_SOURCE" >&2; exit 1; }
rm -rf "$ASSETS_DIR"
mkdir -p "$ASSETS_DIR/www"
if [ -d "$COMMON_ASSETS_DIR" ]; then
    cp -r "$COMMON_ASSETS_DIR/." "$ASSETS_DIR/www/"
fi
cp -r "$ASSETS_SOURCE/." "$ASSETS_DIR/www/"

echo "Computing embedded assets fingerprint..."
WWW_VERSION="$( (cd "$ASSETS_DIR/www" && find . -type f | sort | while IFS= read -r F; do printf '%s|%s\n' "${F#./}" "$(sha256 "$F")"; done) | sha256sum | awk '{print $1}' )"
printf '%s\n' "$WWW_VERSION" > "$ASSETS_DIR/www.version"
BUILD_TIMESTAMP="$(date -u +%s)"
printf '%s\n' "$BUILD_TIMESTAMP" > "$ASSETS_DIR/www.build_timestamp"
echo "www fingerprint: $WWW_VERSION"
echo "www build timestamp: $BUILD_TIMESTAMP"

echo "Preparing declared kclib dependencies..."
prepare_kclib_dependencies
discover_kclib_functions
generate_common_bridge
inject_native_facade
build_common_native
build_project_native

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
EOF

cat << EOF >> "$MANIFEST_FILE"
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
    <string name="js_interface_name">__kcHostTransport</string>
</resources>
EOF

cat << EOF > "$VALUES_DIR/icon_colors.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="icon_background">$ICON_BACKGROUND</color>
</resources>
EOF

cat << EOF > "$MIPMAP_ANYDPI_V26_DIR/ic_launcher.xml"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
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

JAVA_WEBVIEW_DEBUG=false
if [ "$WEBVIEW_DEBUG" = "true" ]; then
    JAVA_WEBVIEW_DEBUG=true
fi

cat << EOF > "$PROVISIONER_FILE"
package $PACKAGE_NAME;

import android.content.Context;
import android.content.res.AssetManager;
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

public class Provisioner {
    private static final String TAG = "Provisioner";

    private static final String APP_MANIFEST_URL = "$APP_MANIFEST_URL";
    private static final String DEFAULT_START = "$APP_START";
    private static final String INSTALLED_MANIFEST_FILE = "installed.manifest.json";
    private static final int CONNECT_TIMEOUT_MS = 15000;
    private static final int READ_TIMEOUT_MS = 30000;

    public interface ProgressListener {
        void onStage(String text);
        void onProgress(long bytesDone, long bytesTotal, String current, long currentDone, long currentTotal);
        void onWarning(String text);
    }

    private static class Pending {
        final String label;
        final String url;
        final long size;
        final String sha;
        final File target;

        Pending(String label, String url, long size, String sha, File target) {
            this.label = label;
            this.url = url;
            this.size = size;
            this.sha = sha;
            this.target = target;
        }
    }

    private static class Progress {
        private final ProgressListener listener;
        private final long total;
        private long committed;

        Progress(ProgressListener listener, long total) {
            this.listener = listener;
            this.total = Math.max(0, total);
        }

        void stage(String text) { listener.onStage(text); }

        void report(String label, long currentTotal, long currentDone) {
            long done = committed + currentDone;
            if (currentTotal > 0 && done > committed + currentTotal) {
                done = committed + currentTotal;
            }
            listener.onProgress(done, total, label, currentDone, currentTotal);
        }

        void commit(long n) { committed += n; }
    }

    private static class ManifestData {
        final long timestamp;
        final String start;
        final JSONObject raw;
        ManifestData(long timestamp, String start, JSONObject raw) {
            this.timestamp = timestamp;
            this.start = start;
            this.raw = raw;
        }
    }

    // Categorized provisioning failures so callers can distinguish network
    // problems from exact integrity or activation failures.
    private static class ProvisionException extends IOException {
        ProvisionException(String message) { super(message); }
    }

    private static class DownloadException extends ProvisionException {
        DownloadException(String message) { super(message); }
    }

    private static class SizeMismatchException extends ProvisionException {
        SizeMismatchException(String message) { super(message); }
    }

    private static class ShaMismatchException extends ProvisionException {
        ShaMismatchException(String message) { super(message); }
    }

    private static class IncompleteReleaseException extends ProvisionException {
        IncompleteReleaseException(String message) { super(message); }
    }

    private static class CommitException extends ProvisionException {
        CommitException(String message) { super(message); }
    }

    public static String provision(Context context, ProgressListener listener) {
        File filesDir = context.getFilesDir();
        File wwwDir = new File(filesDir, "www");

        recoverOnStartup(context, filesDir, wwwDir, listener);
        if (copyEmbeddedWww(context, filesDir, wwwDir)) {
            clearInstalledMetadata(context);
        }

        String start = installedStart(filesDir);
        if (start.isEmpty()) {
            start = DEFAULT_START;
        }

        try {
            listener.onStage("Reading app manifest...");
            boolean[] appChanged = {false};
            JSONObject appManifest = fetchJsonCached(context, APP_MANIFEST_URL, appChanged);
            ManifestData manifest = validateManifest(appManifest, filesDir);
            if (manifest == null) {
                listener.onWarning("Invalid remote manifest (using local cache)");
                Log.e(TAG, "remote manifest rejected; keeping local release");
                return startUri(filesDir, start);
            }

            if (manifest.timestamp <= installedTimestamp(filesDir)) {
                listener.onStage("Done");
                Log.i(TAG, "remote manifest is not newer than active release; keeping local web assets");
                return startUri(filesDir, start);
            }

            start = manifest.start;
            stageRelease(context, manifest, filesDir, listener);
            commitRelease(filesDir, listener);
            writeInstalledMetadata(context, appManifest);
            listener.onStage("Done");
            Log.i(TAG, "provisioning complete");
        } catch (SizeMismatchException e) {
            Log.w(TAG, "asset size mismatch; local release unchanged", e);
            listener.onWarning("Asset size mismatch (using local cache)");
        } catch (ShaMismatchException e) {
            Log.w(TAG, "asset sha256 mismatch; local release unchanged", e);
            listener.onWarning("Asset checksum mismatch (using local cache)");
        } catch (IncompleteReleaseException e) {
            Log.w(TAG, "remote release incomplete; local release unchanged", e);
            listener.onWarning("Incomplete remote release (using local cache)");
        } catch (CommitException e) {
            Log.w(TAG, "update activation failed; recovery will restore local release", e);
            listener.onWarning("Could not activate update (using local cache)");
        } catch (DownloadException e) {
            Log.w(TAG, "asset download failed; local release unchanged", e);
            listener.onWarning("Download failed: " + (e.getMessage() == null ? "connection error" : e.getMessage())
                    + " (using local cache)");
        } catch (IOException e) {
            Log.w(TAG, "network or provisioning failure; using local web assets", e);
            String msg = e.getMessage();
            listener.onWarning("Network unavailable: " + (msg == null ? "connection error" : msg)
                    + " (using local cache)");
        }

        return startUri(filesDir, start);
    }

    private static String startUri(File filesDir, String start) {
        String uri = new File(filesDir, start).toURI().toString();
        if (uri.startsWith("file:/") && !uri.startsWith("file:///")) {
            uri = "file:///" + uri.substring(6);
        }
        return uri;
    }

    private static void recoverOnStartup(Context context, File filesDir, File wwwDir, ProgressListener listener) {
        File wwwUpdate = new File(filesDir, "www.update");
        File wwwOld = new File(filesDir, "www.old");

        if (wwwUpdate.isDirectory()) {
            deleteRecursive(wwwUpdate);
            Log.i(TAG, "cleaned stale www.update staging");
        }

        if (wwwDir.isDirectory()) {
            if (isUsableWww(wwwDir, filesDir)) {
                if (wwwOld.isDirectory()) {
                    deleteRecursive(wwwOld);
                    Log.i(TAG, "cleaned stale www.old backup");
                }
                return;
            }
            deleteRecursive(wwwDir);
            Log.i(TAG, "removed unusable www");
        }

        if (wwwOld.isDirectory()) {
            if (renameOrCopy(wwwOld, wwwDir) && isUsableWww(wwwDir, filesDir)) {
                deleteRecursive(wwwOld);
                listener.onWarning("Recovered previous version");
                Log.i(TAG, "recovered www from www.old");
                return;
            }
            deleteRecursive(wwwOld);
            Log.i(TAG, "www.old was not usable; removed");
        }
    }

    private static boolean isUsableWww(File www, File filesDir) {
        if (!www.isDirectory() || www.list().length == 0) {
            return false;
        }
        File wwwVersion = new File(filesDir, "www.version");
        if (!wwwVersion.isFile()) {
            return true;
        }
        try {
            JSONObject installed = readInstalledManifest(filesDir);
            if (installed == null) {
                return true;
            }
            String start = installed.optString("start", "");
            if (start.isEmpty()) {
                return false;
            }
            File startFile = resolveUnderWww(www, stripWwwPrefix(start));
            return startFile != null && startFile.isFile();
        } catch (Exception e) {
            return false;
        }
    }

    private static JSONObject readInstalledManifest(File filesDir) {
        File f = new File(filesDir, INSTALLED_MANIFEST_FILE);
        if (!f.isFile()) {
            return null;
        }
        String body = readFileToString(f);
        if (body.isEmpty()) {
            return null;
        }
        try {
            return new JSONObject(body);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String installedStart(File filesDir) {
        JSONObject installed = readInstalledManifest(filesDir);
        if (installed != null) {
            String start = installed.optString("start", "");
            if (!start.isEmpty()) {
                return start;
            }
        }
        return "";
    }

    // Returns the timestamp of the currently active web release: the installed
    // manifest timestamp when one has been committed, otherwise the embedded
    // web build timestamp. Embedded activation clears installed metadata, so
    // precedence always reflects the release actually active in www.
    private static long installedTimestamp(File filesDir) {
        JSONObject installed = readInstalledManifest(filesDir);
        if (installed != null && installed.has("timestamp")) {
            try {
                return installed.getLong("timestamp");
            } catch (Exception ignored) {}
        }
        long embeddedBuildTimestamp = 0;
        try {
            String ts = readFileToString(new File(filesDir, "www.build_timestamp"));
            if (!ts.isEmpty()) {
                embeddedBuildTimestamp = Long.parseLong(ts.trim());
            }
        } catch (Exception ignored) {}
        return Math.max(0, embeddedBuildTimestamp);
    }

    // Manifest paths are stored relative to filesDir and therefore carry the
    // "www/" prefix. Address files inside a www root (staging dir, active
    // www dir) by stripping that prefix: the root itself is the release.
    private static String stripWwwPrefix(String path) {
        return path.startsWith("www/") ? path.substring(4) : path;
    }

    private static File resolveUnderWww(File www, String path) {
        try {
            File candidate = new File(www, path);
            String canonical = candidate.getCanonicalPath();
            String wwwRoot = www.getCanonicalPath();
            if (canonical.startsWith(wwwRoot + File.separator) || canonical.equals(wwwRoot)) {
                return candidate;
            }
        } catch (IOException ignored) {}
        return null;
    }

    private static boolean renameOrCopy(File src, File dest) {
        if (src.renameTo(dest)) {
            return true;
        }
        try {
            if (dest.exists()) {
                deleteRecursive(dest);
            }
            copyDir(src, dest);
            deleteRecursive(src);
            return true;
        } catch (IOException e) {
            Log.e(TAG, "renameOrCopy failed: " + src + " -> " + dest, e);
            return false;
        }
    }

    private static void copyDir(File src, File dest) throws IOException {
        if (src.isDirectory()) {
            dest.mkdirs();
            File[] children = src.listFiles();
            if (children != null) {
                for (File child : children) {
                    copyDir(child, new File(dest, child.getName()));
                }
            }
        } else {
            InputStream in = null;
            FileOutputStream fos = null;
            try {
                in = new FileInputStream(src);
                fos = new FileOutputStream(dest);
                copyStream(in, fos);
            } finally {
                closeQuietly(in);
                closeQuietly(fos);
            }
        }
    }

    private static ManifestData validateManifest(JSONObject manifest, File filesDir) {
        try {
            if (!manifest.has("timestamp")) {
                Log.e(TAG, "manifest validation: missing required field timestamp");
                return null;
            }
            if (!manifest.has("start")) {
                Log.e(TAG, "manifest validation: missing required field start");
                return null;
            }
            if (!manifest.has("assets")) {
                Log.e(TAG, "manifest validation: missing required field assets");
                return null;
            }

            long timestamp = manifest.getLong("timestamp");
            String start = manifest.getString("start");

            if (!isValidRelativePath(start) || !start.startsWith("www/") || start.contains("..")) {
                Log.e(TAG, "manifest validation: invalid start path: " + start);
                return null;
            }
            if (!isPathContainedInWww(start, filesDir)) {
                Log.e(TAG, "manifest validation: start escapes filesDir/www: " + start);
                return null;
            }

            JSONArray assets = manifest.getJSONArray("assets");
            Set<String> declaredPaths = new HashSet<String>();

            for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.getJSONObject(i);

                if (!a.has("path") || !a.has("size_bytes") || !a.has("sha256")) {
                    Log.e(TAG, "manifest validation: asset missing required fields at index " + i);
                    return null;
                }

                String path = a.getString("path");
                if (path.isEmpty() || !isValidRelativePath(path)
                        || !path.startsWith("www/") || path.contains("..")) {
                    Log.e(TAG, "manifest validation: invalid asset path: " + path);
                    return null;
                }
                if (!isPathContainedInWww(path, filesDir)) {
                    Log.e(TAG, "manifest validation: asset path escapes filesDir/www: " + path);
                    return null;
                }
                if (!declaredPaths.add(path)) {
                    Log.e(TAG, "manifest validation: duplicate asset path: " + path);
                    return null;
                }

                String sha = a.getString("sha256");
                if (!isValidSha256(sha)) {
                    Log.e(TAG, "manifest validation: invalid sha256 for " + path + ": " + sha);
                    return null;
                }

                long sizeBytes = a.getLong("size_bytes");
                if (sizeBytes < 0) {
                    Log.e(TAG, "manifest validation: negative size_bytes for " + path);
                    return null;
                }
            }

            if (!declaredPaths.contains(start)) {
                Log.e(TAG, "manifest validation: start does not reference a declared asset: " + start);
                return null;
            }

            return new ManifestData(timestamp, start, manifest);
        } catch (Exception e) {
            Log.e(TAG, "manifest validation failed", e);
            return null;
        }
    }

    private static boolean isValidRelativePath(String path) {
        if (path.isEmpty()) return false;
        if (path.startsWith("/")) return false;
        if (path.contains("\0")) return false;
        return true;
    }

    private static boolean isPathContainedInWww(String path, File filesDir) {
        try {
            File wwwDir = new File(filesDir, "www");
            File target = new File(filesDir, path);
            String canonicalTarget = target.getCanonicalPath();
            String canonicalWww = wwwDir.getCanonicalPath();
            return canonicalTarget.startsWith(canonicalWww + File.separator)
                    || canonicalTarget.equals(canonicalWww);
        } catch (IOException e) {
            return false;
        }
    }

    private static boolean isValidSha256(String sha) {
        if (sha == null || sha.length() != 64) return false;
        for (int i = 0; i < 64; i++) {
            char c = sha.charAt(i);
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                return false;
            }
        }
        return true;
    }

    private static void stageRelease(Context context, ManifestData manifest, File filesDir, ProgressListener listener)
            throws IOException {
        File wwwDir = new File(filesDir, "www");
        File stagingDir = new File(filesDir, "www.update");

        if (stagingDir.exists()) {
            deleteRecursive(stagingDir);
        }
        if (!stagingDir.mkdirs() && !stagingDir.isDirectory()) {
            throw new IOException("cannot create staging directory: " + stagingDir);
        }

        List<Pending> pending = new ArrayList<Pending>();
        long total = 0;

        JSONArray assets = manifest.raw.optJSONArray("assets");
        if (assets != null) {
            for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.optJSONObject(i);
                if (a == null) continue;

                String path = a.optString("path");
                if (path.isEmpty()) continue;

                String sha = a.optString("sha256", "");
                long size = a.optLong("size_bytes", -1);

                File activeFile = new File(filesDir, path);
                File stagingFile = new File(stagingDir, stripWwwPrefix(path));

                File parent = stagingFile.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new IOException("cannot create staging directory: " + parent);
                }

                if (activeFile.isFile() && !sha.isEmpty() && size >= 0
                        && activeFile.length() == size
                        && sha.equalsIgnoreCase(computeSha256(activeFile))) {
                    copyFile(activeFile, stagingFile);
                    Log.i(TAG, "reused from active: " + path);
                } else {
                    pending.add(new Pending(path, buildUrl(APP_MANIFEST_URL, path),
                            size, sha, stagingFile));
                    total += Math.max(0, size);
                }
            }
        }

        if (!pending.isEmpty()) {
            Progress progress = new Progress(listener, total);
            for (Pending p : pending) {
                progress.stage("Downloading " + p.label + "...");
                Log.i(TAG, "downloading asset: " + p.label);
                downloadFile(p.url, p.target, p.size, p.sha, p.label, progress);
            }
        }

        verifyCompleteRelease(manifest, stagingDir);
    }

    private static void verifyCompleteRelease(ManifestData manifest, File stagingDir) throws IOException {
        JSONArray assets = manifest.raw.optJSONArray("assets");
        if (assets == null) {
            throw new IncompleteReleaseException("no assets declared in manifest");
        }

        for (int i = 0; i < assets.length(); i++) {
            JSONObject a = assets.optJSONObject(i);
            if (a == null) continue;

            String path = a.optString("path");
            if (path.isEmpty()) continue;

            File f = new File(stagingDir, stripWwwPrefix(path));
            if (!f.isFile()) {
                throw new IncompleteReleaseException("staged asset missing: " + path);
            }

            long expectedSize = a.optLong("size_bytes", -1);
            if (expectedSize >= 0 && f.length() != expectedSize) {
                throw new SizeMismatchException("staged asset size mismatch: " + path
                        + " (expected " + expectedSize + ", got " + f.length() + ")");
            }

            String expectedSha = a.optString("sha256", "");
            if (!expectedSha.isEmpty() && !expectedSha.equalsIgnoreCase(computeSha256(f))) {
                throw new ShaMismatchException("staged asset sha256 mismatch: " + path);
            }
        }

        File startFile = new File(stagingDir, stripWwwPrefix(manifest.start));
        if (!startFile.isFile()) {
            throw new IncompleteReleaseException("manifest start file missing from staging: " + manifest.start);
        }
    }

    private static void commitRelease(File filesDir, ProgressListener listener) throws IOException {
        File wwwDir = new File(filesDir, "www");
        File stagingDir = new File(filesDir, "www.update");
        File backupDir = new File(filesDir, "www.old");

        if (backupDir.exists()) {
            deleteRecursive(backupDir);
        }

        if (wwwDir.exists()) {
            if (!wwwDir.renameTo(backupDir)) {
                throw new CommitException("failed to move active www to backup");
            }
        }

        if (!stagingDir.renameTo(wwwDir)) {
            if (backupDir.exists()) {
                renameOrCopy(backupDir, wwwDir);
                deleteRecursive(backupDir);
            }
            throw new CommitException("failed to activate staged release");
        }

        deleteRecursive(backupDir);
        Log.i(TAG, "release committed successfully");
    }

    private static void downloadFile(String urlStr, File out, long expectedSize, String expectedSha,
            String label, Progress progress) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        try {
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new DownloadException("HTTP " + code + " for " + label);
            }
            long contentLength = conn.getContentLength();
            long totalBytes = contentLength > 0 ? contentLength : expectedSize;
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
                    progress.report(label, totalBytes, done);
                }
                progress.commit(done);
            } finally {
                closeQuietly(in);
                closeQuietly(fos);
            }

            if (expectedSize >= 0 && out.length() != expectedSize) {
                out.delete();
                throw new SizeMismatchException("asset size mismatch: " + label
                        + " (expected " + expectedSize + ", got " + out.length() + ")");
            }

            String sha = computeSha256(out);
            if (sha.isEmpty()) {
                out.delete();
                throw new IOException("SHA-256 computation failed for " + label);
            }
            if (!expectedSha.isEmpty() && !expectedSha.equalsIgnoreCase(sha)) {
                out.delete();
                throw new ShaMismatchException("asset sha256 mismatch: " + label);
            }
        } finally {
            conn.disconnect();
        }
    }

    private static JSONObject fetchJson(String urlStr) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        try {
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " for " + urlStr);
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
                closeQuietly(reader);
            }
            try {
                return new JSONObject(sb.toString());
            } catch (Exception e) {
                throw new IOException("invalid JSON from " + urlStr, e);
            }
        } finally {
            conn.disconnect();
        }
    }

    // Fetches the remote manifest using the committed manifest cache for
    // If-Modified-Since reuse. It never persists cache state itself; committed
    // metadata is written only after a successful commit so that a failure
    // before commit leaves installed-version metadata representing the
    // previous release.
    private static JSONObject fetchJsonCached(Context context, String urlStr, boolean[] changedOut) throws IOException {
        File cache = manifestCacheFile(context, urlStr);
        String cachedBody = readFileToString(cache);
        long cachedTimestamp = 0;
        if (cache.isFile() && !cachedBody.isEmpty()) {
            try {
                JSONObject cached = new JSONObject(cachedBody);
                cachedTimestamp = cached.optLong("timestamp", 0);
            } catch (Exception ignored) {}
        }

        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setRequestMethod("HEAD");
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        if (cachedTimestamp > 0) {
            java.text.SimpleDateFormat httpDateFormat =
                    new java.text.SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", java.util.Locale.US);
            httpDateFormat.setTimeZone(java.util.TimeZone.getTimeZone("GMT"));
            conn.setRequestProperty("If-Modified-Since",
                    httpDateFormat.format(new java.util.Date(cachedTimestamp * 1000L)));
        }
        try {
            int code = conn.getResponseCode();
            if (code == HttpURLConnection.HTTP_NOT_MODIFIED) {
                changedOut[0] = false;
                try {
                    return new JSONObject(cachedBody);
                } catch (Exception e) {
                    throw new IOException("invalid cached JSON", e);
                }
            }
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " for " + urlStr);
            }
        } finally {
            conn.disconnect();
        }

        JSONObject fresh = fetchJson(urlStr);
        changedOut[0] = true;
        return fresh;
    }

    // Persists the accepted manifest as installed-version metadata alongside
    // the HTTP cache. Called only after a successful commit.
    private static void writeInstalledMetadata(Context context, JSONObject manifest) throws IOException {
        writeStringToFile(new File(context.getFilesDir(), INSTALLED_MANIFEST_FILE), manifest.toString());
        File cache = manifestCacheFile(context, APP_MANIFEST_URL);
        writeStringToFile(cache, manifest.toString());
    }

    // Drops previously committed remote metadata when a newer embedded APK
    // release has been activated, so the embedded release's build timestamp
    // and default start become authoritative over the stale remote release.
    private static void clearInstalledMetadata(Context context) {
        File filesDir = context.getFilesDir();
        deleteRecursive(new File(filesDir, INSTALLED_MANIFEST_FILE));
        deleteRecursive(manifestCacheFile(context, APP_MANIFEST_URL));
        Log.i(TAG, "cleared installed metadata after embedded activation");
    }

    private static File manifestCacheFile(Context context, String urlStr) {
        return new File(context.getFilesDir(), "manifest." + (urlStr.hashCode() & 0x7fffffff) + ".json");
    }

    private static String buildUrl(String manifestUrl, String path) {
        int idx = manifestUrl.lastIndexOf("/manifest.json");
        String base = idx >= 0 ? manifestUrl.substring(0, idx + 1) : manifestUrl;
        if (base.endsWith("/")) {
            return base + path;
        }
        return base + "/" + path;
    }

    // Activates the embedded web assets when the APK ships a different web
    // version than the previously active one. Returns true when embedded
    // assets replaced the active release.
    private static boolean copyEmbeddedWww(Context context, File filesDir, File wwwDir) {
        try {
            AssetManager am = context.getAssets();
            String embeddedVersion = readStreamToString(am.open("www.version"));
            String localVersion = readFileToString(new File(filesDir, "www.version"));
            if (embeddedVersion.equals(localVersion)) {
                return false;
            }
            deleteRecursive(wwwDir);
            if (wwwDir.mkdirs()) {
                copyAssetDir(am, "www", wwwDir);
                writeStringToFile(new File(filesDir, "www.version"), embeddedVersion);
                try {
                    String embeddedTimestamp = readStreamToString(am.open("www.build_timestamp"));
                    writeStringToFile(new File(filesDir, "www.build_timestamp"), embeddedTimestamp);
                } catch (IOException ignored) {}
                Log.i(TAG, "embedded www copied to " + wwwDir);
                return true;
            }
        } catch (IOException e) {
            Log.e(TAG, "cannot copy embedded assets", e);
        }
        return false;
    }

    private static void copyAssetDir(AssetManager am, String assetPath, File destDir) throws IOException {
        String[] entries = am.list(assetPath);
        if (entries == null) return;
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
                    copyStream(in, fos);
                } finally {
                    closeQuietly(in);
                    closeQuietly(fos);
                }
            }
        }
    }

    private static void deleteRecursive(File f) {
        if (!f.exists()) return;
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

    private static String computeSha256(File f) {
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
            closeQuietly(in);
        }
    }

    private static void copyFile(File src, File dst) throws IOException {
        InputStream in = null;
        FileOutputStream fos = null;
        try {
            in = new FileInputStream(src);
            fos = new FileOutputStream(dst);
            copyStream(in, fos);
        } finally {
            closeQuietly(in);
            closeQuietly(fos);
        }
    }

    private static void copyStream(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
    }

    private static String readFileToString(File f) {
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            return readStreamToString(in);
        } catch (IOException e) {
            return "";
        } finally {
            closeQuietly(in);
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
            closeQuietly(fos);
        }
    }

    private static void closeQuietly(InputStream in) {
        if (in != null) { try { in.close(); } catch (IOException ignored) {} }
    }

    private static void closeQuietly(OutputStream out) {
        if (out != null) { try { out.close(); } catch (IOException ignored) {} }
    }

    private static void closeQuietly(BufferedReader reader) {
        if (reader != null) { try { reader.close(); } catch (IOException ignored) {} }
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

import java.io.File;
import java.io.IOException;

public class TrustedWebViewClient extends WebViewClient {
    private final Context context;
    private final String[] trustedOrigins;
    private final File managedWwwDir;

    public TrustedWebViewClient(Context context, String[] trustedOrigins, File managedWwwDir) {
        this.context = context;
        this.trustedOrigins = trustedOrigins;
        this.managedWwwDir = managedWwwDir;
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
        if (JSBridge.isTrustedUrl(url, trustedOrigins, managedWwwDir)) {
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

cat << EOF > "$JS_INTERFACE_FILE"
package $PACKAGE_NAME;

import android.content.Context;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;

import java.io.File;
import java.net.URI;

public class JSBridge {
    private static final String ASSET_PREFIX = "file:///android_asset/";
    private final Context context;
    private final WebView webView;
    private final String[] trustedOrigins;
    private final File managedWwwDir;
    private final String gateToken;
    private volatile String currentUrl = "file:///android_asset/";

    public JSBridge(Context context, WebView webView, String[] trustedOrigins, File managedWwwDir, String gateToken) {
        this.context = context;
        this.webView = webView;
        this.trustedOrigins = trustedOrigins;
        this.managedWwwDir = managedWwwDir;
        this.gateToken = gateToken;
    }

    public void setCurrentUrl(String url) {
        this.currentUrl = url;
    }

    public static boolean isTrustedUrl(String url, String[] trustedOrigins, File managedWwwDir) {
        if (url == null || url.isEmpty()) {
            return false;
        }

        if (url.startsWith("file://")) {
            return isManagedFileUrl(url, managedWwwDir);
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

    static boolean isManagedFileUrl(String url, File managedWwwDir) {
        if (managedWwwDir == null) {
            return false;
        }
        try {
            if (url.startsWith(ASSET_PREFIX)) {
                return true;
            }
            String path = url.substring("file://".length());
            File candidate = new File(path);
            String canonical = candidate.getCanonicalPath();
            String wwwRoot = managedWwwDir.getCanonicalPath();
            return canonical.startsWith(wwwRoot + File.separator) || canonical.equals(wwwRoot);
        } catch (Exception e) {
            return false;
        }
    }

    static String normalizeOrigin(URI uri) {
        String scheme = uri.getScheme();
        String host = uri.getHost();

        if (scheme == null || host == null) {
            return null;
        }

        scheme = scheme.toLowerCase();
        host = host.toLowerCase();

        int port = uri.getPort();
        if (port == -1) {
            return scheme + "://" + host;
        }
        return scheme + "://" + host + ":" + port;
    }

    private boolean isMainFrameTrusted() {
        String url = currentUrl;
        if (url == null) {
            return false;
        }
        return isTrustedUrl(url, trustedOrigins, managedWwwDir);
    }

    // Subframe isolation: privileged calls must present the per-process
    // capability token that Android injects only into trusted main-frame
    // content. A cross-origin remote or otherwise untrusted iframe cannot
    // read window.__kcBridgeToken, so it cannot produce a valid token.
    boolean isTrustedCall(String token) {
        if (token == null || gateToken == null || !token.equals(gateToken)) {
            return false;
        }
        return isMainFrameTrusted();
    }

    boolean canUseBridge() {
        return isMainFrameTrusted();
    }

    @JavascriptInterface
    public void showToast(String token, String message) {
        if (!isTrustedCall(token)) {
            return;
        }
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show();
    }

    @JavascriptInterface
    public boolean isOnline(String token) {
        if (!isTrustedCall(token)) {
            return false;
        }
        ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        if (cm != null) {
            NetworkInfo netInfo = cm.getActiveNetworkInfo();
            return netInfo != null && netInfo.isConnected();
        }
        return false;
    }

    @JavascriptInterface
    public String getFilesDir(String token) {
        if (!isTrustedCall(token)) {
            return "";
        }
        return context.getFilesDir().getAbsolutePath();
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
    private static final String JS_INTERFACE_NAME = "__kcHostTransport";
    private static final String[] TRUSTED_ORIGINS = { $JAVA_TRUSTED_ORIGINS };

    private WebView webView;
    private JSBridge jsBridge;
    private String homeUrl = null;
    private String gateToken = null;

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
        webView.getSettings().setAllowFileAccessFromFileURLs(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setUseWideViewPort(true);
        webView.getSettings().setLoadWithOverviewMode(true);
        webView.setVerticalScrollBarEnabled(false);
        if ($JAVA_WEBVIEW_DEBUG) {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                WebView.setWebContentsDebuggingEnabled(true);
            }
        }
        webView.setWebChromeClient(new android.webkit.WebChromeClient() {
            @Override
            public boolean onConsoleMessage(android.webkit.ConsoleMessage consoleMessage) {
                android.util.Log.d("JSConsole", consoleMessage.message() + " (" + consoleMessage.sourceId() + ":" + consoleMessage.lineNumber() + ")");
                return super.onConsoleMessage(consoleMessage);
            }
        });

        File wwwDir = new File(getFilesDir(), "www");
        gateToken = newGateToken();
        jsBridge = new JSBridge(this, webView, TRUSTED_ORIGINS, wwwDir, gateToken);
        webView.setWebViewClient(new TrustedWebViewClient(this, TRUSTED_ORIGINS, wwwDir) {
            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                jsBridge.setCurrentUrl(url);
                if (JSBridge.isTrustedUrl(url, TRUSTED_ORIGINS, wwwDir)) {
                    injectGateToken(view);
                }
                if (homeUrl != null && homeUrl.equals(url)) {
                    view.clearHistory();
                    homeUrl = null;
                }
            }
        });
        webView.addJavascriptInterface(jsBridge, JS_INTERFACE_NAME);
        webView.addJavascriptInterface(new NativeBridge(this, webView, jsBridge), "__kcNativeTransport");

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
                                    "if(window.KcSplash&&window.KcSplash.setStatus)window.KcSplash.setStatus(\"" + escapeJs(text) + "\");", null);
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
                                    "if(window.KcSplash&&window.KcSplash.setProgress)window.KcSplash.setProgress(" + bytesDone + "," + bytesTotal
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
                                    "if(window.KcSplash&&window.KcSplash.setWarning)window.KcSplash.setWarning(\"" + escapeJs(text) + "\");", null);
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
                            Log.e(TAG, "Provisioning failed: " + result[1]);
                            webView.loadDataWithBaseURL("file:///android_asset/",
                                    errorPage(result[1]), "text/html", "UTF-8", null);
                            webView.clearHistory();
                        }
                    }
                });
            }
        }).start();
    }

    private void injectGateToken(WebView view) {
        if (gateToken == null) {
            return;
        }
        String escaped = escapeJs(gateToken);
        view.evaluateJavascript(
                "window.__kcBridgeToken='" + escaped + "';"
                        + "if(window.KcSplash&&window.KcSplash._setToken)window.KcSplash._setToken('" + escaped + "');",
                null);
    }

    private static String newGateToken() {
        byte[] buf = new byte[16];
        new java.security.SecureRandom().nextBytes(buf);
        StringBuilder sb = new StringBuilder();
        for (byte b : buf) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
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
    "$NATIVE_BRIDGE_FILE" \
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

rm -f "$RES_DIR/temp_icon_file_base" "$RES_DIR/temp_icon_render.png"
rm -rf "$TEMP_ROOT_DIR"

publish

echo "BUILD COMPLETE for $DISPLAY_NAME. Both files are in $OUTPUT_DIR/."
echo "APK Output: $DEBUG_APK_FILE"
echo "AAB Output: $AAB_SIGNED_FILE"
echo "INSTALL: adb install -r -t $DEBUG_APK_FILE"
echo "UNINSTALL: adb uninstall $PACKAGE_NAME"
