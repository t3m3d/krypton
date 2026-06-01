# Wiring the KSML live demo into krypton-lang.org (site.htk)

krypton-lang.org runs as a **live Krypton server** (`site.htk` via systemd —
see `kweb/deploy/setup.sh`; confirmed `x-powered-by: Krypton 2.2.0`). That means
KSML's HTTP round-trips work on the live site. This adds an interactive demo
page that runs real Krypton in the visitor's browser session — counter + live
stdlib-module filter, **no hand-written JavaScript**.

The full, tested page lives in `kweb/examples/ksml_showcase.htk`. This doc lists
the exact edits to graft it into `site.htk`.

> **Build first.** `site.htk` uses `ShellExecuteA` (Windows-only) and the socket
> layer, so it does **not** build on macOS. Apply these edits and build/test on
> Windows or the Linux server before deploying.

## Prereqs (already done)

`ksml.k` has been copied into this repo's `stdlib/` (it originated in
`kweb/stdlib/`). `site.htk` can now `import "k:ksml"`.

## Edit 1 — imports (top of site.htk)

```krypton
import "k:htmk"
import "k:server"
import "k:ks"
import "k:ksml"        // <-- add
```

## Edit 2 — the demo page functions

Copy these from `kweb/examples/ksml_showcase.htk` into `site.htk` (anywhere
among the other `page*` functions): `lower`, `ciHas`, `modules`, `moduleRows`,
`counterFragment`, `showcaseContent`, and the `let hits = 0` + `func NL()` at
top level. Then add a site-themed page wrapper:

```krypton
func pageKsmlDemo() {
    emit sitePage("Live Demo", showcaseContent())
}
```

`showcaseContent()` already includes its own scoped CSS. It also needs the
KSML runtime in `<head>` — add `ksmlRuntime()` to the head slot in `sitePage`
(or just for this page) so the htmx runtime is present:

```krypton
func sitePage(title, content) {
    emit htPage("Krypton - " + title,
        siteCSS() + htMetaViewport() + ksmlRuntime(),   // <-- + ksmlRuntime()
        siteNav(title) + content + siteFooter())
}
```

(Adding `ksmlRuntime()` site-wide is harmless — it's one cached `<script>`.)

## Edit 3 — routes (in the dispatch `while` loop)

```krypton
            } else if path == "/demo" {
                serverRespond(pageKsmlDemo())
            } else if path == "/ksml/inc" {
                hits = hits + 1
                serverRespondText(counterFragment())
            } else if path == "/ksml/dec" {
                hits = hits - 1
                serverRespondText(counterFragment())
            } else if path == "/ksml/reset" {
                hits = 0
                serverRespondText(counterFragment())
            } else if path == "/ksml/modules" {
                serverRespond(moduleRows(serverQueryValue("q")))
```

(Insert before the final `else { serverRespond404() }`.)

> `serverQueryValue` is in `k:server` (one-call urldecoded query param). If the
> deployed server.k predates it, use `queryParam(serverReqQuery(), "q")` instead.

## Edit 4 — nav link (in `siteNav`)

```krypton
         htA("/features", "Features") +
         htA("/demo", "Live Demo") +        // <-- add
         htA("/programs", "Programs") +
```

## Verify after deploy

- `https://krypton-lang.org/demo` shows the counter + filter.
- Click +1 → the number changes without a page reload.
- Type in the filter → the module list narrows as you type.

If any of those don't update, check that the htmx runtime loaded (the
`ksmlRuntime()` `<script>` in `<head>`) and that the `/ksml/*` routes return
**fragments** (`serverRespondText` / a bare `<ul>`), not full pages.

## Note on state

`hits` is a single module-level global, so the counter is **shared across all
visitors** (fine for a demo; it's a global tally). For per-visitor state you'd
key it by session cookie via `serverReqCookie` / `serverSetCookie`.
