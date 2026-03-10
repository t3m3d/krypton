just run {
  let src = readFile("kompiler/run.k")
  let toks = tokenize(src)
  kp("Run.k token count: " + lineCount(toks))
  emit "ok"
}
