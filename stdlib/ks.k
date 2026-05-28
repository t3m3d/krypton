// ks.k — KryptonScript: emit JavaScript from Krypton
// Use with htScriptInline() to embed client-side behavior in .htk apps.
//
//   let js = ksOnClick("btn", ksSetText("output", ksStr("Clicked!")))
//   htScriptInline(ksReady(js))

module ks

// ── Literals + expressions ───────────────────────────────────────────

func ksStr(s)       { emit "\"" + s + "\"" }
func ksNum(n)       { emit n + "" }
func ksTrue()       { emit "true" }
func ksFalse()      { emit "false" }
func ksNull()       { emit "null" }
func ksNot(expr)    { emit "!" + expr }
func ksPlus(a, b)   { emit a + " + " + b }
func ksMinus(a, b)  { emit a + " - " + b }
func ksTimes(a, b)  { emit a + " * " + b }
func ksDiv(a, b)    { emit a + " / " + b }
func ksMod(a, b)    { emit a + " % " + b }
func ksEq(a, b)     { emit a + " === " + b }
func ksNeq(a, b)    { emit a + " !== " + b }
func ksLt(a, b)     { emit a + " < " + b }
func ksGt(a, b)     { emit a + " > " + b }
func ksAnd(a, b)    { emit a + " && " + b }
func ksOr(a, b)     { emit a + " || " + b }
func ksTernary(cond, t, f) { emit "(" + cond + " ? " + t + " : " + f + ")" }

// ── Variables ────────────────────────────────────────────────────────

func ksLet(nm, val)    { emit "let " + nm + " = " + val + ";\n" }
func ksConst(nm, val)  { emit "const " + nm + " = " + val + ";\n" }
func ksAssign(nm, val) { emit nm + " = " + val + ";\n" }
func ksIncr(nm)        { emit nm + "++;\n" }
func ksDecr(nm)        { emit nm + "--;\n" }

// ── DOM ──────────────────────────────────────────────────────────────

func ksGetEl(id)                 { emit "document.getElementById(" + ksStr(id) + ")" }
func ksQuery(sel)                { emit "document.querySelector(" + ksStr(sel) + ")" }
func ksQueryAll(sel)             { emit "document.querySelectorAll(" + ksStr(sel) + ")" }
func ksSetText(id, val)          { emit ksGetEl(id) + ".textContent = " + val + ";\n" }
func ksSetHtml(id, val)          { emit ksGetEl(id) + ".innerHTML = " + val + ";\n" }
func ksGetText(id)               { emit ksGetEl(id) + ".textContent" }
func ksGetVal(id)                { emit ksGetEl(id) + ".value" }
func ksSetVal(id, val)           { emit ksGetEl(id) + ".value = " + val + ";\n" }
func ksSetAttr(id, attr, val)    { emit ksGetEl(id) + ".setAttribute(" + ksStr(attr) + ", " + val + ");\n" }
func ksRemoveAttr(id, attr)      { emit ksGetEl(id) + ".removeAttribute(" + ksStr(attr) + ");\n" }
func ksAddClass(id, cls)         { emit ksGetEl(id) + ".classList.add(" + ksStr(cls) + ");\n" }
func ksRemoveClass(id, cls)      { emit ksGetEl(id) + ".classList.remove(" + ksStr(cls) + ");\n" }
func ksToggleClass(id, cls)      { emit ksGetEl(id) + ".classList.toggle(" + ksStr(cls) + ");\n" }
func ksHide(id)                  { emit ksGetEl(id) + ".style.display = " + ksStr("none") + ";\n" }
func ksShow(id)                  { emit ksGetEl(id) + ".style.display = " + ksStr("") + ";\n" }
func ksSetStyle(id, prop, val)   { emit ksGetEl(id) + ".style." + prop + " = " + val + ";\n" }

// ── Events ───────────────────────────────────────────────────────────

func ksOnClick(id, body)     { emit ksGetEl(id) + ".addEventListener(" + ksStr("click") + ", function(e) {\n" + body + "});\n" }
func ksOnSubmit(id, body)    { emit ksGetEl(id) + ".addEventListener(" + ksStr("submit") + ", function(e) {\ne.preventDefault();\n" + body + "});\n" }
func ksOnInput(id, body)     { emit ksGetEl(id) + ".addEventListener(" + ksStr("input") + ", function(e) {\n" + body + "});\n" }
func ksOnChange(id, body)    { emit ksGetEl(id) + ".addEventListener(" + ksStr("change") + ", function(e) {\n" + body + "});\n" }
func ksOnKeydown(id, body)   { emit ksGetEl(id) + ".addEventListener(" + ksStr("keydown") + ", function(e) {\n" + body + "});\n" }
func ksOnEvent(id, evt, body) { emit ksGetEl(id) + ".addEventListener(" + ksStr(evt) + ", function(e) {\n" + body + "});\n" }
func ksOnReady(body)         { emit "document.addEventListener(" + ksStr("DOMContentLoaded") + ", function() {\n" + body + "});\n" }

// ── Control flow ─────────────────────────────────────────────────────

func ksIf(cond, body)           { emit "if (" + cond + ") {\n" + body + "}\n" }
func ksIfElse(cond, t, f)      { emit "if (" + cond + ") {\n" + t + "} else {\n" + f + "}\n" }
func ksWhile(cond, body)        { emit "while (" + cond + ") {\n" + body + "}\n" }
func ksFor(init, cond, step, body) { emit "for (" + init + "; " + cond + "; " + step + ") {\n" + body + "}\n" }
func ksForEach(arr, varNm, body)   { emit arr + ".forEach(function(" + varNm + ") {\n" + body + "});\n" }

// ── Functions ────────────────────────────────────────────────────────

func ksFunc(nm, params, body)    { emit "function " + nm + "(" + params + ") {\n" + body + "}\n" }
func ksArrow(params, body)       { emit "(" + params + ") => {\n" + body + "}" }
func ksReturn(val)               { emit "return " + val + ";\n" }
func ksCall(nm, args)            { emit nm + "(" + args + ");\n" }

// ── Console + alerts ─────────────────────────────────────────────────

func ksLog(val)     { emit "console.log(" + val + ");\n" }
func ksAlert(val)   { emit "alert(" + val + ");\n" }
func ksConfirm(val) { emit "confirm(" + val + ")" }
func ksPrompt(val)  { emit "prompt(" + val + ")" }

// ── Fetch / AJAX ─────────────────────────────────────────────────────

func ksFetch(url, thenBody) {
    emit "fetch(" + ksStr(url) + ").then(function(r) { return r.json(); }).then(function(data) {\n" + thenBody + "});\n"
}

func ksFetchPost(url, bodyExpr, thenBody) {
    emit "fetch(" + ksStr(url) + ", { method: " + ksStr("POST") + ", headers: { " + ksStr("Content-Type") + ": " + ksStr("application/json") + " }, body: JSON.stringify(" + bodyExpr + ") }).then(function(r) { return r.json(); }).then(function(data) {\n" + thenBody + "});\n"
}

// ── Timers ───────────────────────────────────────────────────────────

func ksTimeout(ms, body)  { emit "setTimeout(function() {\n" + body + "}, " + ms + ");\n" }
func ksInterval(ms, body) { emit "setInterval(function() {\n" + body + "}, " + ms + ");\n" }

// ── Convenience wrappers ─────────────────────────────────────────────

func ksReady(body) { emit ksOnReady(body) }

func ksCounter(btnId, displayId) {
    emit ksLet("_count", "0") +
         ksOnClick(btnId,
            ksAssign("_count", "_count + 1") +
            ksSetText(displayId, "_count")
         )
}

func ksToggle(btnId, targetId) {
    emit ksOnClick(btnId,
        ksLet("el", ksGetEl(targetId)) +
        ksIfElse("el.style.display === " + ksStr("none"),
            ksAssign("el.style.display", ksStr("")),
            ksAssign("el.style.display", ksStr("none"))
        )
    )
}

// ── Local / Session storage ──────────────────────────────────────────

func ksLocalSet(key, val)      { emit "localStorage.setItem(" + ksStr(key) + ", " + val + ");\n" }
func ksLocalGet(key)           { emit "localStorage.getItem(" + ksStr(key) + ")" }
func ksLocalRemove(key)        { emit "localStorage.removeItem(" + ksStr(key) + ");\n" }
func ksLocalClear()            { emit "localStorage.clear();\n" }
func ksSessionSet(key, val)    { emit "sessionStorage.setItem(" + ksStr(key) + ", " + val + ");\n" }
func ksSessionGet(key)         { emit "sessionStorage.getItem(" + ksStr(key) + ")" }
func ksSessionRemove(key)      { emit "sessionStorage.removeItem(" + ksStr(key) + ");\n" }

// ── JSON ─────────────────────────────────────────────────────────────

func ksJsonParse(expr)         { emit "JSON.parse(" + expr + ")" }
func ksJsonStringify(expr)     { emit "JSON.stringify(" + expr + ")" }

// ── Dynamic DOM creation ─────────────────────────────────────────────

func ksCreateEl(tag)              { emit "document.createElement(" + ksStr(tag) + ")" }
func ksCreateText(text)           { emit "document.createTextNode(" + text + ")" }
func ksAppend(parent, child)      { emit parent + ".appendChild(" + child + ");\n" }
func ksRemove(el)                 { emit el + ".remove();\n" }
func ksInsertBefore(parent, nw, ref) { emit parent + ".insertBefore(" + nw + ", " + ref + ");\n" }
func ksInsertHTML(id, pos, html)  { emit ksGetEl(id) + ".insertAdjacentHTML(" + ksStr(pos) + ", " + html + ");\n" }
func ksClone(el, deep)            { emit el + ".cloneNode(" + deep + ")" }

// ── classList extras ─────────────────────────────────────────────────

func ksHasClass(id, cls)          { emit ksGetEl(id) + ".classList.contains(" + ksStr(cls) + ")" }
func ksReplaceClass(id, old, nw)  { emit ksGetEl(id) + ".classList.replace(" + ksStr(old) + ", " + ksStr(nw) + ");\n" }

// ── History / SPA routing ────────────────────────────────────────────

func ksHistoryPush(url)           { emit "history.pushState(null, '', " + ksStr(url) + ");\n" }
func ksHistoryReplace(url)        { emit "history.replaceState(null, '', " + ksStr(url) + ");\n" }
func ksOnPopstate(body)           { emit "window.addEventListener('popstate', function(e) {\n" + body + "});\n" }
func ksLocation()                 { emit "window.location.pathname" }
func ksLocationFull()             { emit "window.location.href" }
func ksNavigate(url)              { emit "window.location.href = " + ksStr(url) + ";\n" }
func ksReload()                   { emit "window.location.reload();\n" }

// ── Array / Object helpers ───────────────────────────────────────────

func ksMap(arr, varNm, expr)      { emit arr + ".map(function(" + varNm + ") { return " + expr + "; })" }
func ksFilter(arr, varNm, cond)   { emit arr + ".filter(function(" + varNm + ") { return " + cond + "; })" }
func ksReduce(arr, acc, cur, expr) { emit arr + ".reduce(function(" + acc + ", " + cur + ") { return " + expr + "; }, 0)" }
func ksKeys(obj)                  { emit "Object.keys(" + obj + ")" }
func ksEntries(obj)               { emit "Object.entries(" + obj + ")" }
func ksLength(arr)                { emit arr + ".length" }
func ksJoin(arr, sep)             { emit arr + ".join(" + ksStr(sep) + ")" }
func ksPush(arr, val)             { emit arr + ".push(" + val + ");\n" }
func ksSplice(arr, idx, cnt)      { emit arr + ".splice(" + idx + ", " + cnt + ");\n" }
func ksIncludes(arr, val)         { emit arr + ".includes(" + val + ")" }
func ksIndexOf(arr, val)          { emit arr + ".indexOf(" + val + ")" }

// ── WebSocket ────────────────────────────────────────────────────────

func ksWebSocket(url, varNm)      { emit "var " + varNm + " = new WebSocket(" + ksStr(url) + ");\n" }
func ksWsOnOpen(varNm, body)      { emit varNm + ".onopen = function() {\n" + body + "};\n" }
func ksWsOnMessage(varNm, body)   { emit varNm + ".onmessage = function(e) {\n" + body + "};\n" }
func ksWsOnClose(varNm, body)     { emit varNm + ".onclose = function() {\n" + body + "};\n" }
func ksWsSend(varNm, data)        { emit varNm + ".send(" + data + ");\n" }
func ksWsClose(varNm)             { emit varNm + ".close();\n" }

// ── Clipboard ────────────────────────────────────────────────────────

func ksCopyText(expr) { emit "navigator.clipboard.writeText(" + expr + ");\n" }

// ── Scroll ───────────────────────────────────────────────────────────

func ksScrollTo(id)    { emit ksGetEl(id) + ".scrollIntoView({behavior:'smooth'});\n" }
func ksScrollTop()     { emit "window.scrollTo({top:0,behavior:'smooth'});\n" }

// ── Media queries ────────────────────────────────────────────────────

func ksMatchMedia(query, body) { emit "if(window.matchMedia(" + ksStr(query) + ").matches){\n" + body + "}\n" }
