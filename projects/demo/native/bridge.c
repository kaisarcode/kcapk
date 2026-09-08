/**
 * bridge.c - Project JNI entry points for the redp2p demo.
 * Summary: Maps the demo's explicit native API to libredp2p.
 * Author:  KaisarCode
 * Website: https://kaisarcode.com
 * License: GNU General Public License v3.0
 */

#include <jni.h>
#include <stdint.h>

#include "libredp2p.h"

/**
 * Returns the redp2p build version linked into this application.
 * @param env JNI environment.
 * @param type NativeBridge class.
 * @return Build timestamp from libredp2p.
 */
JNIEXPORT jlong JNICALL Java_com_kaisarcode_demo_NativeBridge_nativeRedp2pVersion(
JNIEnv *env,
jclass type
) {
    (void)env;
    (void)type;
    return (jlong)redp2p_version();
}
