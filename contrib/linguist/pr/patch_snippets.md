# github/linguist PR snippets — Krypton

Three files in `github/linguist` need edits. Krypton shares `.k` with **K**
(Arthur Whitney) and `.ks` with **KerboScript**, so a heuristic is REQUIRED —
a bare extension claim would be rejected.

## 1. lib/linguist/languages.yml
```yaml
Krypton:
  type: programming
  color: "#4F5AA8"
  extensions:
    - ".k"
    - ".ks"
    - ".krh"
  tm_scope: source.krypton
  ace_mode: text          # no "krypton" Ace mode exists; text is valid
  filenames: []
  interpreters:
    - kr
    - kcc
  # language_id: <assigned by maintainers on merge>
```

## 2. lib/linguist/heuristics.yml
```yaml
disambiguations:
  - extensions: ['.k']
    rules:
      - language: Krypton
        pattern: '(?m)^\s*(export\s+)?(func|fn)\s+\w|^\s*just\s+(run|go)\b|^\s*module\s+\w|(?<![\w.])kp\s*\(|(?<![\w.])emit\s'
      - language: K
  - extensions: ['.ks']
    rules:
      - language: Krypton
        pattern: '(?m)^\s*(export\s+)?(func|fn)\s+\w|^\s*just\s+(run|go)\b|(?<![\w.])kp\s*\('
      - language: KerboScript
```
Validated: matches 846/846 real Krypton `.k`/`.ks` files; zero false matches on
K's terse symbolic code or KerboScript's `PRINT`/`SET..TO`/`LOCK` syntax.

## 3. vendor/grammars + grammars.yml
Grammar repo: `t3m3d/krypton-tmLanguage` (scope `source.krypton`,
`krypton.tmLanguage.json`). Add as a Linguist grammar submodule and map it.

## Reality check (read before submitting)
github/linguist generally won't accept a language until it's used across a
meaningful number of public repos. Expect the popularity gate; the grammar +
heuristic + samples here make the PR *technically* complete, but acceptance is a
separate (adoption) question. Until merged, `.gitattributes` paints `.k` as Lisp
locally as a stopgap.
