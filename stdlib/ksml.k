// stdlib/ksml.k — KSML: KryptScript Media Language.
//
// Hypermedia attribute DSL for the Krypton web framework. Lets any htmk
// element fire HTTP requests and swap part of the page with the HTML the
// server returns — no hand-written JavaScript. Pairs with htmk (server-side
// HTML) and server.k (routes that return HTML fragments).
//
// Wire format: emits htmx-compatible `hx-*` / `data-ksml-*` attributes. The
// page includes the KSML client runtime once (ksmlRuntime() / a CDN <script>),
// which scans for these attributes and performs the request + swap.
//
// Style mirrors htmk: every helper returns a ` name="value"` attribute string
// (note leading space) so they concatenate straight into htmk's htElA(...).
//
//   htDivA(
//       ksmlPost("/count") + ksmlTarget("#c") + ksmlSwap("innerHTML"),
//       "+1")
//
//   -> <div hx-post="/count" hx-target="#c" hx-swap="innerHTML">+1</div>

module ksml

// ── low-level attribute builder ──────────────────────────────────────
// Self-contained (no htmk dependency): same escaping rules, leading space.
func ksmlEscape(s) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let c = s[i]
        if c == "&"      { out = out + "&amp;" }
        else if c == "<" { out = out + "&lt;" }
        else if c == ">" { out = out + "&gt;" }
        else if c == "\"" { out = out + "&quot;" }
        else             { out = out + c }
        i += 1
    }
    emit out
}

func ksmlAttr(name, val) {
    emit " " + name + "=\"" + ksmlEscape(val) + "\""
}

// ── HTTP verbs: what request, to where ───────────────────────────────
func ksmlGet(url)    { emit ksmlAttr("hx-get", url) }
func ksmlPost(url)   { emit ksmlAttr("hx-post", url) }
func ksmlPut(url)    { emit ksmlAttr("hx-put", url) }
func ksmlPatch(url)  { emit ksmlAttr("hx-patch", url) }
func ksmlDelete(url) { emit ksmlAttr("hx-delete", url) }

// ── target + swap: which element, how to update ──────────────────────
// target: CSS selector of the element to update (default: the element itself).
func ksmlTarget(sel) { emit ksmlAttr("hx-target", sel) }

// swap strategy. Common values:
//   innerHTML (default), outerHTML, beforebegin, afterbegin,
//   beforeend, afterend, delete, none.
func ksmlSwap(strategy) { emit ksmlAttr("hx-swap", strategy) }

// Convenience swaps.
func ksmlSwapInner()  { emit ksmlSwap("innerHTML") }
func ksmlSwapOuter()  { emit ksmlSwap("outerHTML") }
func ksmlAppend()     { emit ksmlSwap("beforeend") }   // add to end of target
func ksmlPrepend()    { emit ksmlSwap("afterbegin") }  // add to start of target

// ── trigger: when to fire ────────────────────────────────────────────
// event: click | submit | change | keyup | mouseenter | "load" |
//        "every 2s" | "keyup changed delay:500ms" | ...
func ksmlTrigger(event) { emit ksmlAttr("hx-trigger", event) }

// Convenience triggers.
func ksmlOnLoad()         { emit ksmlTrigger("load") }
func ksmlPoll(interval)   { emit ksmlTrigger("every " + interval) }  // e.g. "2s"
func ksmlOnChange()       { emit ksmlTrigger("change") }
func ksmlOnSubmit()       { emit ksmlTrigger("submit") }

// ── request shaping ──────────────────────────────────────────────────
// hx-include: also send the values of elements matching this selector.
func ksmlInclude(sel)   { emit ksmlAttr("hx-include", sel) }
// hx-params: which params to submit ("*" all, "none", "not id,name", ...).
func ksmlParams(spec)   { emit ksmlAttr("hx-params", spec) }
// hx-vals: extra static values as a JSON object string, e.g. "{\"id\":5}".
func ksmlVals(jsonObj)  { emit ksmlAttr("hx-vals", jsonObj) }
// hx-headers: extra request headers as a JSON object string.
func ksmlHeaders(jsonObj) { emit ksmlAttr("hx-headers", jsonObj) }

// ── UX niceties ──────────────────────────────────────────────────────
// hx-indicator: selector of a loading element shown during the request.
func ksmlIndicator(sel) { emit ksmlAttr("hx-indicator", sel) }
// hx-confirm: native confirm() prompt before firing.
func ksmlConfirm(msg)   { emit ksmlAttr("hx-confirm", msg) }
// hx-push-url: "true" to push the request URL into browser history.
func ksmlPushUrl(v)     { emit ksmlAttr("hx-push-url", v) }
// hx-disabled-elt: selector(s) to disable while the request is in flight.
func ksmlDisable(sel)   { emit ksmlAttr("hx-disabled-elt", sel) }
// hx-sync: coordinate requests on a selector, e.g. "this:abort".
func ksmlSync(spec)     { emit ksmlAttr("hx-sync", spec) }
// hx-boost: "true" turns plain <a>/<form> into AJAX (progressive enhancement).
func ksmlBoost(v)       { emit ksmlAttr("hx-boost", v) }

// ── one-shot composite helpers (the 90% cases) ───────────────────────
// A GET that swaps the result into `target`'s innerHTML on click.
func ksmlGetInto(url, target) {
    emit ksmlGet(url) + ksmlTarget(target) + ksmlSwapInner()
}
// A POST that swaps the result into `target`'s innerHTML.
func ksmlPostInto(url, target) {
    emit ksmlPost(url) + ksmlTarget(target) + ksmlSwapInner()
}
// Poll `url` every `interval` (e.g. "5s"), replacing this element's content.
func ksmlLivePoll(url, interval) {
    emit ksmlGet(url) + ksmlTrigger("every " + interval) + ksmlSwapInner()
}

// ── client runtime include ───────────────────────────────────────────
// Drop this once in <head> (or before </body>). KSML attributes are
// htmx-compatible, so the htmx runtime drives them. Pin a version for
// reproducible builds; swap for a self-hosted copy in production.
func ksmlRuntimeUrl() {
    emit "https://unpkg.com/htmx.org@2.0.3"
}

func ksmlRuntime() {
    emit "<script src=\"" + ksmlRuntimeUrl() + "\" crossorigin=\"anonymous\"></script>"
}

// Self-hosted variant: point at a local copy you ship in dist/.
func ksmlRuntimeLocal(path) {
    emit "<script src=\"" + path + "\"></script>"
}
