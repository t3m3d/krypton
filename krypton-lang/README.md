# Krypton Language Support

Syntax highlighting for the [Krypton](https://github.com/krypton-lang/krypton) programming language.

## Features

- Syntax highlighting for `.k` files
- Bracket matching and auto-closing
- Comment toggling (`//` and `/* */`)
- Code folding

## Language Overview

Krypton is a self-hosting, string-typed language with:

```krypton
func greet(name) {
    emit "Hello, " + name
}

just run {
    print(greet("World"))
}
```

## Install Locally

```bash
cd krypton-lang
code --install-extension .
```

Or symlink into your VS Code extensions directory:

```bash
# Windows
mklink /D "%USERPROFILE%\.vscode\extensions\krypton-lang" krypton-lang

# macOS/Linux
ln -s "$(pwd)/krypton-lang" ~/.vscode/extensions/krypton-lang
```

## GitHub Linguist

To register Krypton with GitHub Linguist for repo-level highlighting,
submit a PR to [github/linguist](https://github.com/github-linguist/linguist)
adding Krypton to `languages.yml` with this grammar as the TextMate reference.
