KCAPK ANDROID REFACTOR PLAN

Purpose

Refactor kcapk so that Android applications use project-specific native integration without a shared kclib runner, shared JNI ABI, or runtime-updated native libraries.

The general kcapk build system remains responsible for Android application construction, packaging, signing, common WebView infrastructure, common AndroidBridge behavior, web asset provisioning, and automatic preparation of declared kclib dependencies.

Project-specific native behavior belongs to the project.

The intended final architecture is:

WebView / JavaScript
    |
    +-- AndroidBridge
    |     Common Android capabilities provided by kcapk.
    |
    +-- NativeBridge
          Project-specific application interface.
              |
              +-- Project JNI code
                      |
                      +-- Project kclib dependencies
                      +-- Other native dependencies when explicitly required


CORE DESIGN DECISIONS

[DECIDED] kclibs remain independent pure C libraries.

[DECIDED] There is no common kclib runtime ABI.

[DECIDED] There is no requirement that all kclibs expose the same API.

[DECIDED] Existing API consistency such as open, close, stop, and options conventions may remain where natural, but it is not a common ABI contract.

[DECIDED] kcrun.c is no longer part of the active design.

[DECIDED] jni.c and libjni.so are no longer part of the active design.

[DECIDED] Android applications do not use kc_<name>_run or a JSON runner.

[DECIDED] Android applications ship the native libraries they were built against inside the APK/AAB.

[DECIDED] Native .so files are not independently updated at runtime.

[DECIDED] Updating a native dependency requires rebuilding the application when necessary.

[DECIDED] Web assets may continue to use the existing remote update/provisioning model.

[DECIDED] manifest.json may keep the "kclib" field.

[DECIDED] "kclib" means build-time kclib dependencies only.

[DECIDED] "kclib" does not define a runtime whitelist, runner interface, common ABI, or automatic JavaScript API.

[DECIDED] kclib dependencies are resolved from the canonical kclib dist layout.

[DECIDED] For a dependency NAME, the canonical inputs are:

    KCLIB_DIST/NAME.c/source.zip
    KCLIB_DIST/NAME.c/aarch64/android/libNAME.so
    KCLIB_DIST/NAME.c/armv7/android/libNAME.so

[DECIDED] source.zip is the canonical build-time source/header package.

[DECIDED] The public kclib header is expected under:

    src/libNAME.h

inside source.zip.

[DECIDED] build.sh must automate dependency preparation so project authors and code agents do not manually copy headers or native binaries.

[DECIDED] AndroidBridge remains a common kcapk bridge.

[DECIDED] NativeBridge remains separate from AndroidBridge.

[DECIDED] NativeBridge represents project-specific application functionality.

[DECIDED] NativeBridge must not contain generic kclib knowledge.

[DECIDED] Project JNI code may call any APIs explicitly chosen by that project, including kclibs and custom native libraries.

[DECIDED] No interface is generated automatically from native symbols or headers.

[DECIDED] Automatic work belongs in build.sh when it can be derived deterministically from manifest.json and the canonical dist layout.

[DECIDED] Semantic application integration remains explicit project code.


TARGET PROJECT MODEL

A project should remain small and predictable.

Canonical conceptual layout:

projects/PROJECT/
    config.json
    manifest.json
    assets/
    native/
        NativeBridge.java or equivalent project bridge source
        bridge.c or equivalent project JNI source

Generated Android application files remain under:

projects/PROJECT/app/

Do not require projects to manually vendor extracted kclib headers.

Do not require projects to manually copy kclib .so files.

Do not add a project-local dependency registry duplicating manifest.json.

Do not introduce a second metadata file for native APIs.


MANIFEST CONTRACT

Example:

{
  "kclib": ["redp2p"],
  "start": "www/index.html"
}

Meaning of "kclib":

For every NAME listed in "kclib", build.sh must prepare NAME as a native build dependency of this application.

It must not imply anything else.

Specifically, the field must not:

- generate NativeBridge methods;
- generate JNI entry points;
- generate JSON commands;
- generate dlopen dispatch;
- generate dlsym dispatch;
- expose the library to JavaScript automatically;
- create a runtime allowlist;
- enable runtime native updates;
- force a common ABI.


KCLIB DEPENDENCY RESOLUTION

For every NAME in manifest.json:kclib:

1. Resolve the canonical distribution directory:

   KCLIB_DIST/NAME.c/

2. Require:

   source.zip
   aarch64/android/libNAME.so
   armv7/android/libNAME.so

3. Fail clearly if a required artifact is missing.

4. Extract source.zip into build staging.

5. Require the expected public header:

   extracted/NAME.c/src/libNAME.h

   or the equivalent path produced by the canonical source.zip layout.

6. Add the extracted src directory to the native compiler include path.

7. Stage the Android .so for each supported ABI.

8. Package those .so files into the APK/AAB as native libraries.

9. Do not package source.zip into the final APK.

10. Do not package extracted headers into the final APK.

11. Do not mutate the canonical kclib dist tree.

12. Do not copy headers permanently into the project source tree.


ANDROID ABI MAPPING

Current kclib dist names:

aarch64
armv7

Android package ABI names:

aarch64 -> arm64-v8a
armv7   -> armeabi-v7a

The build must own this mapping centrally.

Project code must not duplicate it.


NATIVE LIBRARY PACKAGING

Native libraries must be packaged as APK/AAB native libraries, not as generic assets that are copied into codeCacheDir at runtime.

Target conceptual APK layout:

lib/arm64-v8a/libredp2p.so
lib/armeabi-v7a/libredp2p.so

plus the project JNI shared library if one exists.

Do not preserve the old behavior where kclib .so files are:

- stored under assets/kclib;
- described by an embedded kclib manifest;
- copied into codeCacheDir;
- compared against a remote kclib manifest;
- replaced independently at runtime.


PROJECT JNI MODEL

JNI is project-specific.

There is no generic libjni.so.

There is no common JNI API required across projects.

A project that needs native functionality provides its JNI implementation in the canonical project-native location.

The project JNI code may include prepared kclib headers directly:

#include "libredp2p.h"

The build system supplies the correct include path automatically.

The project JNI code may directly use the actual C API of the dependency.

Prefer normal compile/link-time use of explicitly declared native dependencies.

Do not introduce generic:

- dlopen-by-name APIs;
- dlsym-by-name APIs;
- native reflection;
- JSON dispatchers;
- command registries;
- kc_<name>_run compatibility layers;
- common native runner ABIs.

If a project has no JNI code, the build must continue to work without creating fake JNI plumbing.


ANDROIDBRIDGE

AndroidBridge remains common infrastructure owned by kcapk.

Preserve common Android functionality that is genuinely shared across applications.

Current examples include Android-specific utility behavior such as:

- platform interaction;
- common application information;
- connectivity helpers;
- common trusted-origin enforcement where currently implemented.

Review actual implementation before deciding which existing methods remain.

Do not move project-specific native APIs into AndroidBridge.

AndroidBridge must not know about:

- redp2p;
- grd;
- llm;
- kclib manifests;
- project-specific C functions;
- project-specific JNI interfaces.


NATIVEBRIDGE

NativeBridge remains separate from AndroidBridge.

NativeBridge is the project-specific application bridge.

Its role is to expose only the native capabilities intentionally defined by the project.

A project may use NativeBridge to call:

- its JNI implementation;
- kclib APIs through its JNI implementation;
- custom native libraries;
- custom application-native code.

NativeBridge must not automatically expose a library merely because it is listed in manifest.json:kclib.

No native API discovery.

No automatic method generation from headers.

No automatic method generation from exported symbols.

No universal run method.

No generic runKclib method.

No KclibBridge class.


JAVASCRIPT BRIDGE MODEL

The JavaScript-facing application API is project-specific.

The project defines the interface it wants JavaScript to see.

The common kcapk layer may provide transport/plumbing when useful, but it must not define application semantics.

The project interface should be explicit and inspectable.

A project that uses redp2p may expose only the redp2p operations that the application actually needs.

A different project may expose an entirely unrelated API.

A project using a non-kclib native dependency must be allowed to define its own bridge in the same way.

Do not require all projects to implement the same NativeBridge method set.


WEB ASSET PROVISIONING

Keep the useful web asset update behavior unless a concrete defect requires changing it.

The remote updater may continue to handle:

- HTML;
- JavaScript;
- CSS;
- images;
- other application assets whose compatibility is not tied to the native ABI.

Separate this logic from native library provisioning.

Provisioner must no longer manage kclib native libraries.

Provisioner must no longer:

- read a remote kclib manifest;
- choose between embedded and remote .so versions;
- install native libraries;
- chmod native libraries;
- load libjni.so;
- prepare a kclib whitelist;
- expose nativeLoadError for the generic JNI runner.


BUILD.SH RESPONSIBILITIES AFTER REFACTOR

build.sh remains the general Android builder.

It should continue owning:

- project selection;
- config.json reading;
- manifest.json reading;
- Android SDK setup;
- Android build tools setup;
- resources;
- icons;
- AndroidManifest.xml generation;
- common Java shell generation;
- AndroidBridge generation or inclusion;
- TrustedWebViewClient;
- WebView setup;
- common splash UI;
- web asset staging;
- web asset fingerprinting;
- web asset provisioning;
- Java compilation;
- project native compilation;
- kclib dependency preparation;
- native ABI packaging;
- DEX generation;
- APK generation;
- AAB generation;
- debug signing;
- optional release signing;
- publication of application web assets and APK artifacts.

It must not own project-specific native semantics.


REMOVE OLD GENERIC KCLIB RUNTIME BEHAVIOR

Remove from build.sh and generated code:

- KCLIB_MANIFEST_URL when used for runtime native updates;
- KCLIB_BRIDGE_PACKAGE;
- KCLIB_BRIDGE_DIR;
- KCLIB_BRIDGE_FILE;
- generic KclibBridge.java generation;
- generic NativeBridge.runKclib behavior;
- libjni.so staging;
- jni.c special-case staging;
- generated AndroidManifest allowed_kclibs metadata;
- prepareNative();
- ensureNative();
- nativeLoadError();
- declaredKclibs();
- declaredKclibList();
- readEmbeddedKclibManifest();
- findEmbeddedRecord();
- findKclibRecord();
- nativePending();
- native .so Pending provisioning entries;
- runtime native .so downloading;
- runtime native .so replacement;
- runtime native .so chmod;
- setWhitelist();
- runKclib();
- kc_<name>_run assumptions.

Before deleting a symbol or helper, confirm its actual current references.


KEEP OR REFACTOR, DO NOT BLINDLY DELETE

The following areas may contain useful common behavior and must be inspected before modification:

- JSBridge.java;
- AndroidBridge registration;
- NativeBridge request/response plumbing;
- MainActivity.java;
- TrustedWebViewClient.java;
- Provisioner.java;
- splash.js;
- splash.html;
- app asset update logic;
- trusted origin handling.

Remove only the parts tied to the discarded generic kclib runtime.

Preserve unrelated working behavior.


PROJECT NATIVE BUILD

Define one canonical project-native source location.

Preferred initial convention:

projects/PROJECT/native/

The exact files supported should be explicit.

Start with the smallest practical contract.

For example:

projects/PROJECT/native/bridge.c
projects/PROJECT/native/NativeBridge.java

Do not invent multiple equivalent locations.

Do not recursively guess arbitrary native project layouts.

If the canonical file does not exist, skip that integration cleanly.

If project native code exists, compile it for each supported Android ABI.

The native compiler invocation must include:

- Android NDK JNI headers;
- platform-specific JNI headers;
- extracted src directories for declared kclib dependencies;
- explicit project-native include directories if a canonical one is later required.

Do not add a build framework solely for this refactor if the existing build can compile the required native source directly.


LINKING POLICY

Prefer explicit linking of project JNI code against its declared native dependencies when practical.

This makes dependency mismatches visible during build/link instead of postponing them to dynamic runtime dispatch.

Do not add generic runtime loading merely to preserve the old architecture.

If Android packaging/loading constraints require a different mechanism for a concrete library, solve that concrete case explicitly and document it.


CUSTOM NATIVE DEPENDENCIES

Do not design a complete generic custom-native packaging system during this refactor unless required by an actual project.

The immediate canonical automation applies to manifest.json:kclib because kclib already has a stable dist layout.

Project JNI code may still contain custom native implementation.

If a real application later needs an external custom .so package, define the smallest explicit extension based on that real case.

Do not distort the kclib dependency contract to anticipate every possible third-party library layout.


SOURCE.ZIP RULES

source.zip is build input only.

Treat it as the source of truth corresponding to the distributed binaries.

Do not modify it.

Do not rebuild kclib binaries from source.zip as part of normal kcapk builds.

Use the distributed Android .so artifacts.

Use source.zip to obtain headers and any compile-time definitions required by the project JNI.

Fail if the expected public header is absent.

Do not silently search arbitrary files for a replacement header.


VERSION AND ABI POLICY

Do not add a common kclib ABI version.

Do not add per-library ABI negotiation during this refactor.

The APK and its native dependencies are one release unit.

A project is built against the headers and .so files currently selected from the canonical dist tree.

If a kclib API changes incompatibly, rebuild the affected application.

Do not independently update the .so in an already released APK.


PUBLICATION MODEL

The published APK/AAB contains the native dependency versions it was built against.

Remote publication of application web assets may remain separate.

Do not publish native dependency updates for an existing APK through the web asset updater.


ERROR MODEL

Build-time dependency errors must fail clearly.

Examples:

missing kclib dist directory
missing source.zip
missing public header
missing Android .so for required ABI
native compilation failure
native link failure
APK native packaging failure

Do not silently omit a declared native dependency.

Runtime NativeBridge errors remain project-specific unless they are transport-level errors owned by common bridge plumbing.


SECURITY BOUNDARY

AndroidBridge exposes only common Android authority intentionally provided by kcapk.

NativeBridge exposes only project-defined authority.

Declaring a kclib dependency does not grant JavaScript access to it.

Native code must not be discoverable through a generic bridge.

Do not expose:

- arbitrary native symbol invocation;
- arbitrary JNI invocation;
- arbitrary shared-library loading;
- a generic terminal;
- a generic kclib runner.

Trusted-origin checks must remain effective for JavaScript interfaces.

Do not weaken existing WebView origin restrictions as part of the native dependency refactor.


DOCUMENTATION POLICY

Do not update README first.

Implement and verify the effective design first.

After behavior is stable:

- update kcapk README;
- update kcapk AGENTS.md;
- remove stale documentation about libjni.so;
- remove stale documentation about generic KclibBridge;
- remove stale documentation about native .so runtime updates;
- document the new meaning of manifest.json:kclib;
- document the canonical project-native integration location;
- document that APK + native .so dependencies form one release unit.

Documentation must describe actual implemented behavior only.


TASK TRACKER

Current implementation status: deterministic kclib packaging, the project-native demo bridge, APK/AAB inspection, and Android device validation are complete. Removal of the obsolete generic runtime generator and final documentation remain in progress.

PHASE 0 - BASELINE INSPECTION

[x] Read current kcapk AGENTS.md and project-local instructions.
[x] Read current README.md.
[x] Read full build.sh.
[x] Read current demo manifest.json.
[x] Read current demo config.json.
[x] Read current generated MainActivity.java.
[x] Read current generated JSBridge.java.
[x] Read current generated NativeBridge.java.
[x] Read current generated KclibBridge.java.
[x] Read current Provisioner.java.
[x] Read current TrustedWebViewClient.java.
[x] Read splash.js and splash.html.
[x] Inspect current APK/AAB native packaging behavior.
[x] Identify all references to libjni.so.
[x] Identify all references to KclibBridge.
[x] Identify all references to runKclib.
[x] Identify all references to allowed_kclibs.
[x] Identify all runtime kclib manifest/provisioning code.
[x] Record current demo behavior before edits.


PHASE 1 - DEFINE CANONICAL PROJECT NATIVE INPUT

[ ] Choose and document in code comments the single canonical project native directory.
[ ] Prefer projects/PROJECT/native/ unless current project structure gives a concrete reason otherwise.
[ ] Define exactly which project-native source files build.sh recognizes.
[ ] Ensure projects with no native integration continue to build.
[ ] Do not add alternative source layouts.


PHASE 2 - KCLIB BUILD DEPENDENCY PREPARATION

[x] Preserve manifest.json:kclib parsing.
[x] Redefine its implementation as build-time dependency selection only.
[x] Resolve KCLIB_DIST_DIR from existing config/default behavior.
[x] For each NAME, require KCLIB_DIST_DIR/NAME.c/source.zip.
[x] For each NAME, require aarch64/android/libNAME.so.
[x] For each NAME, require armv7/android/libNAME.so.
[x] Create temporary dependency extraction directories under the existing build temp root.
[x] Extract source.zip without modifying dist.
[x] Locate src/libNAME.h deterministically.
[x] Add the extracted src directory to native compile includes.
[x] Stage the required .so files for Android native packaging.
[x] Fail clearly on missing dependency inputs.
[x] Do not copy headers permanently into projects/PROJECT/.


PHASE 3 - REMOVE GENERIC JNI RUNTIME

[ ] Stop staging jni.c.
[ ] Stop staging libjni.so.
[ ] Remove KclibBridge.java generation.
[ ] Remove KCLIB_BRIDGE_PACKAGE variables.
[ ] Remove KCLIB_BRIDGE_DIR variables.
[ ] Remove KCLIB_BRIDGE_FILE variables.
[ ] Remove generic setWhitelist JNI calls.
[ ] Remove generic run JNI calls.
[ ] Remove all kc_<name>_run assumptions.
[ ] Remove AndroidManifest allowed_kclibs metadata generation.
[ ] Remove generic native-load state associated with libjni.so.
[ ] Confirm no generated Java code still references KclibBridge.


PHASE 4 - REMOVE NATIVE LIBRARY RUNTIME PROVISIONING

[ ] Remove embedded assets/kclib generation.
[ ] Remove embedded kclib manifest generation.
[ ] Remove runtime kclib manifest fetching when used only for .so updates.
[ ] Remove nativePending().
[ ] Remove findEmbeddedRecord().
[ ] Remove findKclibRecord().
[ ] Remove readEmbeddedKclibManifest().
[ ] Remove declaredKclibs() if no longer used elsewhere.
[ ] Remove declaredKclibList() if no longer used elsewhere.
[ ] Remove ensureNative().
[ ] Remove prepareNative().
[ ] Remove nativeLoadError().
[ ] Remove native .so copy-to-codeCacheDir behavior.
[ ] Remove native .so runtime chmod behavior.
[ ] Remove native .so update comparison by timestamps.
[ ] Preserve web asset provisioning behavior.
[ ] Re-read Provisioner after cleanup and remove dead imports/state only when actually unused.


PHASE 5 - PACKAGE NATIVE LIBRARIES AS APK/AAB NATIVE LIBS

[x] Determine the existing aapt2/bundletool path for native library packaging.
[x] Add canonical ABI mapping:
    aarch64 -> arm64-v8a
    armv7 -> armeabi-v7a
[x] Package libNAME.so under the correct Android ABI directory.
[x] Ensure APK contains each declared kclib .so.
[x] Ensure AAB contains each declared kclib .so.
[x] Ensure source.zip is not packaged.
[x] Ensure extracted headers are not packaged.
[x] Ensure obsolete assets/kclib entries are absent.


PHASE 6 - PROJECT-SPECIFIC JNI COMPILATION

[x] Add build support for the canonical project JNI source.
[x] Compile project JNI for aarch64.
[x] Compile project JNI for armv7.
[x] Add extracted kclib src directories to include paths.
[x] Link against declared kclib Android libraries when required by the project code.
[x] Produce one project JNI shared library per ABI when project JNI exists.
[x] Package the project JNI shared library correctly.
[ ] Do not create project JNI artifacts for projects that do not provide native code.
[ ] Do not introduce a generic JNI API.


PHASE 7 - ANDROIDBRIDGE CLEANUP

[ ] Preserve AndroidBridge as common kcapk functionality.
[ ] Audit its current methods.
[ ] Remove only stale kclib-specific behavior if any exists.
[ ] Preserve trusted-origin enforcement.
[ ] Preserve useful Android-common capabilities.
[ ] Do not add project-specific APIs to AndroidBridge.


PHASE 8 - NATIVEBRIDGE REDEFINITION

[ ] Preserve NativeBridge as a separate concept from AndroidBridge.
[ ] Remove runKclib-specific implementation.
[ ] Identify reusable async request/response plumbing, if any.
[ ] Keep common transport plumbing only when it remains useful independently of kclib.
[ ] Make project-specific NativeBridge behavior come from the canonical project integration.
[ ] Ensure NativeBridge does not automatically expose declared kclibs.
[ ] Ensure projects may define arbitrary application-specific native APIs.
[ ] Ensure a project can choose not to expose NativeBridge functionality at all.


PHASE 9 - DEMO MIGRATION USING REDP2P

[x] Keep demo manifest.json with "kclib": ["redp2p"].
[x] Use /home/kaisar/work/kclib/dist/redp2p.c/source.zip as the canonical header source.
[x] Use aarch64/android/libredp2p.so.
[x] Use armv7/android/libredp2p.so.
[x] Compile demo project JNI against libredp2p.h.
[x] Define only the redp2p functionality that demo actually needs.
[x] Remove generic runKclib JavaScript usage from demo.
[x] Remove generic KclibBridge assumptions from demo.
[x] Confirm demo NativeBridge is project-specific.
[x] Confirm redp2p itself remains unchanged.


PHASE 10 - WEB PROVISIONER REGRESSION CHECK

[ ] Confirm embedded www assets still install on first run.
[ ] Confirm www fingerprint behavior still works.
[ ] Confirm remote web manifest checking still works.
[ ] Confirm updated web assets still download.
[ ] Confirm SHA-256 verification still works.
[ ] Confirm offline fallback still works.
[ ] Confirm splash status reporting still works.
[ ] Confirm splash progress reporting still works.
[ ] Confirm splash warning reporting still works.
[ ] Confirm no native dependency is downloaded by Provisioner.


PHASE 11 - BUILD VERIFICATION

[x] Build demo APK.
[x] Build demo AAB.
[x] Verify Java compilation succeeds.
[x] Verify project JNI compilation succeeds for aarch64.
[x] Verify project JNI compilation succeeds for armv7.
[x] Verify native link succeeds for both ABIs.
[x] Inspect APK contents.
[x] Confirm arm64-v8a native libraries are present.
[x] Confirm armeabi-v7a native libraries are present.
[x] Confirm libjni.so is absent.
[x] Confirm obsolete kclib asset copies are absent.
[x] Confirm source.zip is absent from APK.
[x] Confirm extracted headers are absent from APK.
[x] Inspect AAB native library contents.
[x] Preserve existing signing behavior.


PHASE 12 - ANDROID RUNTIME VERIFICATION

[x] Install demo APK on a supported Android device/emulator.
[x] Confirm application starts.
[x] Confirm WebView loads embedded/current assets.
[ ] Confirm AndroidBridge still works.
[ ] Confirm trusted-origin restrictions still work.
[x] Confirm project NativeBridge loads.
[x] Confirm project JNI loads.
[x] Confirm libredp2p.so resolves correctly.
[x] Exercise the specific redp2p API exposed by demo.
[ ] Confirm no generic runner path exists.
[ ] Confirm no runtime native-library updater is used.
[ ] Confirm web asset updates still work independently.


PHASE 13 - CLEAN DEAD BUILD CODE

[ ] Search build.sh for KCLIB_MANIFEST_URL.
[ ] Keep it only if still used for a real remaining purpose.
[ ] Search build.sh for libjni.
[ ] Require zero active references.
[ ] Search generated Java templates for KclibBridge.
[ ] Require zero active references.
[ ] Search for runKclib.
[ ] Require zero active references.
[ ] Search for allowed_kclibs.
[ ] Require zero active references.
[ ] Search for assets/kclib.
[ ] Require zero active references.
[ ] Remove imports made unused by the refactor.
[ ] Remove variables made unused by the refactor.
[ ] Do not perform unrelated cleanup.


PHASE 14 - DOCUMENT EFFECTIVE DESIGN

[ ] Update README.md only after implementation and runtime behavior are known.
[ ] Update AGENTS.md to describe the new ownership boundaries.
[ ] Document manifest.json:kclib as build-time dependency selection.
[ ] Document canonical kclib dist resolution.
[ ] Document source.zip header extraction.
[ ] Document project-native integration location.
[ ] Document AndroidBridge versus NativeBridge.
[ ] Document that native dependencies ship with the APK.
[ ] Document that changing an incompatible native API requires an app rebuild.
[ ] Remove documentation about generic libjni.so.
[ ] Remove documentation about runKclib.
[ ] Remove documentation about runtime .so updating.
[ ] Do not document speculative custom dependency machinery.


NON-GOALS

Do not:

- restore kcrun;
- restore jni.c;
- create another common kclib ABI;
- add run.h back to kclibs;
- add kc_<name>_run;
- generate bindings from C headers;
- inspect .so symbols to generate bindings;
- create a native reflection system;
- create a generic dlopen/dlsym runtime;
- create a JSON runner;
- create a common command protocol;
- add ABI negotiation infrastructure;
- independently update native .so files;
- redesign kclib APIs;
- modify kclib projects as part of this refactor;
- create a framework for arbitrary third-party native dependencies without a concrete need;
- replace the existing Android build system with Gradle or another framework merely for architectural preference;
- clean build artifacts or build directories unless explicitly authorized.


COMPATIBILITY REQUIREMENTS

Preserve unless a concrete change requires otherwise:

- ./build.sh PROJECT_NAME invocation;
- current config.json semantics unrelated to removed native runner behavior;
- manifest.json:start;
- manifest.json:kclib field name;
- APK output location;
- AAB output location;
- debug signing behavior;
- release signing behavior;
- common WebView behavior;
- AndroidBridge behavior not tied to kclib runtime;
- trusted-origin behavior;
- web asset update behavior;
- splash/progress behavior;
- published web asset layout where practical.


AGENT EXECUTION RULES

Work only in kcapk unless explicitly instructed otherwise.

Do not modify kclib source repositories.

Use the canonical kclib dist artifacts as immutable inputs.

Do not run make clean.

Do not delete existing build directories, caches, generated artifacts, or binaries unless explicitly authorized.

Do not add dependencies or build frameworks without explicit approval.

Before each edit:

1. inspect the affected current implementation;
2. identify the obsolete generic-runner behavior being removed or the exact new deterministic build behavior being added;
3. make the smallest stable change;
4. preserve unrelated behavior.

Do not rewrite build.sh wholesale.

Prefer incremental extraction/removal of the obsolete runtime path.

After each phase, perform the strongest practical local verification before proceeding.

If a proposed change begins recreating a generic runtime, dispatcher, reflection layer, or API-description system, stop and return to the project-specific integration requirement.


COMPLETION CRITERIA

The refactor is complete when:

- kcapk still provides one general Android build.sh;
- manifest.json:kclib still selects kclib dependencies;
- build.sh automatically resolves source.zip and Android .so artifacts;
- project authors do not manually manage kclib headers;
- project authors do not manually copy kclib .so files;
- JNI behavior is project-specific;
- NativeBridge behavior is project-specific;
- AndroidBridge remains common;
- declared kclibs are not automatically exposed to JavaScript;
- no generic kclib runner exists;
- no KclibBridge exists;
- no libjni.so exists;
- no kc_<name>_run contract exists;
- no native .so is updated independently at runtime;
- native libraries are shipped with the APK/AAB;
- web asset updating still works;
- demo successfully uses redp2p through its own project integration;
- APK and AAB contain the correct native libraries for both Android ABIs;
- documentation matches the implemented system;
- no kclib source project was changed to satisfy Android.
