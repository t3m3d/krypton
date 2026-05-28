// htmk smoke — covers each shape (escape, attr, container,
// void, composite, 2.1.1 additions). Trimmed assertions because
// large-stdlib imports trip x64.k's slow-codegen path.
import "k:htmk"

func expect(label, got, want) {
    if got != want {
        kp("FAIL " + label)
        exit("1")
    }
}

just run {
    expect("escape",   htEscape("a<b&\"c\""),    "a&lt;b&amp;&quot;c&quot;")
    expect("attr",     htAttr("id", "x"),         " id=\"x\"")
    expect("p",        htP("hi"),                 "<p>hi</p>")
    expect("a",        htA("/x", "go"),           "<a href=\"/x\">go</a>")
    expect("img",      htImg("/i", "alt"),        "<img src=\"/i\" alt=\"alt\">")
    expect("br",       htBr(),                    "<br>")
    expect("checked",  htChecked(),               " checked")
    // 2.1.1 additions:
    expect("mark",     htMark("x"),               "<mark>x</mark>")
    expect("time",     htTime("2026-05-27", "t"), "<time datetime=\"2026-05-27\">t</time>")
    expect("hx-get",   htHxGet("/api"),           " hx-get=\"/api\"")
    expect("hx-swap",  htHxSwap("outerHTML"),     " hx-swap=\"outerHTML\"")

    kp("ok")
}
