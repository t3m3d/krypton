# Krypton 2.4.8 language support

VS Code extension for Krypton, KryptScript, and Objective-K. Supports `.k`, `.ks`,
and `.htk` files with highlighting, bracket matching, comments, and snippets.
New snippets and completions use `print(...)`. Legacy `kp` remains highlighted.
Objective-K objects, protocols, methods, and requirements have declaration scopes.

## Language server

With `kls`, the extension provides diagnostics, document outline, and completion.
It waits for initialization before opening buffers, synchronizes full document
text, rejects stale diagnostics, and shuts down the server when deactivated.
Use **Krypton: Restart Language Server** from the command palette after installing
or replacing your compiler tools.

Syntax and snippets work without a server and in Restricted Mode. Running `kls`
requires a trusted workspace. Trust only folders whose contents you trust.

| Setting | Default | Purpose |
|---|---|---|
| `krypton.kls.path` | `""` | Absolute path to executable `kls` (`kls.exe` on Windows) |
| `krypton.kls.enabled` | `true` | Enable diagnostics, outline, and completion |
| `krypton.kls.trace` | `false` | Log LSP method names and frame sizes in Krypton LSP output |

Without an explicit path, discovery tries a bundled server for the current
platform, a legacy bundled server, standard macOS installation locations, PATH,
and `KRYPTON_ROOT` / `KRYPTON`. Bundled helpers live under `server/<platform>/`;
other platforms use their installed `kls`. Portable builds contain no server.
The local 2.4.8 artifact built with the command below bundles macOS arm64 `kls`.
No Windows or Linux server is included by that command.

## Install and build

In VS Code, choose **Extensions: Install from VSIX...**, then select
`extensions/krypton-language-2.4.8.vsix`. Restart the extension host if prompted.
This package requires a VS Code-compatible desktop extension host. Brain does
not yet run VS Code JavaScript extensions.

From the Krypton repository root:

```sh
# Portable extension, uses an installed language server:
python3 scripts/build_vsix.py

# macOS arm64 helper included explicitly:
python3 scripts/build_vsix.py --bundle-kls darwin-arm64=/usr/local/bin/kls

# Client tests; optional real-server integration:
KRYPTON_TEST_KLS=/usr/local/bin/kls node --test krypton-lang/test/extension.test.js
```

The builder uses Python's standard library and packages only declared assets.
It excludes Git metadata, test fixtures, and unrelated files. Existing versioned
VSIX files remain available. The grammar lives in the `syntaxes/` Git submodule;
grammar changes must also be committed in its source repository when publishing.
