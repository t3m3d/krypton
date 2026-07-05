# Krypton Web (`kweb`)

`web/` is Krypton's web framework area. It lets you write pages in Krypton,
build static HTML into `dist/`, preview locally, and deploy the generated files.

The short version:

```text
.htk source
  -> Krypton compiler / kweb
  -> generated HTML files in dist/
  -> upload dist/ to web host
```

No C or Objective-C source is part of this workflow.

## What Is `.htk`?

`.htk` means "HTML template written in Krypton".

An `.htk` file is normal Krypton source with a web convention:

- import `k:htmk`
- write functions that return HTML strings
- use `htPage`, `htDiv`, `htP`, `htA`, `htStyle`, etc.
- for static sites, write final files into `dist/`
- for live demos, respond to HTTP requests

Example shape:

```krypton
import "k:htmk"

func homePage() {
    emit htPage("Hello", "",
        htMain(
            htH1("Hello from Krypton") +
            htP("This HTML was built by Krypton.")
        )
    )
}

just run {
    writeFile("dist/index.html", homePage())
}
```

That program builds a string of HTML and writes it as a real webpage.

## Main Pieces

### `k:htmk`

`stdlib/htmk.k` is the HTML builder library.

It gives helpers like:

- `htPage(title, head, body)`
- `htH1(text)`
- `htP(text)`
- `htA(href, text)`
- `htDiv(content)`
- `htDivA(attrs, content)`
- `htStyle(css)`
- `htMetaViewport()`

These helpers return strings. You combine them with `+`.

### `site.htk`

`site.htk` usually contains page functions and shared layout.

For example:

- shared CSS
- nav bar
- footer
- `pageHome()`
- `pageAbout()`
- `pageContact()`

Think of `site.htk` as the source of the website.

### `export.htk`

`export.htk` is the static-site generator.

It imports or defines the page functions, then writes files:

```krypton
just run {
    writeFile("dist/index.html", pageHome())
    writeFile("dist/about.html", pageAbout())
}
```

Think of `export.htk` as the build script for the site.

### `dist/`

`dist/` is generated output.

It contains files your host serves:

- `index.html`
- `about.html`
- CSS/JS/assets if your site writes or copies them
- `.htaccess` when using Apache-style clean URLs/security headers

`dist/` is the folder that gets deployed.

## `kweb` Commands

`web/kweb` is the existing kweb binary.

From inside a project folder:

```bash
kweb build
```

Builds `dist/` by compiling/running `export.htk`.

```bash
kweb serve 8080
```

Serves `dist/` locally for preview.

```bash
kweb deploy example.com username
```

Uploads `dist/` recursively through the existing deploy flow.

The macOS GUI uses FTP directly and has fields for host, user, password, and an
optional remote folder.

## Creating A New Site

```bash
web/kweb init mysite
cd mysite
../web/kweb build
../web/kweb serve 8080
```

Generated shape:

```text
mysite/
  site.htk
  export.htk
  dist/
    .htaccess
```

Edit `site.htk`, then run `kweb build` again.

## Current Repo Site

`web/site/` is the source for the Krypton website.

Important files:

- `web/site/site.htk` - page/layout source
- `web/site/export.htk` - static export builder
- `web/site/dist/` - generated website output

The usual flow:

```bash
cd web/site
../kweb build
../kweb serve 8080
../kweb deploy example.com username
```

## Live Web Apps vs Static Export

Krypton web code has two common modes.

### Static Export

Best for normal websites.

The `.htk` program writes HTML files into `dist/`. Host serves plain files.

Use this for:

- docs
- landing pages
- blogs
- project sites
- pages deployed by FTP/SFTP

### Live Server

Best for demos and local tools.

The `.htk` program handles requests and responds dynamically.

Examples live in `web/examples/`:

- `hello.htk`
- `form.htk`
- `router.htk`
- `interactive.htk`
- `features.htk`

## Objective-K GUI

`web/kweb_gui.ks` is the native macOS GUI wrapper for kweb.

It is KryptScript compiled by `kcc`, using Objective-K/Cocoa helpers:

- project path
- kweb binary path
- host/user/password fields
- optional remote folder for deploys
- build button
- deploy button
- open `dist/`
- log pane

The remote folder field controls where `dist/` lands on the server:

- empty remote folder: `dist/index.html` uploads to `index.html`
- `pages`: `dist/index.html` uploads to `pages/index.html`
- `sites/krypton`: `dist/index.html` uploads to `sites/krypton/index.html`

Do not enter `public_html` for Hostinger FTP accounts that already start inside
the website root.

Build app bundle:

```bash
bootstrap/kcc_driver_macos_aarch64 -r scripts/build-objk-app.ks web/kweb_gui.ks kweb_gui
```

Output:

```text
dist/kweb_gui.app
```

## Mental Model

When writing a static Krypton website:

1. Write HTML-producing functions in `.htk`.
2. Keep shared layout in functions.
3. Make one function per page.
4. In `export.htk`, call those page functions.
5. Write each result into `dist/*.html`.
6. Preview `dist/`.
7. Deploy `dist/`.

The page is "converted" because Krypton runs your page functions and the final
strings they emit are saved as `.html` files.
