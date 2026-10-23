# Main build pipeline and common compilation flow.

# Creates generated-project and temporary build directories.
# @return None.
prepare_build_directories () {
    mkdir -p "$SRC_DIR" "$LAYOUT_DIR" "$VALUES_DIR" "$OUTPUT_DIR" "$ASSETS_DIR" \
        "$MIPMAP_MDPI_DIR" "$MIPMAP_HDPI_DIR" "$MIPMAP_XHDPI_DIR" \
        "$MIPMAP_XXHDPI_DIR" "$MIPMAP_XXXHDPI_DIR" "$MIPMAP_ANYDPI_V26_DIR"
    rm -rf "$TEMP_ROOT_DIR"
    mkdir -p "$TEMP_CLASSES_DIR" "$FLAT_RES_DIR" "$R_PACKAGE_DIR" "$TEMP_BUILD_DATA_DIR" "$AAB_TEMP_DIR" "$NATIVE_LIBS_DIR"
}

# Generates launcher and adaptive launcher icons.
# @return None.
generate_icons () {
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
        *)
            echo "Starting Icon Generation from LOCAL FILE ($ICON_SOURCE_FILE)..."
            if [ ! -f "$ICON_SOURCE_FILE" ]; then
                echo "Error: Icon file not found at $ICON_SOURCE_FILE."
                exit 1
            fi
            cp "$ICON_SOURCE_FILE" "$ICON_TEMP_FILE" || { echo "Error: Failed to copy local icon file." ; exit 1; }
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
            convert "$ICON_RENDER_SOURCE" -resize "$SIZE" "$ICON_FINAL_PNG" || { echo "Error: ImageMagick conversion failed for $DENSITY." ; exit 1; }
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
        rm -f "$ICON_TEMP_FILE" "$ICON_RENDER_FILE"
        exit 1
    fi

    rm -f "$ICON_TEMP_FILE" "$ICON_RENDER_FILE"
    echo "Icon Generation complete."
}

# Prepares local WebView assets and trusted origins.
# @return None.
prepare_web_assets () {
    ORIGINAL_WEBVIEW_URL="$WEBVIEW_URL"
    RESOLVED_TRUSTED_ORIGINS="$TRUSTED_ORIGINS"

    if [ -d "$ASSETS_DIR" ]; then
        rm -rf "$ASSETS_DIR"
    fi
    mkdir -p "$ASSETS_DIR"

    if [ "${ORIGINAL_WEBVIEW_URL#https}" != "$ORIGINAL_WEBVIEW_URL" ] || \
        [ "${ORIGINAL_WEBVIEW_URL#http}" != "$ORIGINAL_WEBVIEW_URL" ] || \
        [ "${ORIGINAL_WEBVIEW_URL#file:}" != "$ORIGINAL_WEBVIEW_URL" ]; then
        echo "WEBVIEW_URL contains a protocol (http/https/file:). Skipping local asset copy."
    else
        ORIGINAL_LOCAL_PATH="$ORIGINAL_WEBVIEW_URL"
        LOCAL_FILE_TO_COPY=""

        case "$ORIGINAL_LOCAL_PATH" in
            \~*) LOCAL_FILE_TO_COPY="$HOME${ORIGINAL_LOCAL_PATH#\~}" ;;
            *) LOCAL_FILE_TO_COPY="$ORIGINAL_LOCAL_PATH" ;;
        esac

        if [ ! -f "$LOCAL_FILE_TO_COPY" ]; then
            echo "Error: Local HTML start file not found at $LOCAL_FILE_TO_COPY."
            echo "Please create the file to continue."
            exit 1
        fi

        FILENAME=$(basename "$LOCAL_FILE_TO_COPY")
        SOURCE_DIR=$(dirname "$LOCAL_FILE_TO_COPY")

        echo "Detected local project path: $ORIGINAL_WEBVIEW_URL. Copying entire project from $SOURCE_DIR to assets."
        cp -r "$SOURCE_DIR/." "$ASSETS_DIR/" || { echo "Error: Failed to copy local HTML assets from $SOURCE_DIR." ; exit 1; }

        WEBVIEW_URL="file:///android_asset/$FILENAME"
        echo "Updated WEBVIEW_URL to: $WEBVIEW_URL"
    fi

    DEFAULT_TRUSTED_ORIGIN=$(extract_origin "$WEBVIEW_URL" 2>/dev/null)
    if [ -n "$DEFAULT_TRUSTED_ORIGIN" ]; then
        if [ -z "$RESOLVED_TRUSTED_ORIGINS" ]; then
            RESOLVED_TRUSTED_ORIGINS="$DEFAULT_TRUSTED_ORIGIN"
        else
            RESOLVED_TRUSTED_ORIGINS="$DEFAULT_TRUSTED_ORIGIN $RESOLVED_TRUSTED_ORIGINS"
        fi
    fi

    if [ "$LOCAL_HTTPS_ASSETS" = true ]; then
        RESOLVED_TRUSTED_ORIGINS="$RESOLVED_TRUSTED_ORIGINS https://appassets.androidplatform.net"
    fi

    JAVA_TRUSTED_ORIGINS=""
    for ORIGIN in $RESOLVED_TRUSTED_ORIGINS; do
        if [ -n "$JAVA_TRUSTED_ORIGINS" ]; then
            JAVA_TRUSTED_ORIGINS="$JAVA_TRUSTED_ORIGINS, "
        fi
        JAVA_TRUSTED_ORIGINS="$JAVA_TRUSTED_ORIGINS\"$ORIGIN\""
    done

    APP_THEME="@android:style/Theme.DeviceDefault.NoActionBar"
    if [ -n "$BACKGROUND" ]; then
        APP_THEME="@style/AppTheme"
    fi
}

# Compiles Android resources and Java sources into classes.dex.
# @return None.
compile_android_sources () {
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
        "$SRC_DIR"/*.java || { echo "Error: JAVAC failed."; exit 1; }

    echo "Packaging .class files into temporary JAR..."
    case "$TEMP_JAR_FILE" in
        /*) ABS_TEMP_JAR_FILE="$TEMP_JAR_FILE" ;;
        *) ABS_TEMP_JAR_FILE="$(pwd)/$TEMP_JAR_FILE" ;;
    esac
    (cd "$TEMP_CLASSES_DIR" && jar cf "$ABS_TEMP_JAR_FILE" .) || { echo "Error: JAR creation failed."; exit 1; }

    echo "Generating Dalvik/ART bytecode..."
    TEMP_DEX_WORK_DIR="$TEMP_BUILD_DATA_DIR/temp_dex_work"
    mkdir -p "$TEMP_DEX_WORK_DIR"
    "$DX" --output "$TEMP_DEX_WORK_DIR" "$ABS_TEMP_JAR_FILE" --min-api "$MIN_SDK" || { rm -rf "$TEMP_DEX_WORK_DIR"; echo "Error: D8/DX failed." ; exit 1; }
    mv "$TEMP_DEX_WORK_DIR/classes.dex" "$DEX_FILE"
    rm -rf "$TEMP_DEX_WORK_DIR"
}

# Runs the complete KCAPK build using forwarded non-API arguments.
# @param $@ Forwarded public build arguments.
# @return None.
kcapk_build () {
    configure_build "$@"
    setup_sdk
    prepare_build_directories
    prepare_permissions
    prepare_share_targets
    prepare_executables
    generate_icons
    prepare_web_assets
    prepare_source_templates
    compile_android_sources

    if $RELEASE_MODE; then
        download_bundletool
        build_aab
        build_apk

        rm -f "$RES_DIR/temp_icon_file_base"
        rm -rf "$TEMP_ROOT_DIR"

        echo "DUAL BUILD COMPLETE for $DISPLAY_NAME. Both files are in $OUTPUT_DIR/."
        echo "APK Output: $DEBUG_APK_FILE"
        echo "AAB Output: $AAB_SIGNED_FILE"
        echo "INSTALL: adb install -r -t $DEBUG_APK_FILE"
        echo "UNINSTALL: adb uninstall $PACKAGE_NAME"
    else
        echo "Starting Debug APK flow for $DISPLAY_NAME."
        build_apk

        rm -f "$RES_DIR/temp_icon_file_base"
        rm -rf "$TEMP_ROOT_DIR"

        echo "APK Compiled! ($DISPLAY_NAME)"
        echo "APK Output: $DEBUG_APK_FILE"
        echo "INSTALL: adb install -r -t $DEBUG_APK_FILE"
        echo "UNINSTALL: adb uninstall $PACKAGE_NAME"
    fi
}
