# Windows shared-core integration

This branch experiments with making the desktop conversion engine host-independent so the
same azooKey desktop behavior can be used from both macOS and Windows.

Initial constraints:

- Keep platform APIs out of conversion logic.
- Resolve filesystem/resource locations in the platform host and inject them.
- Keep the existing macOS behavior unchanged while introducing the shared boundary.
- Do not expose Swift implementation details as the Windows transport contract.
- Preserve upstream compatibility by landing the work as small, reviewable steps.

The first building block is `ConverterEngineEnvironment`, which carries host-resolved
storage and resource locations without embedding macOS App Group assumptions in shared code.
