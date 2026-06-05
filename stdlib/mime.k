// stdlib/mime.k — MIME type lookup by file extension.
//
// Static table covering the common web + dev formats. Companion to
// k:server_native / k:http / k:fs for serving static files.
//
// API:
//   mimeFromExt(ext)    -> MIME string (".html"->"text/html"); "application/octet-stream" on miss
//   mimeFromPath(path)  -> MIME string for the path's extension
//
// Usage:
//   import "k:mime"
//   mimeFromPath("/style.css")     // "text/css"
//   mimeFromPath("/img/logo.png")  // "image/png"
//   mimeFromExt(".json")           // "application/json"

module mime

func _eq(a, b) {
    if a == b { emit 1 }
    emit 0
}

func mimeFromExt(ext) {
    let e = ext
    if len(e) > 0 && e[0] == "." { e = substring(e, 1, len(e)) }
    e = toLower(e)
    // Text + web
    if _eq(e, "html") == 1 { emit "text/html" }
    if _eq(e, "htm")  == 1 { emit "text/html" }
    if _eq(e, "css")  == 1 { emit "text/css" }
    if _eq(e, "js")   == 1 { emit "application/javascript" }
    if _eq(e, "mjs")  == 1 { emit "application/javascript" }
    if _eq(e, "json") == 1 { emit "application/json" }
    if _eq(e, "xml")  == 1 { emit "application/xml" }
    if _eq(e, "txt")  == 1 { emit "text/plain" }
    if _eq(e, "md")   == 1 { emit "text/markdown" }
    if _eq(e, "csv")  == 1 { emit "text/csv" }
    if _eq(e, "atom") == 1 { emit "application/atom+xml" }
    if _eq(e, "rss")  == 1 { emit "application/rss+xml" }
    if _eq(e, "svg")  == 1 { emit "image/svg+xml" }
    // Images
    if _eq(e, "png")  == 1 { emit "image/png" }
    if _eq(e, "jpg")  == 1 { emit "image/jpeg" }
    if _eq(e, "jpeg") == 1 { emit "image/jpeg" }
    if _eq(e, "gif")  == 1 { emit "image/gif" }
    if _eq(e, "webp") == 1 { emit "image/webp" }
    if _eq(e, "ico")  == 1 { emit "image/x-icon" }
    if _eq(e, "bmp")  == 1 { emit "image/bmp" }
    if _eq(e, "tiff") == 1 { emit "image/tiff" }
    if _eq(e, "avif") == 1 { emit "image/avif" }
    // Fonts
    if _eq(e, "woff")  == 1 { emit "font/woff" }
    if _eq(e, "woff2") == 1 { emit "font/woff2" }
    if _eq(e, "ttf")   == 1 { emit "font/ttf" }
    if _eq(e, "otf")   == 1 { emit "font/otf" }
    if _eq(e, "eot")   == 1 { emit "application/vnd.ms-fontobject" }
    // Audio / video
    if _eq(e, "mp3")  == 1 { emit "audio/mpeg" }
    if _eq(e, "wav")  == 1 { emit "audio/wav" }
    if _eq(e, "ogg")  == 1 { emit "audio/ogg" }
    if _eq(e, "flac") == 1 { emit "audio/flac" }
    if _eq(e, "mp4")  == 1 { emit "video/mp4" }
    if _eq(e, "webm") == 1 { emit "video/webm" }
    if _eq(e, "mkv")  == 1 { emit "video/x-matroska" }
    if _eq(e, "mov")  == 1 { emit "video/quicktime" }
    // Code / data
    if _eq(e, "wasm") == 1 { emit "application/wasm" }
    if _eq(e, "pdf")  == 1 { emit "application/pdf" }
    if _eq(e, "zip")  == 1 { emit "application/zip" }
    if _eq(e, "gz")   == 1 { emit "application/gzip" }
    if _eq(e, "tar")  == 1 { emit "application/x-tar" }
    if _eq(e, "7z")   == 1 { emit "application/x-7z-compressed" }
    if _eq(e, "yaml") == 1 { emit "application/yaml" }
    if _eq(e, "yml")  == 1 { emit "application/yaml" }
    if _eq(e, "toml") == 1 { emit "application/toml" }
    if _eq(e, "ini")  == 1 { emit "text/plain" }
    if _eq(e, "k")    == 1 { emit "text/x-krypton" }
    if _eq(e, "ks")   == 1 { emit "text/x-krypton" }
    if _eq(e, "krh")  == 1 { emit "text/x-krypton-header" }
    if _eq(e, "htk")  == 1 { emit "text/x-krypton-template" }
    emit "application/octet-stream"
}

func mimeFromPath(path) {
    let dot = 0 - 1
    let i = 0
    let n = len(path)
    // Find LAST '.' that isn't part of "..".
    while i < n {
        if path[i] == "." { dot = i }
        i += 1
    }
    if dot < 0 { emit "application/octet-stream" }
    emit mimeFromExt(substring(path, dot, len(path)))
}

// ── Category predicates (return "1" / "0") ───────────────────────────

func _mimeStarts(mime, pfx) {
    if len(mime) < len(pfx) { emit "0" }
    if substring(mime, 0, len(pfx)) == pfx { emit "1" }
    emit "0"
}

func isImage(mime) { emit _mimeStarts(mime, "image/") }
func isAudio(mime) { emit _mimeStarts(mime, "audio/") }
func isVideo(mime) { emit _mimeStarts(mime, "video/") }
func isText(mime)  { emit _mimeStarts(mime, "text/") }
func isApp(mime)   { emit _mimeStarts(mime, "application/") }
func isFont(mime)  { emit _mimeStarts(mime, "font/") }

// True iff mime is one of the common JSON/JSONP variants.
func isJson(mime) {
    if mime == "application/json" { emit "1" }
    if mime == "application/javascript" { emit "1" }
    if mime == "application/x-json" { emit "1" }
    emit "0"
}

// True iff mime is binary in the loose sense (not text/* and not json).
func isBinary(mime) {
    if _mimeStarts(mime, "text/") == "1" { emit "0" }
    if isJson(mime) == "1" { emit "0" }
    if mime == "application/xml" { emit "0" }
    if mime == "application/x-yaml" { emit "0" }
    emit "1"
}
