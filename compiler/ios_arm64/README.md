# iOS arm64 backend

iOS currently shares `compiler/macos_arm64/macho_arm64_self.k`. The emitter
selects iOS load commands and UIKit linking with:

```text
macho_host --target ios-sim-arm64 --ir input.kir output
macho_host --target ios-device-arm64 --ir input.kir output
```

This avoids a 400 KB fork of the arm64 code generator. Target-specific code
stays behind explicit profiles. Simulator comes first; device signing follows.
