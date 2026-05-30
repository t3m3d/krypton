// Tutorial 32: HTML in Krypton with htmk
// k:htmk emits HTML strings. Compose with + into a full document.
// Every helper returns a string; combine them to build pages.

import "k:htmk"

just run {
    // Single elements
    kp(htH1("Hello, Krypton"))
    kp(htP("Pure Krypton emits this HTML."))

    // Wrappers + attributes
    let card = htDiv(
        htH3("A card") +
        htP("Composed from htmk helpers.")
    )
    kp(card)

    // Links and lists
    kp(htA("https://krypton-lang.org", "Visit krypton-lang.org"))

    let menu = htUl(
        htLi(htA("/", "Home")) +
        htLi(htA("/learn.html", "Learn")) +
        htLi(htA("/blog.html", "Blog"))
    )
    kp(menu)

    // Full document: htPage wraps with <!DOCTYPE>, <head>, <body>.
    let page = htPage("My Page", "",
        htH1("Welcome") +
        htP("Built end-to-end in Krypton.")
    )
    kp(page)
}
