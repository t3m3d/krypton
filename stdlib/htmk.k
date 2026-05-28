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

func htScript(src)              { emit htElA("script", htSrc(src), "") }
func htScriptInline(code)       { emit "<script>" + code + "</script>" }
func htStyle(content)           { emit htEl("style", content) }
func htLink(rel, href)          { emit htVoid("link", htAttr("rel", rel) + htHref(href)) }
func htMeta(name, content)      { emit htVoid("meta", htAttr("name", name) + htAttr("content", content)) }
func htMetaCharset(charset)     { emit htVoid("meta", htAttr("charset", charset)) }
func htMetaViewport()           { emit htVoid("meta", htAttr("name", "viewport") + htAttr("content", "width=device-width, initial-scale=1.0")) }

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
