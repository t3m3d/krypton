# Krypton Language Support for VS Code

Syntax highlighting **plus a bundled language server** (`kls.exe`) for the
[Krypton](https://github.com/t3m3d/krypton) programming language.

## Features

- Syntax highlighting for `.k` files
- Bracket matching and auto-closing (incl. `` ` `` for backtick interpolation strings)
- Comment toggling (`//` and `/* */`)
- Folding by indentation
- **(1.8.1+)** Real-time diagnostics from `kls`:
  - tokenizer errors (unterminated strings/comments, bad hex literals)
  - structural errors (unmatched braces/parens/brackets)
  - shape errors (missing func name, missing param list, bare `let`)
  - duplicate function name warnings
- **(1.8.1+)** Document outline (function/struct/module list)
- **(1.8.1+)** Completion (38 keywords + 109 builtins + open-buffer functions)

## Settings

| Key | Default | Purpose |
|---|---|---|
| `krypton.kls.path`   | `""`    | Explicit path to `kls.exe`. Empty = bundled binary, then PATH |
| `krypton.kls.enabled`| `true`  | Disable to fall back to syntax-only mode |
| `krypton.kls.trace`  | `false` | Log every JSON-RPC frame to the *Krypton LSP* output channel |

## Source of truth

The TextMate grammar (`syntaxes/krypton.tmLanguage.json`) is a git submodule
pointing at https://github.com/t3m3d/krypton-tmLanguage. The standalone repo
exists so it can be referenced by GitHub Linguist for repo-level highlighting
without having to vendor the whole compiler. To update the grammar, edit it
in that repo and update the submodule pointer here.

## Install locally

Either install the prebuilt vsix from `extensions/krypton-language-<version>.vsix`:

```bash
code --install-extension extensions/krypton-language-1.8.1.vsix
```

The `.vsix` bundles `kls.exe` so the language server works out of the box on
Windows. macOS / Linux users need to build their own `kls` binary
(see [`lsp/`](../lsp/)) and point `krypton.kls.path` at it.

…or symlink this folder into your VS Code extensions directory:

```bash
# Windows (PowerShell, admin)
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.vscode\extensions\krypton-lang" -Target "$(Resolve-Path .)"

# macOS / Linux
ln -s "$(pwd)" ~/.vscode/extensions/krypton-lang
```

## Build a vsix

```bash
bash scripts/build_vsix.sh
```

The script creates `extensions/krypton-language-<version>.vsix` from the
manifest in this folder plus the submoduled tmLanguage grammar. No
`vsce` / Node toolchain required — vsix is just a ZIP with a specific layout.
