# Advanced documentation

These pages explain KCAPK's internal design and integration boundaries. To build a first application, start with [Getting started](../GETTING_STARTED.md). For ordinary build options, use [Configuration](../CONFIGURATION.md).

## Architecture and integration

- [Architecture](../ARCHITECTURE.md) - build pipeline, generated Android application, and component boundaries.
- [NativeBridge](../NATIVE_BRIDGE.md) - JavaScript/native interface, trust model, and error conventions.
- [Async operations](../ASYNC.md) - Promise requests, page lifecycle, completion, and cancellation.
- [Native extensions](extensions.md) - compose application-owned Java code, resources, and manifest declarations.

## Development and verification

- [Testing](../TESTING.md) - integration tests, test APK, and manual device checks.
- [Android API reference](../apis/README.md) - method-level documentation for individual Android capabilities.
- [External binaries](../EXTERNAL_BINARIES.md) - ABI selection, packaging, process execution, and lifecycle.

## Next step

- [Architecture](../ARCHITECTURE.md) - understand how the generated app is assembled.
