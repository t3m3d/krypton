module kcss

// kcss — Krypton CSS DSL. Mirrors htmk's emit-string-builder pattern.
// Compose stylesheets in pure Krypton; no JS or external CSS engine.
//
// Shape:
//   kcssDecl("color", "#7722ff")           → "color:#7722ff;"
//   kcssRule(".btn", body)                 → ".btn{body}"
//   kcssMedia("(max-width:600px)", rules)  → "@media (max-width:600px){rules}"
//   kcssStyle(rules)                       → "<style>rules</style>"
//
// Compose by `+`. Each helper returns a string; concatenate to build a
// full stylesheet, then wrap with kcssStyle for HTML output (htmk-friendly).

// ── Primitives ───────────────────────────────────────────────────────

// kcssDecl: one declaration with trailing semicolon.
//   kcssDecl("color", "red") → "color:red;"
func kcssDecl(prop, val) {
    emit prop + ":" + val + ";"
}

// kcssRule: a rule block.
//   kcssRule(".x", "color:red;") → ".x{color:red;}"
func kcssRule(selector, body) {
    emit selector + "{" + body + "}"
}

// kcssRules: just an alias when you've already joined rules with +.
func kcssRules(joined) {
    emit joined
}

// kcssMedia: a media query block. `query` is anything after `@media `.
//   kcssMedia("(max-width:600px)", ".x{color:red;}")
//     → "@media (max-width:600px){.x{color:red;}}"
func kcssMedia(query, body) {
    emit "@media " + query + "{" + body + "}"
}

// kcssKeyframes: an @keyframes block. `body` should already contain
// frame selectors and their decls, e.g. "0%{opacity:0}100%{opacity:1}".
func kcssKeyframes(name, body) {
    emit "@keyframes " + name + "{" + body + "}"
}

// kcssFrame: one frame inside @keyframes.
//   kcssFrame("0%", "opacity:0;") → "0%{opacity:0;}"
func kcssFrame(at, body) {
    emit at + "{" + body + "}"
}

// kcssRoot: :root{...} declaration block — CSS custom properties live here.
func kcssRoot(decls) {
    emit ":root{" + decls + "}"
}

// kcssVar: a CSS custom-property declaration.
//   kcssVar("primary", "#7722ff") → "--primary:#7722ff;"
func kcssVar(name, val) {
    emit "--" + name + ":" + val + ";"
}

// kcssUseVar: reference a CSS custom property.
//   kcssUseVar("primary") → "var(--primary)"
func kcssUseVar(name) {
    emit "var(--" + name + ")"
}

// kcssStyle: wrap stylesheet text in a <style> element for HTML embedding.
func kcssStyle(rules) {
    emit "<style>" + rules + "</style>"
}

// ── Common declaration shortcuts ─────────────────────────────────────

func kcssColor(c)        { emit kcssDecl("color", c) }
func kcssBg(c)           { emit kcssDecl("background", c) }
func kcssBgColor(c)      { emit kcssDecl("background-color", c) }
func kcssFont(f)         { emit kcssDecl("font-family", f) }
func kcssFontSize(s)     { emit kcssDecl("font-size", s) }
func kcssFontWeight(w)   { emit kcssDecl("font-weight", w) }
func kcssMargin(m)       { emit kcssDecl("margin", m) }
func kcssPadding(p)      { emit kcssDecl("padding", p) }
func kcssBorder(b)       { emit kcssDecl("border", b) }
func kcssRadius(r)       { emit kcssDecl("border-radius", r) }
func kcssWidth(w)        { emit kcssDecl("width", w) }
func kcssHeight(h)       { emit kcssDecl("height", h) }
func kcssMinWidth(w)     { emit kcssDecl("min-width", w) }
func kcssMaxWidth(w)     { emit kcssDecl("max-width", w) }
func kcssDisplay(d)      { emit kcssDecl("display", d) }
func kcssFlex()          { emit kcssDecl("display", "flex") }
func kcssInlineFlex()    { emit kcssDecl("display", "inline-flex") }
func kcssGrid()          { emit kcssDecl("display", "grid") }
func kcssBlock()         { emit kcssDecl("display", "block") }
func kcssInline()        { emit kcssDecl("display", "inline") }
func kcssNone()          { emit kcssDecl("display", "none") }
func kcssTextAlign(a)    { emit kcssDecl("text-align", a) }
func kcssLineHeight(h)   { emit kcssDecl("line-height", h) }
func kcssLetterSpacing(s){ emit kcssDecl("letter-spacing", s) }
func kcssPosition(p)     { emit kcssDecl("position", p) }
func kcssTop(t)          { emit kcssDecl("top", t) }
func kcssBottom(b)       { emit kcssDecl("bottom", b) }
func kcssLeft(l)         { emit kcssDecl("left", l) }
func kcssRight(r)        { emit kcssDecl("right", r) }
func kcssZIndex(z)       { emit kcssDecl("z-index", z) }
func kcssOpacity(o)      { emit kcssDecl("opacity", o) }
func kcssOverflow(o)     { emit kcssDecl("overflow", o) }
func kcssCursor(c)       { emit kcssDecl("cursor", c) }
func kcssTransition(t)   { emit kcssDecl("transition", t) }
func kcssTransform(t)    { emit kcssDecl("transform", t) }
func kcssAnimation(a)    { emit kcssDecl("animation", a) }
func kcssBoxShadow(s)    { emit kcssDecl("box-shadow", s) }
func kcssGap(g)          { emit kcssDecl("gap", g) }
func kcssJustify(j)      { emit kcssDecl("justify-content", j) }
func kcssAlign(a)        { emit kcssDecl("align-items", a) }
func kcssFlexDir(d)      { emit kcssDecl("flex-direction", d) }
func kcssFlexWrap(w)     { emit kcssDecl("flex-wrap", w) }
func kcssGridCols(c)     { emit kcssDecl("grid-template-columns", c) }
func kcssGridRows(r)     { emit kcssDecl("grid-template-rows", r) }

// ── Selector helpers ─────────────────────────────────────────────────

// Compose pseudo-class onto a selector.
func kcssHover(sel)      { emit sel + ":hover" }
func kcssFocus(sel)      { emit sel + ":focus" }
func kcssActive(sel)     { emit sel + ":active" }
func kcssDisabled(sel)   { emit sel + ":disabled" }
func kcssVisited(sel)    { emit sel + ":visited" }
func kcssBefore(sel)     { emit sel + "::before" }
func kcssAfter(sel)      { emit sel + "::after" }

// Descendant / child / adjacent combinators.
func kcssChild(parent, child)    { emit parent + " " + child }
func kcssDirect(parent, child)   { emit parent + ">" + child }
func kcssAdjacent(a, b)          { emit a + "+" + b }
func kcssSibling(a, b)           { emit a + "~" + b }

// Group selectors with commas: "h1, h2, h3".
func kcssGroup(a, b)             { emit a + "," + b }

// ── Value helpers ────────────────────────────────────────────────────

// Linear gradient.
//   kcssLinearGradient("135deg", "#7722ff,#5d16da")
//     → "linear-gradient(135deg,#7722ff,#5d16da)"
func kcssLinearGradient(deg, colors) {
    emit "linear-gradient(" + deg + "," + colors + ")"
}

// Radial gradient (pass full spec after the open paren).
//   kcssRadialGradient("circle,#fff,transparent")
//     → "radial-gradient(circle,#fff,transparent)"
func kcssRadialGradient(spec) {
    emit "radial-gradient(" + spec + ")"
}

// rgba helper.
func kcssRgba(r, g, b, a) {
    emit "rgba(" + r + "," + g + "," + b + "," + a + ")"
}

// calc() helper.
func kcssCalc(expr) { emit "calc(" + expr + ")" }

// Common unit builders so call sites stay terse.
func kcssPx(n)   { emit n + "px" }
func kcssRem(n)  { emit n + "rem" }
func kcssEm(n)   { emit n + "em" }
func kcssPct(n)  { emit n + "%" }
func kcssVw(n)   { emit n + "vw" }
func kcssVh(n)   { emit n + "vh" }

// ── Breakpoints (mobile-first) ───────────────────────────────────────

// Convenience for typical breakpoints. Pass the inner body (already-joined
// rules) and get the @media block.
func kcssOnMobile(body)  { emit kcssMedia("(max-width:600px)",  body) }
func kcssOnTablet(body)  { emit kcssMedia("(max-width:900px)",  body) }
func kcssOnDesktop(body) { emit kcssMedia("(min-width:901px)",  body) }

// Reduced-motion accessibility wrap.
func kcssReducedMotion(body) {
    emit kcssMedia("(prefers-reduced-motion:reduce)", body)
}

// Dark-mode wrap (color-scheme based).
func kcssOnDark(body) {
    emit kcssMedia("(prefers-color-scheme:dark)", body)
}
