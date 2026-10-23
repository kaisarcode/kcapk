# Template rendering and trusted-origin helpers.

# Extracts scheme://host[:port] from a remote URL.
# @param $1 Remote URL.
# @return Prints the origin or fails.
extract_origin () {
    INPUT_URL="$1"

    case "$INPUT_URL" in
        http://*|https://*)
            SCHEME="${INPUT_URL%%://*}"
            REMAINDER="${INPUT_URL#*://}"
            HOST_AND_PORT="${REMAINDER%%/*}"

            if [ -z "$HOST_AND_PORT" ]; then
                return 1
            fi

            printf '%s://%s\n' "$SCHEME" "$HOST_AND_PORT"
            ;;
        *) return 1 ;;
    esac
}

# Escapes a value for a sed replacement using # as the delimiter.
# @param $1 Replacement value.
# @return Prints the escaped replacement.
escape_template_value () {
    printf '%s' "$1" | sed 's/[\\&#]/\\&/g'
}

# Renders one source template into the generated Android project.
# @param $1 Template path.
# @param $2 Destination path.
# @return None.
render_template () {
    TEMPLATE_FILE="$1"
    DESTINATION_FILE="$2"

    [ -f "$TEMPLATE_FILE" ] || { echo "Error: Source template not found: $TEMPLATE_FILE" >&2; exit 1; }
    mkdir -p "$(dirname "$DESTINATION_FILE")"

    PACKAGE_VALUE=$(escape_template_value "$PACKAGE_NAME")
    VERSION_CODE_VALUE=$(escape_template_value "$VERSION_CODE")
    VERSION_NAME_VALUE=$(escape_template_value "$VERSION_NAME")
    DISPLAY_NAME_VALUE=$(escape_template_value "$DISPLAY_NAME")
    ICON_BACKGROUND_VALUE=$(escape_template_value "$ICON_BACKGROUND")
    BACKGROUND_VALUE=$(escape_template_value "$BACKGROUND")
    APP_THEME_VALUE=$(escape_template_value "$APP_THEME")
    WEBVIEW_URL_VALUE=$(escape_template_value "$WEBVIEW_URL")
    TRUSTED_ORIGINS_VALUE=$(escape_template_value "$JAVA_TRUSTED_ORIGINS")
    EXECUTABLE_NAMES_VALUE=$(escape_template_value "$JAVA_EXECUTABLE_NAMES")
    FULLSCREEN_VALUE=$(escape_template_value "$IS_FULLSCREEN")
    MIN_SDK_VALUE=$(escape_template_value "$MIN_SDK")
    TARGET_SDK_VALUE=$(escape_template_value "$TARGET_SDK")

    sed \
        -e "s#@PACKAGE_NAME@#$PACKAGE_VALUE#g" \
        -e "s#@VERSION_CODE@#$VERSION_CODE_VALUE#g" \
        -e "s#@VERSION_NAME@#$VERSION_NAME_VALUE#g" \
        -e "s#@DISPLAY_NAME@#$DISPLAY_NAME_VALUE#g" \
        -e "s#@ICON_BACKGROUND@#$ICON_BACKGROUND_VALUE#g" \
        -e "s#@BACKGROUND@#$BACKGROUND_VALUE#g" \
        -e "s#@APP_THEME@#$APP_THEME_VALUE#g" \
        -e "s#@WEBVIEW_URL@#$WEBVIEW_URL_VALUE#g" \
        -e "s#@TRUSTED_ORIGINS@#$TRUSTED_ORIGINS_VALUE#g" \
        -e "s#@EXECUTABLE_NAMES@#$EXECUTABLE_NAMES_VALUE#g" \
        -e "s#@IS_FULLSCREEN@#$FULLSCREEN_VALUE#g" \
        -e "s#@MIN_SDK@#$MIN_SDK_VALUE#g" \
        -e "s#@TARGET_SDK@#$TARGET_SDK_VALUE#g" \
        "$TEMPLATE_FILE" > "$DESTINATION_FILE" || { echo "Error: Failed to render template: $TEMPLATE_FILE" >&2; exit 1; }
}

# Copies and renders the Android source tree used by generated apps.
# @return None.
prepare_source_templates () {
    JAVA_TEMPLATE_DIR="$KCAPK_SRC_DIR/java"
    RESOURCE_TEMPLATE_DIR="$KCAPK_SRC_DIR/res"
    MANIFEST_TEMPLATE="$KCAPK_SRC_DIR/AndroidManifest.xml.in"
    RESOURCE_TEMPLATE_LIST="$TEMP_ROOT_DIR/resource_templates.list"

    [ -d "$JAVA_TEMPLATE_DIR" ] || { echo "Error: Java source template directory not found: $JAVA_TEMPLATE_DIR" >&2; exit 1; }
    [ -d "$RESOURCE_TEMPLATE_DIR" ] || { echo "Error: Resource template directory not found: $RESOURCE_TEMPLATE_DIR" >&2; exit 1; }

    echo "Writing Android source templates..."
    render_template "$MANIFEST_TEMPLATE" "$MANIFEST_FILE"

    MANIFEST_DYNAMIC_TEMP="$TEMP_ROOT_DIR/AndroidManifest.dynamic"
    while IFS= read -r LINE || [ -n "$LINE" ]; do
        case "$LINE" in
            *'@PERMISSIONS@'*) cat "$PERMISSION_DECLARATIONS_FILE" ;;
            *'@SHARE_TARGETS@'*) cat "$SHARE_TARGET_DECLARATIONS_FILE" ;;
            *) printf '%s\n' "$LINE" ;;
        esac
    done < "$MANIFEST_FILE" > "$MANIFEST_DYNAMIC_TEMP"
    mv "$MANIFEST_DYNAMIC_TEMP" "$MANIFEST_FILE"

    for TEMPLATE_FILE in "$JAVA_TEMPLATE_DIR"/*.java.in; do
        [ -f "$TEMPLATE_FILE" ] || continue
        TARGET_NAME=$(basename "$TEMPLATE_FILE" .in)
        render_template "$TEMPLATE_FILE" "$SRC_DIR/$TARGET_NAME"
    done

    cp -R "$RESOURCE_TEMPLATE_DIR/." "$RES_DIR/" || { echo "Error: Failed to copy Android resource templates." >&2; exit 1; }
    find "$RES_DIR" -type f -name '*.in' -print > "$RESOURCE_TEMPLATE_LIST" || { echo "Error: Failed to enumerate Android resource templates." >&2; exit 1; }
    while IFS= read -r TEMPLATE_FILE; do
        [ -n "$TEMPLATE_FILE" ] || continue
        DESTINATION_FILE=${TEMPLATE_FILE%.in}
        render_template "$TEMPLATE_FILE" "$DESTINATION_FILE"
        rm -f "$TEMPLATE_FILE"
    done < "$RESOURCE_TEMPLATE_LIST"
    rm -f "$RESOURCE_TEMPLATE_LIST"

    if [ -z "$BACKGROUND" ]; then
        rm -f "$VALUES_DIR/app_colors.xml" "$VALUES_DIR/styles.xml"
    fi
}
