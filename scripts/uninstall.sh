#!/bin/bash
# kcapk uninstall tool
# Summary: Uninstalls a built package from a connected Android device.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU General Public License v3.0

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
REPO_DIR="$ROOT_DIR"

# Extracts the value of a flat JSON key from a file.
# @param file JSON file (flat).
# @param key Key name (without quotes).
# @return 0 on success; the value is written to stdout.
json_get() {
    local file="$1" key="$2"
    awk -v key="\"$key\"" '
    {
        buf = buf " " $0
    }
    END {
        if (match(buf, key "[[:space:]]*:[[:space:]]*")) {
            s = substr(buf, RSTART + RLENGTH)
            if (substr(s, 1, 1) == "\"") {
                s = substr(s, 2)
                if (match(s, /^[^"]*/)) {
                    print substr(s, 1, RLENGTH)
                }
            }
        }
    }' "$file"
}

# Prints the first positional project name from the arguments.
# @param args Command-line arguments.
# @return 0 on success; the name is written to stdout.
resolve_name() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help) ;;
            *)
                printf '%s\n' "$arg"
                return 0
                ;;
        esac
    done
    return 0
}

# Uninstalls the package for the requested project.
# @return 0 on success.
main() {
    local name config package arg

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                echo "Usage: uninstall.sh [PROJECT_NAME]"
                echo "  PROJECT_NAME  Package to uninstall (default: demo)."
                exit 0
                ;;
        esac
    done

    name=$(resolve_name "$@")
    name=${name:-demo}
    config="$REPO_DIR/proj/$name/config.json"

    [ -f "$config" ] || { echo "error: config not found: $config" >&2; exit 1; }

    package=$(json_get "$config" package_name)
    package=${package:-com.kaisarcode.$name}

    echo "Uninstalling $package"
    adb uninstall "$package"
}

main "$@"
