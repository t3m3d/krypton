// `do` is Krypton's no-result / action-only return annotation.
func tap() -> do {
    print("tap")
}

just run {
    tap()
    print("done")
}