// tests/smoke_new_stdlib.k — quick build+behaviour check for the
// stdlib modules added 2026-06-03: color, mime, cookie.
//
// (uuid was attempted but deferred — its entropy source needs to be a
// small-int builtin that doesn't trip the smart-int pointer ceiling.
// random() returns 0 on Linux; rdtsc/timestamp return values above
// 0x7F000000 which get re-tagged as pointers. Coming back to it once
// a `randomBytes(n)` or sub-tag entropy primitive lands.)

import "k:color"
import "k:mime"
import "k:cookie"

func check(name, expected, actual) {
    if expected == actual { print("[PASS] " + name) }
    else { print("[FAIL] " + name + " expected=" + expected + " got=" + actual) }
}

just run {
    // ── color ──────────────────────────────────────────────────────
    check("hex -> rgb (#7722ff)",  "119,34,255", colorHexToRgb("#7722ff"))
    check("hex -> rgb (no #)",     "119,34,255", colorHexToRgb("7722ff"))
    check("rgb -> hex round-trip", "#7722ff",    colorRgbToHex(119, 34, 255))
    check("rgb -> hex clamp high", "#ff00ff",    colorRgbToHex(999, 0, 999))
    check("rgb -> hex clamp neg",  "#000000",    colorRgbToHex(0 - 5, 0 - 5, 0 - 5))
    check("lighten 50% of #000",   "#7f7f7f",    colorLighten("#000000", 50))
    check("darken 50% of #ffffff", "#808080",    colorDarken("#ffffff", 50))
    check("mix 50% red/blue",      "#80007f",    colorMix("#ff0000", "#0000ff", 50))

    // ── mime ───────────────────────────────────────────────────────
    check("mime .html",         "text/html",                 mimeFromExt(".html"))
    check("mime css (no dot)",  "text/css",                  mimeFromExt("css"))
    check("mime .wasm path",    "application/wasm",          mimeFromPath("/particles.wasm"))
    check("mime png path",      "image/png",                 mimeFromPath("/img/logo.png"))
    check("mime unknown",       "application/octet-stream",  mimeFromExt(".xyz"))
    check("mime .k path",       "text/x-krypton",            mimeFromPath("examples/hello.k"))
    check("mime no extension",  "application/octet-stream",  mimeFromPath("/no-ext"))

    // ── cookie ─────────────────────────────────────────────────────
    let h = "session=abc123; user=ada; theme=dark"
    check("cookieGet session",  "abc123", cookieGet(h, "session"))
    check("cookieGet user",     "ada",    cookieGet(h, "user"))
    check("cookieGet missing",  "",       cookieGet(h, "nope"))
    check("cookieGet prefix-collision", "", cookieGet(h, "sess"))
    check("cookieBuild",        "k=v",    cookieBuild("k", "v"))
    let sc = cookieSet("auth", "xyz", "Path=/, Max-Age=3600, HttpOnly")
    check("cookieSet shape",    "auth=xyz; Path=/; Max-Age=3600; HttpOnly", sc)

    print("done")
}
