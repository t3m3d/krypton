// Tutorial 33: Styling with kcss
// k:kcss emits CSS strings the same way k:htmk emits HTML.
// Compose theme + rules + media queries via +.

import "k:kcss"

just run {
    // Theme custom properties via :root.
    let theme = kcssRoot(
        kcssVar("primary", "#7722ff") +
        kcssVar("text",    "#222")
    )
    print(theme)

    // A button rule. kcssDecl makes each line; kcssRule wraps the body.
    let btn = kcssRule(".btn",
        kcssBg(kcssUseVar("primary")) +
        kcssColor("#fff") +
        kcssPadding("12px 24px") +
        kcssRadius("8px")
    )
    print(btn)

    // Hover state via kcssHover selector helper.
    let btnHover = kcssRule(kcssHover(".btn"),
        "transform:translateY(-1px);"
    )
    print(btnHover)

    // Mobile-first override via kcssOnMobile (≤600px).
    let mobile = kcssOnMobile(
        kcssRule(".btn",
            kcssDisplay("block") + kcssWidth("100%")
        )
    )
    print(mobile)

    // Wrap the whole sheet in a <style> tag, ready for htmk to embed.
    let css = theme + btn + btnHover + mobile
    print(kcssStyle(css))
}
