#!/bin/sh
# build.sh
# Summary: Generic Android WebView APK/AAB builder entrypoint.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: https://www.gnu.org/licenses/lgpl-3.0.html

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
KCAPK_BUILD_DIR="$SCRIPT_DIR/src/build"
# shellcheck disable=SC2034
KCAPK_TEMPLATE_SOURCE_DIR="$SCRIPT_DIR/src/templates"
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kcapk-build.XXXXXX")

# Cleans up the temporary working directory.
# @return None.
# shellcheck disable=SC2317
cleanup () {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

for MODULE in apis config sdk permissions executables templates package pipeline; do
    MODULE_FILE="$KCAPK_BUILD_DIR/$MODULE.sh"
    [ -f "$MODULE_FILE" ] || { echo "Error: Internal build module not found: $MODULE_FILE" >&2; exit 1; }
    # shellcheck disable=SC1090
    . "$MODULE_FILE"
done

prepare_api_build "$@"
# shellcheck disable=SC2034
KCAPK_SRC_DIR="$WORK_DIR/templates"

eval "kcapk_build$RUN_ARGS"
STATUS=$?
exit "$STATUS"
