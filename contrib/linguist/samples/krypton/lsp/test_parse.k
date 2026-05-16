// Quick standalone test of jpParse to debug the JSON parser.

import "json_parse.k"

just run {
    let frame = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"
    kp("input: " + frame)

    // step through manually
    let st = jpNew(frame)
    kp("after jpNew: i=" + jpI(st) + " line=" + jpLine(st) + " col=" + jpCol(st))
    kp("text len: " + len(jpText(st)))
    kp("peek: '" + jpPeek(st) + "'")
    st = jpSkipWS(st)
    kp("after skipWS: i=" + jpI(st))
    kp("peek: '" + jpPeek(st) + "'")

    let m0 = jmNew()
    let r = jpParseValue(st, "", m0)
    kp("parsed result len: " + len(r))
    let mAfter = jpMap(r)
    kp("map after: '" + mAfter + "' len=" + len(mAfter))

    let m = jpParse(frame)
    kp("map len: " + len(m))
    // Dump map with control chars made visible
    let i = 0
    let sb = sbNew()
    let sep3 = fromCharCode(3)
    let sep4 = fromCharCode(4)
    while i < len(m) {
        let c = m[i]
        if c == sep3 { sb = sbAppend(sb, "<EOR>\n") }
        else if c == sep4 { sb = sbAppend(sb, "<KV>") }
        else { sb = sbAppend(sb, c) }
        i += 1
    }
    kp("map dump:")
    kp(sbToString(sb))
    kp("---")
    kp("method = '" + jpGet(m, "method") + "'")
    kp("id = '" + jpGet(m, "id") + "'")
    kp("jsonrpc = '" + jpGet(m, "jsonrpc") + "'")
}
