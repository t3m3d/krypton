Instructions and ready-to-copy YAML for proposing Krypton to GitHub Linguist.

Quick steps
- Add the `Krypton` entry to `lib/linguist/languages.yml` in the github/linguist repo using the snippet in `languages.yml`.
- Add the grammar mapping to `grammars.yml` in github/linguist using the snippet in `grammars.yml`.
- Link the grammar `path` to this repo's TextMate grammar at `krypton-lang/syntaxes/krypton.tmLanguage.json`.
- Open a PR against `github/linguist` describing the language and linking this repository as the source.

Notes
- This repo already provides a TextMate grammar at `krypton-lang/syntaxes/krypton.tmLanguage.json` and sets
  `*.k linguist-language=Krypton` in `.gitattributes`.
- If maintainers prefer a different grammar path or a different repo name, update the `path`/`repo` fields in the
  `grammars.yml` snippet before submitting.

Contact
- If you want, I can draft the full PR body and the exact patch to submit to `github/linguist`.
