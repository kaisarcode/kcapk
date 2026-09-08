#!/bin/sh
# Summary: Compiles the generated demo Provisioner with its manifest URL pointed at a local test server, then runs the provisioning logic scenarios on the JVM.
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU General Public License v3.0

set -eu

KC_REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KC_TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATED_DIR="$KC_TEST_DIR/generated"
BUILD_DIR="$KC_TEST_DIR/build"

# Prints a free loopback TCP port for the local manifest server.
# @return The selected port number.
select_port() {
    port="${TEST_PORT:-}"
    if [ -z "$port" ]; then
        if command -v python3 >/dev/null 2>&1; then
            port=$(python3 -c 'import socket
s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
        else
            port=18081
        fi
    fi
    echo "$port"
}

# Creates empty scratch directories for the compiled test sources.
# @return None.
prepare_directories() {
    rm -rf "$GENERATED_DIR" "$BUILD_DIR"
    mkdir -p "$GENERATED_DIR" "$BUILD_DIR"
}

# Regenerates the demo app and points the Provisioner at the local test server.
# @param $1 Local port for the manifest server.
# @return None.
generate_provisioner() {
    "$KC_REPO_DIR/build.sh" demo >/dev/null 2>&1
    sed -e "s|APP_MANIFEST_URL = \"[^\"]*\"|APP_MANIFEST_URL = \"http://127.0.0.1:${1}/update/provision/manifest.json\"|" \
        "$KC_REPO_DIR/projects/demo/app/src/main/java/com/kaisarcode/demo/Provisioner.java" \
        > "$GENERATED_DIR/Provisioner.java"
}

# Compiles the harness shims and the generated Provisioner source.
# @return None.
compile_sources() {
    find "$KC_TEST_DIR/src" "$GENERATED_DIR" -name '*.java' > "$BUILD_DIR/sources.txt"
    javac -d "$BUILD_DIR/classes" @"$BUILD_DIR/sources.txt" 2>&1
}

# Runs the provisioning scenarios against the local test server.
# @param $1 Local port for the manifest server.
# @return None.
run_provision_tests() {
    java ${TEST_JAVA_OPTS:+"$TEST_JAVA_OPTS"} "-Dtest.port=$1" -cp "$BUILD_DIR/classes" com.kaisarcode.demo.ProvisionTest
}

# Runs the provisioning harness end to end.
# @return None.
main() {
    port="$(select_port)"
    prepare_directories
    generate_provisioner "$port"
    compile_sources
    run_provision_tests "$port"
}

main
