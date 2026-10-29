# Advanced documentation

These pages explain KCAPK's internal design and integration boundaries. To build a first application, start with [Getting started](../getting_started.md). For ordinary build options, use [Configuration](../configuration.md).

## Architecture and integration

- [Architecture](../architecture.md) - build pipeline, generated Android application, and component boundaries.
- [NativeBridge](../native_bridge.md) - JavaScript/native interface, trust model, and error conventions.
- [Async operations](../async.md) - Promise requests, page lifecycle, completion, and cancellation.
- [Native extensions](extensions.md) - compose application-owned Java code, resources, and manifest declarations.

## Development and verification

- [Testing](../testing.md) - integration tests, test APK, and manual device checks.
- [Android API reference](../apis/readme.md) - method-level documentation for individual Android capabilities.
- [External binaries](../external_binaries.md) - ABI selection, packaging, process execution, and lifecycle.

## Next step

Continue with [architecture](../architecture.md).
