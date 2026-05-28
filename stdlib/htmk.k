module htmk

func htEscape(s) {
    let out = sbNew()
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c == "&"  { out = sbAppend(out, "&amp;") }
        else if c == "<"  { out = sbAppend(out, "&lt;") }
        else if c == ">"  { out = sbAppend(out, "&gt;") }
        else if c == "\"" { out = sbAppend(out, "&quot;") }
        else { out = sbAppend(out, c) }
        i += 1
    }
    emit sbToString(out)
}

func htAttr(name, val) {
    emit " " + name + "=\"" + htEscape(val) + "\""
}

func htClass(c)       { emit htAttr("class", c) }
func htId(i)          { emit htAttr("id", i) }
func htHref(url)      { emit htAttr("href", url) }
func htSrc(url)       { emit htAttr("src", url) }
func htType(t)        { emit htAttr("type", t) }
func htName(n)        { emit htAttr("name", n) }
func htValue(v)       { emit htAttr("value", v) }
func htFor(f)         { emit htAttr("for", f) }
func htAction(a)      { emit htAttr("action", a) }
func htMethod(m)      { emit htAttr("method", m) }
func htPlaceholder(p) { emit htAttr("placeholder", p) }
func htStyleAttr(s)   { emit htAttr("style", s) }
func htOnClick(handler) { emit htAttr("onclick", handler) }

func htEl(tag, content) {
    emit "<" + tag + ">" + content + "</" + tag + ">"
}

func htElA(tag, attrs, content) {
    emit "<" + tag + attrs + ">" + content + "</" + tag + ">"
}

func htVoid(tag, attrs) {
    emit "<" + tag + attrs + ">"
}

func htDiv(content)              { emit htEl("div", content) }
func htDivA(attrs, content)      { emit htElA("div", attrs, content) }
func htSpan(content)             { emit htEl("span", content) }
func htSpanA(attrs, content)     { emit htElA("span", attrs, content) }
func htP(content)                { emit htEl("p", content) }
func htPA(attrs, content)        { emit htElA("p", attrs, content) }
func htH1(content)               { emit htEl("h1", content) }
func htH2(content)               { emit htEl("h2", content) }
func htH3(content)               { emit htEl("h3", content) }
func htH4(content)               { emit htEl("h4", content) }
func htH5(content)               { emit htEl("h5", content) }
func htH6(content)               { emit htEl("h6", content) }
func htSection(content)          { emit htEl("section", content) }
func htSectionA(attrs, content)  { emit htElA("section", attrs, content) }
func htArticle(content)          { emit htEl("article", content) }
func htHeader(content)           { emit htEl("header", content) }
func htFooter(content)           { emit htEl("footer", content) }
func htNav(content)              { emit htEl("nav", content) }
func htMain(content)             { emit htEl("main", content) }
func htAside(content)            { emit htEl("aside", content) }
func htStrong(content)           { emit htEl("strong", content) }
func htEm(content)               { emit htEl("em", content) }
func htCode(content)             { emit htEl("code", content) }
func htPre(content)              { emit htEl("pre", content) }
func htBlockquote(content)       { emit htEl("blockquote", content) }
func htLabel(content)            { emit htEl("label", content) }
func htLabelFor(forId, content)  { emit htElA("label", htFor(forId), content) }

func htA(href, content)     { emit htElA("a", htHref(href), content) }
func htAA(attrs, content)   { emit htElA("a", attrs, content) }
func htImg(src, alt)        { emit htVoid("img", htSrc(src) + htAttr("alt", alt)) }
func htImgA(attrs)          { emit htVoid("img", attrs) }
func htBr()                 { emit "<br>" }
func htHr()                 { emit "<hr>" }

func htUl(content)          { emit htEl("ul", content) }
func htUlA(attrs, content)  { emit htElA("ul", attrs, content) }
func htOl(content)          { emit htEl("ol", content) }
func htOlA(attrs, content)  { emit htElA("ol", attrs, content) }
func htLi(content)          { emit htEl("li", content) }
func htLiA(attrs, content)  { emit htElA("li", attrs, content) }

func htTable(content)       { emit htEl("table", content) }
func htTableA(attrs, content) { emit htElA("table", attrs, content) }
func htThead(content)       { emit htEl("thead", content) }
func htTbody(content)       { emit htEl("tbody", content) }
func htTr(content)          { emit htEl("tr", content) }
func htTrA(attrs, content)  { emit htElA("tr", attrs, content) }
func htTd(content)          { emit htEl("td", content) }
func htTdA(attrs, content)  { emit htElA("td", attrs, content) }
func htTh(content)          { emit htEl("th", content) }
func htThA(attrs, content)  { emit htElA("th", attrs, content) }

func htForm(action, method, content) {
    emit htElA("form", htAction(action) + htMethod(method), content)
}
func htFormA(attrs, content)    { emit htElA("form", attrs, content) }
func htInput(typ, nm, val) {
    emit htVoid("input", htType(typ) + htName(nm) + htValue(val))
}
func htInputA(attrs)            { emit htVoid("input", attrs) }
func htTextarea(nm, content)    { emit htElA("textarea", htName(nm), content) }
func htButton(content)          { emit htEl("button", content) }
func htButtonA(attrs, content)  { emit htElA("button", attrs, content) }
func htSelect(nm, content)      { emit htElA("select", htName(nm), content) }
func htOption(val, content)     { emit htElA("option", htValue(val), content) }

// ── HTML5 interactive + media ─────────────────────────────────────

func htDetails(content)          { emit htEl("details", content) }
func htDetailsA(attrs, content)  { emit htElA("details", attrs, content) }
func htSummary(content)          { emit htEl("summary", content) }
func htDialog(content)           { emit htEl("dialog", content) }
func htDialogA(attrs, content)   { emit htElA("dialog", attrs, content) }
func htProgress(val, mx)         { emit htElA("progress", htValue(val) + htAttr("max", mx), "") }
func htMeter(val, mn, mx)        { emit htElA("meter", htValue(val) + htAttr("min", mn) + htAttr("max", mx), "") }
func htVideo(src, attrs)         { emit htElA("video", htSrc(src) + attrs, "Your browser does not support video.") }
func htAudio(src, attrs)         { emit htElA("audio", htSrc(src) + attrs, "Your browser does not support audio.") }
func htIframe(src, attrs)        { emit htElA("iframe", htSrc(src) + attrs, "") }
func htCanvas(idVal, w, h)       { emit htElA("canvas", htId(idVal) + htAttr("width", w) + htAttr("height", h), "") }
func htPicture(content)          { emit htEl("picture", content) }
func htSource(src, typ)          { emit htVoid("source", htSrc(src) + htType(typ)) }
func htFieldset(content)         { emit htEl("fieldset", content) }
func htFieldsetA(attrs, content) { emit htElA("fieldset", attrs, content) }
func htLegend(content)           { emit htEl("legend", content) }
func htOptgroup(label, content)  { emit htElA("optgroup", htAttr("label", label), content) }
func htDatalist(idVal, content)  { emit htElA("datalist", htId(idVal), content) }

// ── Common attributes ────────────────────────────────────────────

func htDisabled()   { emit " disabled" }
func htRequired()   { emit " required" }
func htReadonly()   { emit " readonly" }
func htAutofocus()  { emit " autofocus" }
func htChecked()    { emit " checked" }
func htSelected()   { emit " selected" }
func htAutoplay()   { emit " autoplay" }
func htControls()   { emit " controls" }
func htLoop()       { emit " loop" }
func htMuted()      { emit " muted" }
func htOpen()       { emit " open" }
func htData(nm, v)  { emit htAttr("data-" + nm, v) }
func htRole(r)      { emit htAttr("role", r) }
func htAria(nm, v)  { emit htAttr("aria-" + nm, v) }
func htTitle(t)     { emit htAttr("title", t) }
func htAlt(a)       { emit htAttr("alt", a) }
func htWidth(w)     { emit htAttr("width", w) }
func htHeight(h)    { emit htAttr("height", h) }
func htTarget(t)    { emit htAttr("target", t) }
func htRel(r)       { emit htAttr("rel", r) }

func htScript(src)              { emit htElA("script", htSrc(src), "") }
func htScriptInline(code)       { emit "<script>" + code + "</script>" }
func htStyle(content)           { emit htEl("style", content) }
func htLink(rel, href)          { emit htVoid("link", htAttr("rel", rel) + htHref(href)) }
func htMeta(name, content)      { emit htVoid("meta", htAttr("name", name) + htAttr("content", content)) }
func htMetaCharset(charset)     { emit htVoid("meta", htAttr("charset", charset)) }
func htMetaViewport()           { emit htVoid("meta", htAttr("name", "viewport") + htAttr("content", "width=device-width, initial-scale=1.0")) }

// HTML5 inline / semantic gaps.
func htFigure(content)           { emit htEl("figure", content) }
func htFigcaption(content)       { emit htEl("figcaption", content) }
func htMark(content)             { emit htEl("mark", content) }
func htTime(datetime, content)   { emit htElA("time", htAttr("datetime", datetime), content) }
func htAddress(content)          { emit htEl("address", content) }
func htAbbr(title, content)      { emit htElA("abbr", htTitle(title), content) }
func htCite(content)             { emit htEl("cite", content) }
func htKbd(content)              { emit htEl("kbd", content) }
func htSamp(content)             { emit htEl("samp", content) }
func htVar(content)              { emit htEl("var", content) }
func htQ(content)                { emit htEl("q", content) }
func htSub(content)              { emit htEl("sub", content) }
func htSup(content)              { emit htEl("sup", content) }
func htSmall(content)            { emit htEl("small", content) }
func htDel(content)              { emit htEl("del", content) }
func htIns(content)              { emit htEl("ins", content) }
func htHgroup(content)           { emit htEl("hgroup", content) }
func htDl(content)               { emit htEl("dl", content) }
func htDt(content)               { emit htEl("dt", content) }
func htDd(content)               { emit htEl("dd", content) }
func htCaption(content)          { emit htEl("caption", content) }
func htTfoot(content)            { emit htEl("tfoot", content) }
func htColgroup(content)         { emit htEl("colgroup", content) }
func htCol(attrs)                { emit htVoid("col", attrs) }

// htmx-style live-update attributes — pair with a 4 KB htmx.js
// shim in the page <head> for in-place fragment swapping. Server-
// side: hand the corresponding URLs through k:server and emit raw
// HTML fragments (no full htPage wrap).
func htHxGet(url)     { emit htAttr("hx-get", url) }
func htHxPost(url)    { emit htAttr("hx-post", url) }
func htHxPut(url)     { emit htAttr("hx-put", url) }
func htHxDelete(url)  { emit htAttr("hx-delete", url) }
func htHxTarget(sel)  { emit htAttr("hx-target", sel) }
func htHxSwap(mode)   { emit htAttr("hx-swap", mode) }
func htHxTrigger(ev)  { emit htAttr("hx-trigger", ev) }
func htHxConfirm(msg) { emit htAttr("hx-confirm", msg) }

func htPage(title, headExtra, body) {
    let NL = "\n"
    emit "<!DOCTYPE html>" + NL +
         "<html lang=\"en\">" + NL +
         "<head>" + NL +
         htMetaCharset("UTF-8") + NL +
         htMetaViewport() + NL +
         htEl("title", title) + NL +
         headExtra + NL +
         "</head>" + NL +
         "<body>" + NL +
         body + NL +
         "</body>" + NL +
         "</html>"
}
