# NativeBridge API selection and template pruning.

# Quotes a shell argument for safe reuse.
# @param $1 Argument to quote.
# @return Prints the quoted argument.
quote_arg () {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Appends a quoted argument to the build arguments list.
# @param $1 Argument to append.
# @return None.
append_arg () {
    QUOTED_ARG=$(quote_arg "$1")
    RUN_ARGS="$RUN_ARGS $QUOTED_ARG"
}

# Normalizes an API name alias to its canonical form.
# @param $1 API name or alias.
# @return Prints the normalized API name or fails.
normalize_api_name () {
    case "$1" in
        core) printf '%s\n' core ;;
        network) printf '%s\n' network ;;
        permissions) printf '%s\n' permissions ;;
        notifications) printf '%s\n' notifications ;;
        alarms) printf '%s\n' alarms ;;
        haptics) printf '%s\n' haptics ;;
        intents) printf '%s\n' intents ;;
        files) printf '%s\n' files ;;
        apps) printf '%s\n' apps ;;
        resources) printf '%s\n' resources ;;
        system-ui|systemUI) printf '%s\n' systemUI ;;
        clipboard) printf '%s\n' clipboard ;;
        screen) printf '%s\n' screen ;;
        voice) printf '%s\n' voice ;;
        *) return 1 ;;
    esac
}

# Enables an optional API module for the build.
# @param $1 API name to enable.
# @return None.
enable_api () {
    NORMALIZED_API=$(normalize_api_name "$1") || {
        echo "Error: Unknown --api value: $1" >&2
        exit 1
    }

    [ "$NORMALIZED_API" = core ] && return

    case " $ENABLED_APIS " in
        *" $NORMALIZED_API "*) ;;
        *) ENABLED_APIS="$ENABLED_APIS $NORMALIZED_API" ;;
    esac
}

# Checks if an API module is enabled.
# @param $1 API name to check.
# @return 0 if enabled, 1 otherwise.
api_enabled () {
    case "$1" in
        core) return 0 ;;
        exec) $HAS_EXEC; return ;;
        async)
            $HAS_EXEC && return 0
            case " $ENABLED_APIS " in
                *" permissions "*|*" files "*|*" apps "*|*" resources "*|*" voice "*) return 0 ;;
            esac
            return 1
            ;;
    esac

    case " $ENABLED_APIS " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

# Filters a template file, including/excluding API-specific blocks.
# @param $1 Template file path.
# @return None.
filter_template_file () {
    INPUT_FILE="$1"
    OUTPUT_FILE="$INPUT_FILE.kcapk"
    INCLUDE_BLOCK=true

    while IFS= read -r LINE || [ -n "$LINE" ]; do
        case "$LINE" in
            *'@KCAPK_API:'*'@'*)
                API_NAME=$(printf '%s\n' "$LINE" | sed -n 's/.*@KCAPK_API:\([A-Za-z0-9_-]*\)@.*/\1/p')
                if api_enabled "$API_NAME"; then
                    INCLUDE_BLOCK=true
                else
                    INCLUDE_BLOCK=false
                fi
                continue
                ;;
            *'@KCAPK_END_API@'*)
                INCLUDE_BLOCK=true
                continue
                ;;
        esac

        if $INCLUDE_BLOCK; then
            printf '%s\n' "$LINE"
        fi
    done < "$INPUT_FILE" > "$OUTPUT_FILE" || exit 1

    mv "$OUTPUT_FILE" "$INPUT_FILE"
}

# Injects a permission declaration into the staged manifest template if absent.
# @param $1 Android permission name.
# @return None.
inject_api_permission () {
    PERMISSION_NAME="$1"
    grep -q "android:name=\"$PERMISSION_NAME\"" "$API_MANIFEST_TEMPLATE" && return

    TEMP_MANIFEST="$API_MANIFEST_TEMPLATE.permission"
    awk -v permission="$PERMISSION_NAME" '
        /@PERMISSIONS@/ {
            printf "    <uses-permission android:name=\"%s\" />\n", permission
        }
        { print }
    ' "$API_MANIFEST_TEMPLATE" > "$TEMP_MANIFEST" || exit 1
    mv "$TEMP_MANIFEST" "$API_MANIFEST_TEMPLATE"
}

# Parses API-only options, stages templates, and forwards remaining arguments.
# @param $@ Public build arguments.
# @return None.
prepare_api_build () {
    ENABLED_APIS=""
    RUN_ARGS=""
    HAS_EXEC=false
    HAS_SHARE_TARGET=false
    REQUEST_NETWORK_PERMISSION=false
    REQUEST_BOOT_PERMISSION=false
    REQUEST_VIBRATE_PERMISSION=false
    EXTENSION_DIRS=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --api)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --api requires a value." >&2; exit 1; }
                enable_api "$1"
                shift
                ;;
            --extension)
                shift
                [ "$#" -gt 0 ] || { echo "Error: --extension requires a directory." >&2; exit 1; }
                [ -d "$1" ] || { echo "Error: Extension directory not found: $1" >&2; exit 1; }
                EXTENSION_DIRECTORY=$(CDPATH= cd -- "$1" && pwd) || exit 1
                EXTENSION_DIRS="$EXTENSION_DIRS
$EXTENSION_DIRECTORY"
                shift
                ;;
            --exec)
                HAS_EXEC=true
                append_arg "$1"
                shift
                [ "$#" -gt 0 ] || { echo "Error: --exec requires a path." >&2; exit 1; }
                append_arg "$1"
                shift
                ;;
            --share-target)
                HAS_SHARE_TARGET=true
                append_arg "$1"
                shift
                [ "$#" -gt 0 ] || { echo "Error: --share-target requires a MIME type." >&2; exit 1; }
                append_arg "$1"
                shift
                ;;
            --permission)
                append_arg "$1"
                shift
                [ "$#" -gt 0 ] || { echo "Error: --permission requires a value." >&2; exit 1; }
                case "$1" in
                    android.permission.ACCESS_NETWORK_STATE) REQUEST_NETWORK_PERMISSION=true ;;
                    android.permission.RECEIVE_BOOT_COMPLETED) REQUEST_BOOT_PERMISSION=true ;;
                    android.permission.VIBRATE) REQUEST_VIBRATE_PERMISSION=true ;;
                esac
                append_arg "$1"
                shift
                ;;
            *)
                append_arg "$1"
                shift
                ;;
        esac
    done

    if $HAS_SHARE_TARGET && ! api_enabled intents; then
        echo "Error: --share-target requires --api intents." >&2
        exit 1
    fi

    [ -d "$KCAPK_TEMPLATE_SOURCE_DIR" ] || { echo "Error: Template directory not found: $KCAPK_TEMPLATE_SOURCE_DIR" >&2; exit 1; }
    cp -R "$KCAPK_TEMPLATE_SOURCE_DIR" "$WORK_DIR/templates" || exit 1

    for TEMPLATE_FILE in "$WORK_DIR/templates/AndroidManifest.xml.in" "$WORK_DIR/templates/java/JSBridge.java.in" "$WORK_DIR/templates/java/MainActivity.java.in" "$WORK_DIR/templates/res/raw/native_bridge.js.in"; do
        [ -f "$TEMPLATE_FILE" ] && filter_template_file "$TEMPLATE_FILE"
    done

    API_MANIFEST_TEMPLATE="$WORK_DIR/templates/AndroidManifest.xml.in"
    api_enabled network && inject_api_permission android.permission.ACCESS_NETWORK_STATE
    api_enabled alarms && inject_api_permission android.permission.RECEIVE_BOOT_COMPLETED
    api_enabled haptics && inject_api_permission android.permission.VIBRATE
    $REQUEST_NETWORK_PERMISSION && inject_api_permission android.permission.ACCESS_NETWORK_STATE
    $REQUEST_BOOT_PERMISSION && inject_api_permission android.permission.RECEIVE_BOOT_COMPLETED
    $REQUEST_VIBRATE_PERMISSION && inject_api_permission android.permission.VIBRATE

    for TEMPLATE_FILE in "$WORK_DIR/templates/java"/*.java.in; do
        [ -f "$TEMPLATE_FILE" ] || continue
        TEMPLATE_NAME=$(basename "$TEMPLATE_FILE")

        case "$TEMPLATE_NAME" in
            AsyncBridge.java.in) api_enabled async || rm -f "$TEMPLATE_FILE" ;;
            ExecBridge.java.in) api_enabled exec || rm -f "$TEMPLATE_FILE" ;;
            PermissionBridge.java.in) api_enabled permissions || rm -f "$TEMPLATE_FILE" ;;
            NotificationBridge.java.in)
                if ! api_enabled notifications && ! api_enabled alarms; then
                    rm -f "$TEMPLATE_FILE"
                fi
                ;;
            AlarmBridge.java.in|AlarmReceiver.java.in|AlarmRestoreReceiver.java.in) api_enabled alarms || rm -f "$TEMPLATE_FILE" ;;
            HapticBridge.java.in) api_enabled haptics || rm -f "$TEMPLATE_FILE" ;;
            IntentBridge.java.in) api_enabled intents || rm -f "$TEMPLATE_FILE" ;;
            FileBridge.java.in) api_enabled files || rm -f "$TEMPLATE_FILE" ;;
            AppBridge.java.in) api_enabled apps || rm -f "$TEMPLATE_FILE" ;;
            ResourceBridge.java.in) api_enabled resources || rm -f "$TEMPLATE_FILE" ;;
            SystemUIBridge.java.in) api_enabled systemUI || rm -f "$TEMPLATE_FILE" ;;
            ClipboardBridge.java.in) api_enabled clipboard || rm -f "$TEMPLATE_FILE" ;;
            ScreenBridge.java.in) api_enabled screen || rm -f "$TEMPLATE_FILE" ;;
            VoiceBridge.java.in) api_enabled voice || rm -f "$TEMPLATE_FILE" ;;
        esac
    done

    # Compose app-owned Java, resources, and components in the staged tree.
    EXTENSION_PERMISSIONS="$WORK_DIR/extension-permissions.xml"
    EXTENSION_COMPONENTS="$WORK_DIR/extension-components.xml"
    : > "$EXTENSION_PERMISSIONS"
    : > "$EXTENSION_COMPONENTS"
    while IFS= read -r EXTENSION_DIRECTORY; do
        [ -n "$EXTENSION_DIRECTORY" ] || continue
        if [ -d "$EXTENSION_DIRECTORY/java" ]; then
            for EXTENSION_FILE in "$EXTENSION_DIRECTORY"/java/*.java.in; do
                [ -f "$EXTENSION_FILE" ] || continue
                TARGET="$WORK_DIR/templates/java/$(basename "$EXTENSION_FILE")"
                if [ -e "$TARGET" ] && [ "$(basename "$TARGET")" != "KcapkAppExtension.java.in" ]; then
                    echo "Error: Extension may not override a KCAPK class: $TARGET" >&2
                    exit 1
                fi
                cp "$EXTENSION_FILE" "$TARGET" || exit 1
            done
        fi
        if [ -d "$EXTENSION_DIRECTORY/res" ]; then
            cp -R "$EXTENSION_DIRECTORY/res/." "$WORK_DIR/templates/res/" || exit 1
        fi
        if [ -f "$EXTENSION_DIRECTORY/manifest/permissions.xml" ]; then
            cat "$EXTENSION_DIRECTORY/manifest/permissions.xml" >> "$EXTENSION_PERMISSIONS" || exit 1
        fi
        if [ -f "$EXTENSION_DIRECTORY/manifest/components.xml" ]; then
            cat "$EXTENSION_DIRECTORY/manifest/components.xml" >> "$EXTENSION_COMPONENTS" || exit 1
        fi
    done <<EOF
$EXTENSION_DIRS
EOF

    printf 'NativeBridge APIs: core'
    for API_NAME in $ENABLED_APIS; do
        printf ' %s' "$API_NAME"
    done
    $HAS_EXEC && printf ' exec'
    printf '\n'
}
