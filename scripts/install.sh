#!/bin/bash
# kcapk install tool
# Summary: Installs a built APK from dist onto a connected Android device.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU General Public License v3.0

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
DIST_DIR="$ROOT_DIR/dist"

# Prints the first positional project name from the arguments.
# @param args Command-line arguments.
# @return 0 on success; the name is written to stdout.
resolve_name() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help|-r|-t|-g) ;;
            *)
                printf '%s\n' "$arg"
                return 0
                ;;
        esac
    done
    return 0
}

# Installs the built APK for the requested project.
# @return 0 on success.
main() {
    local name apk adb_args arg

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                echo "Usage: install.sh [PROJECT_NAME] [-r] [-t] [-g]"
                echo "  PROJECT_NAME  Build to install (default: demo)."
                echo "  -r            Replace existing app."
                echo "  -t            Allow test APKs."
                echo "  -g            Grant all runtime permissions."
                exit 0
                ;;
        esac
    done

    name=$(resolve_name "$@")
    name=${name:-demo}
    apk="$DIST_DIR/$name/$name.apk"

    [ -f "$apk" ] || { echo "error: APK not found: $apk" >&2; exit 1; }

    adb_args=()
    for arg in "$@"; do
        case "$arg" in
            -r|-t|-g) adb_args+=("$arg") ;;
        esac
    done

    echo "Installing $apk"
    adb install "${adb_args[@]}" "$apk"
}

main "$@"
