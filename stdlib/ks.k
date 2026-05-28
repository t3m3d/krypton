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
