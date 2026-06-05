# HANDOFF → Agent W — kr.exe parity: top-level auto-wrap + REPL (2026-06-05)

**Priority: low / when convenient.** No rush — finish the kryptlink link
shortener first. This just records what the POSIX `kr` gained so Windows
`kr.exe` (`tools/kr/run.k`) can match it later. Nothing is broken on Windows;
it's a feature gap, not a regression.

## Context

The POSIX `kr` runner (repo-root `kr`, bash; macOS + Linux) got two new
KryptScript features on 2026-06-04. The Windows runner `tools/kr/run.k`
(→ `kr.exe`) still only does the old "compile script → temp exe → run →
delete" flow. **`kr` is the canonical spec — mirror its behavior.**

Brian's vision: "KryptScript should work kinda like Swift, but as Krypton."

## Feature 1 — Swift-like top-level auto-wrap

If a `.ks`/`.k` script has **no** `just run { }` block, wrap its whole body
in one before compiling, so users write scripts top-to-bottom with no
boilerplate. `import` and `func` work fine inside the wrap (verified).

Rules (see `kr` lines ~106-145):
- **Detect**: strip `//` line comments first, then decide. Wrap only if the
  (comment-stripped) source has **no** `just run` token AND **no** top-level
  `module` decl. Files with an explicit `just run` or a `module` run
  unchanged (a `module` is a library, not a script).
- **Strip a leading `#!` shebang** line before wrapping (don't let it land
  inside the block).
- **Wrap**: emit `just run {\n<body>\n}` to a temp file, compile + run that.
- Forward script args; propagate the script's exit code (already done in
  run.k).

Example that must work (no `just run`):
```
#!/usr/bin/env kr
import "k:ansi"
func greet(w) { emit "Hello, " + w + "!" }
kp(bold(cyan(greet("world"))))
```

## Feature 2 — REPL (kr.exe with no args)

`kr` / `kr.exe` with **no arguments** → interactive REPL. Krypton has no
interpreter, so it's an **accumulating** REPL (see `kr` `_repl()`,
lines ~43-97):
- Prompt `ks> `. Read a line from stdin.
- **Remember** lines that start with `import`/`func`/`struct`/`let` (they
  persist for later lines). Bare expressions/statements run once.
- Each turn, build a program = remembered `import`s at top + `just run {`
  remembered `func`/`struct`/`let` + the current line `}`, compile + run it,
  show output. (Re-running remembered defs is fine — they're side-effect-free
  redefinitions/bindings.)
- **Multi-line**: if a line's `{` vs `}` counts are unbalanced, keep reading
  with a `..> ` continuation prompt until they balance, then submit.
- **Commands**: `:help`, `:list` (show remembered defs), `:reset` (clear
  state), `:q`/`:quit` (and EOF/Ctrl-Z on Windows) to exit.
- To see a value, the user types `kp(expr)` (no auto-print — same as POSIX).

## Windows impl notes
- `tools/kr/run.k` already has `_tempExePath()`, `_quote()`, `_cmdWrap()`,
  `shellRun()`, `DeleteFileA()` — reuse them. For wrap mode, write the
  wrapped source to a temp `.ks` in `%TEMP%`, then run the existing
  compile→run→delete flow on it (and delete the temp `.ks` too).
- REPL needs line-at-a-time stdin reads — Krypton `readLine`/`input`
  builtins. Loop until EOF.
- Installer already maps `.ks` → `KryptonScript.Run` → `kr.exe "%1" %*`,
  so double-click/`myscript.ks args` keep working; this only adds the
  no-arg REPL path and the auto-wrap step.

— Agent M (macOS)
