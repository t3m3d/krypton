// Tutorial 34: Hacker News reader, live in your browser
// A real CLI rewritten to run client-side via the lesson runner. Same
// JSON parsing + URL handling as khn (https://github.com/t3m3d/khn);
// HTTP swapped from `exec("curl ...")` to `fetch(url)`, time from
// `exec("date +%s")` to `nowSec()`.

import "k:json_parse"

// Strip the scheme + path so we display just the host of an article URL.
func host(url) {
    let s = url
    if startsWith(s, "https://") { s = substring(s, 8, len(s)) }
    if startsWith(s, "http://")  { s = substring(s, 7, len(s)) }
    let slash = indexOf(s, "/")
    if slash < 0 { emit s }
    emit substring(s, 0, slash)
}

// Relative-age formatter — Krypton handles the unix-time math itself.
func ago(unix) {
    let diff = nowSec() - toInt(unix)
    if diff < 60   { emit "" + diff + "s ago" }
    if diff < 3600 { emit "" + (diff / 60) + "m ago" }
    if diff < 86400 { emit "" + (diff / 3600) + "h ago" }
    emit "" + (diff / 86400) + "d ago"
}

func padL(s, w) {
    let out = ""
    let pad = w - len(s)
    while pad > 0 { out = out + " "; pad -= 1 }
    emit out + s
}

just run {
    let api = "https://hacker-news.firebaseio.com/v0"
    let limit = 10

    kp("Fetching HN top stories...")

    // 1. Top story IDs come back as "[123, 456, 789, ...]".
    let raw = fetch(api + "/topstories.json")
    let cleaned = replace(replace(replace(raw, "[", ""), "]", ""), " ", "")
    let idList = replace(cleaned, ",", "\n")
    let total = lineCount(idList)

    kp("")
    kp("Hacker News — top " + limit + " (live, fetched in your browser)")
    kp("")

    let i = 0
    let shown = 0
    while shown < limit && i < total {
        let id = trim(getLine(idList, i))
        if len(id) > 0 {
            let itemRaw = fetch(api + "/item/" + id + ".json")
            if len(itemRaw) > 0 {
                let jp = jpParse(itemRaw)
                let title = jpGet(jp, "title")
                let score = jpGet(jp, "score")
                let by    = jpGet(jp, "by")
                let url   = jpGet(jp, "url")
                let time  = jpGet(jp, "time")
                let kids  = "0"
                if jpHas(jp, "descendants") {
                    kids = jpGet(jp, "descendants")
                }
                let h = ""
                if len(url) > 0 { h = host(url) }

                // Row 1: rank + score + title.
                kp("#" + padL("" + (shown + 1), 2) + "  " +
                   padL("" + score, 4) + "  " + title)
                // Row 2: meta + comments link.
                let meta = ""
                if len(h) > 0 { meta = h + " | " }
                kp("       " + meta + by + " | " + ago(time) + " | " +
                   kids + " comments")
                kp("       https://news.ycombinator.com/item?id=" + id)
                kp("")
                shown += 1
            }
        }
        i += 1
    }

    kp("--- " + shown + " stories shown. Live data, hit Run again for the latest.")
}
