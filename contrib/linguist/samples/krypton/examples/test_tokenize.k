just run {
  let src = readFile("examples/hello.k")
  let toks = tokenize(src)
  kp("TOKEN COUNT: " + lineCount(toks))
  let i = 0
  while i < lineCount(toks) {
    kp("[" + i + "] " + tokAt(toks, i))
    i += 1
  }
  emit "ok"
}
