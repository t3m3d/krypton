# Launch week: kcss, the lesson runner, and a 95-byte WASM proof

**2026-05-30** · Brian / krypton-lang.org

This week I pushed Krypton from "self-hosted compiler with three native
backends" into "self-hosted compiler with three native backends and a
working WebAssembly proof." Plus the site got a real mobile pass, an
in-browser lesson runner, a CSS DSL, and a `/kcode` landing page that
actually sells the IDE.

Recap of what shipped, in order of "would you click this on Hacker News":

## 1. Krypton compiles to WebAssembly (proof of concept)

Krypton has three native backends today — `elf.k` for Linux,
`x64.k` for Windows, `macho_arm64_self.k` for macOS (which writes its
own ad-hoc SHA-256 code signature so the binary runs under Tahoe AMFI
without `codesign`). I want a fourth: `kcc --wasm src.k -o out.wasm`.

This week I shipped Phase 0 of that work — a hand-written Krypton
program that emits a valid 95-byte `.wasm` module. The binary loads
via `WebAssembly.instantiate` and prints "Hello" through a host
`console_log` import. Verified in JavaScriptCore via
`osascript -l JavaScript`.

```
$ /tmp/hw
wrote /tmp/hello.wasm: 95 bytes

$ xxd /tmp/hello.wasm
00000000: 0061 736d 0100 0000 0109 0260 027f 7f00  .asm.......`....
00000010: 6000 0002 1301 0365 6e76 0b63 6f6e 736f  `......env.conso
00000020: 6c65 5f6c 6f67 0000 0302 0101 0503 0100  le_log..........
00000030: 0107 1302 066d 656d 6f72 7902 0006 5f73  .....memory..._s
00000040: 7461 7274 0001 0a0a 0108 0041 0041 0510  tart.......A.A..
00000050: 000b 0b0b 0100 4100 0b05 4865 6c6c 6f    ......A...Hello

$ osascript -l JavaScript run_wasm.js
Module instantiated OK
OUTPUT: Hello
```

The proof is in `wasm_proof/hello_wasm.htk` in the repo. ~140 lines of
Krypton, of which most is one-liner helpers (`hexByte`, `leb`, `b`,
`wasmSection`). The trick was discovering Krypton's `writeBytes()`
builtin, which takes a hex-encoded string like `"x00x61x73x6d"` and
writes real bytes — the only way to put `\0` bytes in a file from
Krypton, since regular string concat is C-string null-terminated.

This unblocks Phase 1: lower Krypton IR to WASM and emit lesson 01
end-to-end. From there, the path to "real Krypton runs in the browser"
(replacing the JS bridge below) is mechanical.

The full design lives in `docs/wasm_backend_design.md`. tl;dr:
WebAssembly is mechanically simpler than Mach-O, the section layout fits
on one cheat sheet, and the existing ELF/Mach-O backends' byte-write
patterns lift directly into a `wasm_self.k` backend.

## 2. The lesson runner (JS bridge that runs 26/31 lessons)

While the WASM backend cooks, every lesson page on krypton-lang.org now
has a "▶ Run" button. Click it, see output, no install required.

The bridge is `dist/runner.js`: a Krypton-to-JavaScript mini-interpreter
written in ~330 lines. It transpiles a useful subset of Krypton — `func`,
`fn`, `if`/`elif`/`else`, `while`, `for in`, `let`, `emit`, `just run`,
arithmetic, string concat, the `kp`/`len`/`listNew`/`mapNew` builtins
— into JavaScript, then evaluates it inside a sandbox that captures
output.

Results: **26 of 31 lessons run cleanly.** The five that gate gracefully
(struct, try/catch, match, k:fs, k:http, k:json) display a "needs the
real runtime — run locally with `kcc -r tutorial/<lesson>.k`" message
instead of a stack trace.

The bridge is **explicitly temporary.** It exists to give visitors an
immediate "does this language feel right" answer without an install
step. The WASM backend retires it.

You can poke at the bridge directly on the
[playground](https://krypton-lang.org/playground.html) — same editor, no
lesson context.

## 3. kcss — Krypton CSS DSL

The site framework had `htmk` (HTML emit) and `ks` (Krypton → JS).
The missing leg was CSS. This week: `stdlib/kcss.k`.

```krypton
import "k:kcss"

func siteTheme() {
    emit kcssRoot(
        kcssVar("primary",      "#7722ff") +
        kcssVar("primary-dark", "#5d16da") +
        kcssVar("bg",           "#fafafa")
    )
}

let btn = kcssRule(".btn",
    kcssBg(kcssUseVar("primary")) +
    kcssColor("#fff") +
    kcssPadding("12px 24px") +
    kcssRadius("8px")
)

let mobile = kcssOnMobile(
    kcssRule(".btn", kcssDisplay("block") + kcssWidth("100%"))
)
```

Output:

```css
:root{--primary:#7722ff;--primary-dark:#5d16da;--bg:#fafafa;}
.btn{background:var(--primary);color:#fff;padding:12px 24px;border-radius:8px;}
@media (max-width:600px){.btn{display:block;width:100%;}}
```

~120 helpers, all one-liners. Compose with `+`. Wrap with `kcssStyle(rules)`
for HTML embedding.

The full design is in `docs/kcss_design.md`. The point isn't to wrap
every CSS declaration — it's to give theme primitives, breakpoint
helpers, and keyframes a real shape. The dense rule bodies stay as raw
strings; CSS is already terse enough.

`web/site/export.htk` (the krypton-lang.org generator) dogfoods kcss
for theme + breakpoints + keyframes now. Same byte output, cleaner
source.

## 4. htmk composition helpers

`stdlib/htmk.k` grew seven new helpers for the patterns you'd
otherwise hand-concat:

- `htEach(list, fn)` — map a newline-list through `fn`, concat results.
- `htEachI(list, fn)` — same, with `(item, index)`.
- `htWhen(cond, html)` / `htUnless(cond, html)` — conditional render.
- `htEither(cond, ifTrue, ifFalse)` — ternary for HTML.
- `htJoin(list)` / `htJoinSep(list, sep)` — concat newline-list, with or
  without separator.
- `htWrap(list, before, after)` — wrap each item, closure-free shortcut
  for `<li>X</li>` lists.

Two non-obvious constraints showed up while building these:

1. **Krypton's `fn` is a keyword.** Using `fn` as a parameter name
   breaks the C emitter. Renamed to `f`. Bug-in-fixed-form: noted in
   `feedback_krypton_dev_gotchas`.
2. **Funcptr calls need `callPtr`.** The Mac kcc 2.0.0 doesn't support
   `f(x)` for funcptr-typed parameters; you have to use
   `callPtr(f, x)`. Documented in the handoff but easy to forget.

Both worked out. The site's `pageLearnIndex()` now builds its 31 lesson
cards via `htEach(lessonFiles(), funcptr(_lessonCard))` instead of a
while-loop.

## 5. Mobile pass + iOS polish

Every page on krypton-lang.org has a real mobile breakpoint now —
hamburger menu at ≤600px, stacked hero buttons, tightened code blocks,
scaled-down particle canvas. The lesson runner runs cleanly on an
iPhone 13 mini (verified by my eight-year-old).

Three iOS-specific polish bits:

- `theme-color` meta tag (Safari's address bar tints purple to match the
  hero gradient).
- `apple-mobile-web-app-capable` + `black-translucent` status bar style
  (looks right when added to home screen).
- `-webkit-tap-highlight-color: transparent` on buttons so they don't
  flash gray on tap.

## 6. Sponsor + kcode landing pages

The funnel side. `/sponsor.html` explains what sponsorship funds (WASM
backend, lesson runner v2, course writing time) and routes to GitHub
Sponsors. `/kcode.html` is the paid-IDE landing page with a Buy button
that'll point at Gumroad once enrollment finishes. The $25/mo
"Patron" tier gets the recommended-card highlight — standard upsell
pattern.

Nav-level "♥ Sponsor" button site-wide. Footer line: "Built and
maintained by Brian. Support the project on ♥ GitHub Sponsors — keeps
Krypton shipping."

## 7. Plumbing

- OpenGraph + Twitter Card metas on every page, with a 1200×630 SVG
  `/og.svg` that uses the same gradient as the hero.
- `sitemap.xml` (41 URLs) generated by the same Krypton build.
- `robots.txt` allowing crawl, pointing at the sitemap.
- `Cache-Control: no-cache, must-revalidate` on `.js` and `.html`
  so future runner updates land without cache-bust gymnastics.

## What's next

In priority order:

1. **WASM Phase 1 — IR → WASM lowering.** Lift the Phase 0 helpers into
   `compiler/wasm32/wasm_self.k`. First end-to-end target:
   `tutorial/01_hello_world.k` → `01_hello_world.wasm`, runs in browser
   matching `kcc -r` output.
2. **WASM Phase 2 — control flow + multi-func modules.** Tutorials
   1-13. Each lesson page gains a `<lesson>.wasm` artifact that the
   runner loads instead of the JS bridge.
3. **kcode 1.0 paid release.** Gumroad page goes live with the Buy
   button URL. `$29` one-time.
4. **Course chapter 4 as lead-magnet.** "Linux x86_64: writing your own
   ELF (no linker)." Free chapter for the
   [self-hosting compiler course](/path-coming-soon).

If you're following along, the cleanest entry points are the
[learn track](https://krypton-lang.org/learn.html) (lesson 01 → 13 all
runnable in-page), the
[playground](https://krypton-lang.org/playground.html), or the
[WASM design doc](https://github.com/t3m3d/krypton/blob/main/docs/wasm_backend_design.md)
if you like compiler stuff.

If you'd like to support the work,
[sponsor on GitHub](https://github.com/sponsors/t3m3d) — keeps me
shipping.

---

*Krypton is built by Brian. Source on
[github.com/t3m3d/krypton](https://github.com/t3m3d/krypton). Site +
framework, lessons, and the in-browser runner are all generated by
`web/site/export.htk` — one .htk file produces the whole site.*
