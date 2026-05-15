Add the following snippets into `github/linguist`.

-- languages.yml snippet --

Krypton:
  type: programming
  color: "#4F5AA8"
  tm_scope: source.krypton
  ace_mode: krypton
  extensions:
    - .k
  filenames: []
  interpreters: []

-- grammars.yml snippet --

- language: "Krypton"
  scope: source.krypton
  path: krypton/krypton-lang/syntaxes/krypton.tmLanguage.json
  repo: krypton

Notes:
- The `path` assumes you will add the Krypton repo as a submodule or refer to it by its GitHub `owner/repo` path when adding to `grammars.yml` (maintainers may prefer `repo: owner/krypton` and a repo `path` that points to the raw grammar file in that repo).
