# Krypton Language Support for VS Code

Syntax highlighting for the [Krypton](https://github.com/t3m3d/krypton)
programming language.

## Features

- Syntax highlighting for `.k` files
- Bracket matching and auto-closing (incl. `` ` `` for backtick interpolation strings)
- Comment toggling (`//` and `/* */`)
- Folding by indentation

## Source of truth

The TextMate grammar (`syntaxes/krypton.tmLanguage.json`) is a git submodule
pointing at https://github.com/t3m3d/krypton-tmLanguage. The standalone repo
exists so it can be referenced by GitHub Linguist for repo-level highlighting
without having to vendor the whole compiler. To update the grammar, edit it
in that repo and update the submodule pointer here.

## Install locally

Either install the prebuilt vsix from `extensions/krypton-language-<version>.vsix`:

```bash
code --install-extension extensions/krypton-language-1.4.0.vsix
```

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
