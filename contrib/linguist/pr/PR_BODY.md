Proposed PR: Add Krypton language support

Summary
- Adds `Krypton` as a programming language to Linguist with a TextMate grammar mapping.

Details
- Language name: Krypton
- File extension: `.k`
- TextMate scope: `source.krypton`
- Grammar source: https://github.com/<your-organization>/krypton (the PR should reference the Krypton repo and the grammar file at `krypton-lang/syntaxes/krypton.tmLanguage.json`).

Why
- Krypton is an actively-developed systems language with a complete TextMate grammar in the repository. GitHub currently auto-detects `.k` as KCL for some repositories; adding Krypton ensures correct language attribution for this ecosystem.

Notes for maintainers
- The grammar is included in the Krypton repo under `krypton-lang/syntaxes/krypton.tmLanguage.json`.
- `.gitattributes` in the Krypton repo already contains `*.k linguist-language=Krypton` to force detection when the repo is present.
- If you prefer a different `repo` identifier or path layout, update the `grammars.yml` entry accordingly.

Checklist
- [ ] Add entry to `lib/linguist/languages.yml` (snippet attached).
- [ ] Add mapping to `grammars.yml` (snippet attached).
- [ ] Confirm `tm_scope` and `fileTypes` match the TextMate grammar.
