// URL encode/decode round-trip + edge cases.
import "k:url"

func expect(label, got, want) {
    if got != want {
        kp("FAIL " + label)
        kp("  want: [" + want + "]")
        kp("  got:  [" + got + "]")
        exit("1")
    }
}

just run {
    // Unreserved survives.
    expect("safe alnum",      urlEncode("abcXYZ012"),       "abcXYZ012")
    expect("safe special",    urlEncode("a-b_c.d~e"),       "a-b_c.d~e")

    // Reserved gets percent-encoded.
    expect("space",           urlEncode("hi mom"),          "hi%20mom")
    expect("slash",           urlEncode("a/b"),             "a%2Fb")
    expect("amp",             urlEncode("a&b"),             "a%26b")
    expect("equals",          urlEncode("a=b"),             "a%3Db")

    // Query variant: space → +.
    expect("query space",     urlEncodeQuery("hi mom"),     "hi+mom")
    expect("query amp",       urlEncodeQuery("a&b"),        "a%26b")

    // Round-trip.
    expect("decode space",    urlDecode("hi%20mom"),        "hi mom")
    expect("decode slash",    urlDecode("a%2Fb"),           "a/b")
    expect("decode case",     urlDecode("a%2fB"),           "a/B")     // lowercase hex
    expect("decode amp",      urlDecodeQuery("a%26b"),      "a&b")
    expect("decode q space",  urlDecodeQuery("hi+mom"),     "hi mom")
    expect("decode q plus",   urlDecode("hi+mom"),          "hi+mom")   // urlDecode keeps +

    // Lone % stays literal if not followed by 2 hex digits.
    expect("bare percent",    urlDecode("a%zz"),            "a%zz")

    // urlBuild: empty query returns base.
    expect("build empty",     urlBuild("/x", ""),           "/x")
    expect("build one",       urlBuild("/api", "q=hi mom"), "/api?q=hi+mom")
    expect("build two",       urlBuild("/api", "k=a,v=b c"), "/api?k=a&v=b+c")

    kp("ok")
}
