# kcss — Krypton CSS DSL

**Status:** shipped in `stdlib/kcss.k` as of 2026-05-30.
**Authored by:** Brian (KryptonBytes) / krypton-lang.org.

`kcss` is Krypton's CSS emit module. It lets you author stylesheets in pure
Krypton, returning CSS strings that compose with `+`. Output goes straight
into a `<style>` element via `kcssStyle(rules)`. No JavaScript involved
either side of the build — `kcss` runs at Krypton compile/runtime, emits
plain CSS text, browsers consume it as a static asset.

It is the missing third leg of the framework. Each module emits one
language verbatim:

| Module  | Emits   | Pattern                                         |
|---------|---------|-------------------------------------------------|
| `htmk`  | HTML    | `htDiv(content)`, `htElA(tag, attrs, content)` |
| `kcss`  | CSS     | `kcssRule(sel, body)`, `kcssMedia(q, body)`     |
| `ks`    | JS      | `ksFetch(...)`, `ksOnClick(...)`               |

All three are pure-Krypton strings under the hood. Compose by `+`. No
runtime, no transformer, no node_modules.

---

## Why a DSL at all

Hand-rolling CSS as a multi-line string in Krypton source works and was
how `krypton-lang.org` started. The pain points showed up at scale:

1. **No theme primitives.** Defining `--primary: #7722ff` lives in the
   same flat string as a hundred other rules. Changing it required
   grepping. With `kcss`, theme tokens live in `siteTheme()` —
   `kcssVar("primary", "#7722ff")` — and any consumer pulls them via
   `kcssUseVar("primary")`.

2. **Breakpoint reuse.** Each page used the same `@media (max-width:600px)`
   query. `kcssOnMobile(body)` documents intent and centralizes the
   threshold. Want a global media-query strategy change? One edit.

3. **Self-hosting story.** "Krypton can build a real website end-to-end"
   needs *all three* outputs from Krypton. `htmk` covered HTML; `ks` covered
   JS. CSS sat as a giant raw string. `kcss` closes that gap.

4. **Course material.** Each helper is a one-liner. Walking through how
   `kcssMedia` becomes `@media ... { ... }` is a teachable moment about
   how to build a DSL on top of string concat with zero runtime overhead.

---

## Surface

### Primitives

```
kcssDecl(prop, val)         → "prop:val;"
kcssRule(sel, body)         → "sel{body}"
kcssRules(joined)           → "joined"            (pass-through alias)
kcssMedia(q, body)          → "@media q{body}"
kcssKeyframes(name, body)   → "@keyframes name{body}"
kcssFrame(at, body)         → "at{body}"          (for use inside keyframes)
kcssRoot(decls)             → ":root{decls}"
kcssVar(name, val)          → "--name:val;"
kcssUseVar(name)            → "var(--name)"
kcssStyle(rules)            → "<style>rules</style>"
```

### Common declaration shortcuts

```
kcssColor / kcssBg / kcssBgColor / kcssFont / kcssFontSize / kcssFontWeight
kcssMargin / kcssPadding / kcssBorder / kcssRadius
kcssWidth / kcssHeight / kcssMinWidth / kcssMaxWidth
kcssDisplay / kcssFlex / kcssInlineFlex / kcssGrid / kcssBlock / kcssNone
kcssTextAlign / kcssLineHeight / kcssLetterSpacing
kcssPosition / kcssTop / kcssBottom / kcssLeft / kcssRight / kcssZIndex
kcssOpacity / kcssOverflow / kcssCursor
kcssTransition / kcssTransform / kcssAnimation / kcssBoxShadow
kcssGap / kcssJustify / kcssAlign / kcssFlexDir / kcssFlexWrap
kcssGridCols / kcssGridRows
```

Each emits one terminated declaration: `kcssColor("red")` → `"color:red;"`.

### Selector helpers

```
kcssHover(sel)     → "sel:hover"
kcssFocus(sel)     → "sel:focus"
kcssActive(sel)    → "sel:active"
kcssDisabled(sel)  → "sel:disabled"
kcssBefore(sel)    → "sel::before"
kcssAfter(sel)     → "sel::after"
kcssChild(a, b)    → "a b"      (descendant)
kcssDirect(a, b)   → "a>b"      (direct child)
kcssAdjacent(a, b) → "a+b"      (adjacent sibling)
kcssSibling(a, b)  → "a~b"      (general sibling)
kcssGroup(a, b)    → "a,b"      (comma-grouped)
```

### Value helpers

```
kcssLinearGradient(deg, colors)    → "linear-gradient(deg,colors)"
kcssRadialGradient(spec)           → "radial-gradient(spec)"
kcssRgba(r, g, b, a)               → "rgba(r,g,b,a)"
kcssCalc(expr)                     → "calc(expr)"
kcssPx(n) / kcssRem(n) / kcssEm(n) / kcssPct(n) / kcssVw(n) / kcssVh(n)
```

### Breakpoints

```
kcssOnTablet(body)       → "@media (max-width:900px){body}"
kcssOnMobile(body)       → "@media (max-width:600px){body}"
kcssOnDesktop(body)      → "@media (min-width:901px){body}"
kcssReducedMotion(body)  → "@media (prefers-reduced-motion:reduce){body}"
kcssOnDark(body)         → "@media (prefers-color-scheme:dark){body}"
```

The thresholds (`600px` / `900px`) are opinions baked in for now. If a
project needs different ones, drop down to `kcssMedia("(max-width:700px)",
body)` directly.

---

## Patterns

### Theme block

```krypton
func siteTheme() {
    emit kcssRoot(
        kcssVar("primary",      "#7722ff") +
        kcssVar("primary-dark", "#5d16da") +
        kcssVar("bg",           "#fafafa")
    )
}
```

Output:

```css
:root{--primary:#7722ff;--primary-dark:#5d16da;--bg:#fafafa;}
```

Consumer rules then use `kcssUseVar("primary")` instead of hard-coding the
hex.

### Component rule

```krypton
let btn = kcssRule(".btn",
    kcssBg(kcssUseVar("primary")) +
    kcssColor("#fff") +
    kcssPadding("12px 24px") +
    kcssRadius("8px") +
    kcssCursor("pointer")
)

let btnHover = kcssRule(kcssHover(".btn"),
    kcssTransform("translateY(-1px)")
)
```

Output:

```css
.btn{background:var(--primary);color:#fff;padding:12px 24px;border-radius:8px;cursor:pointer;}
.btn:hover{transform:translateY(-1px);}
```

### Mobile-first overrides

```krypton
let css = baseRules() + kcssOnMobile(
    kcssRule(".btn",
        kcssDisplay("block") + kcssWidth("100%")
    )
)
```

Output:

```css
... base rules ...
@media (max-width:600px){.btn{display:block;width:100%;}}
```

### Keyframes

```krypton
kcssKeyframes("fadeUp",
    "from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}")
```

Output:

```css
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
```

### Hybrid (pragmatic)

For dense rule bodies, raw strings are still fine. `kcss` is structure
sugar — use helpers where they earn their keep (theme, breakpoints,
component composition) and drop to raw CSS for property-soup chunks. This
is exactly how `web/site/export.htk` dogfoods it: theme via `kcssRoot` +
`kcssVar`, breakpoints via `kcssOnMobile` / `kcssOnTablet`, animations
via `kcssKeyframes`, and rules themselves as raw strings (CSS is already
terse enough that wrapping every declaration would hurt readability).

---

## Non-goals (v1)

- **CSS parsing.** kcss only emits. No round-trip, no AST.
- **Auto-prefixing.** If you need `-webkit-` you write it. Browsers handle
  almost everything modern without help; the rare cases pay their own cost.
- **CSS-in-JS-style scoping.** No hash-based class names. Selectors are
  whatever you pass in. Component scoping is by naming convention.
- **Type-checked declarations.** `kcssColor("totally-not-a-color")` will
  emit garbage CSS. By design — the same friction exists in plain CSS.
- **Build-step optimization.** No minification, no dead-code elimination.
  CSS is already small; the framework's value is authorship ergonomics.

---

## Implementation

Single file: `stdlib/kcss.k`. ~140 funcs, all one-liners or near-it. No
state, no allocation beyond what `+` does. The whole module fits in one
screen.

It depends on nothing — no `import` statements at the top. Every helper
just concatenates strings. Compatible with Mac kcc 2.0.0 and the in-flight
2.1 toolchain.

---

## Future directions

- **`stdlib/kcss_themes.k`** — opinionated theme presets (light/dark,
  spacing scales, type scales). Pull in only if wanted.
- **`stdlib/kcss_components.k`** — common component snippets (buttons,
  cards, navs) returning pre-built rule strings. Skinned by theme vars.
- **Build-time dedupe.** Right now `siteCSS()` may emit the same rule
  twice if a caller is sloppy. A `kcssDedupe(rules)` pass could
  string-compare and drop duplicates. Low priority.
- **WASM target.** When `kcc --wasm` lands (see `docs/wasm_backend_design.md`
  whenever that's written), `kcss` will work without modification —
  it's pure-Krypton string concat. The same module powers both static
  HTML emission AND runtime CSS-in-Krypton in the browser.

---

## See also

- `stdlib/htmk.k` — HTML emit DSL (the sibling)
- `stdlib/ks.k`   — KryptonScript → JS DSL (the other sibling)
- `web/site/export.htk` — krypton-lang.org generator, uses kcss for
  theme + breakpoints + keyframes
