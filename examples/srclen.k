just run {
  let src = readFile(arg(0))
  let toks = ""
  let i = 0
  let srcLen = len(src)
  while i < srcLen {
    let ch = src[i]
    if ch == " " || ch == "\n" || ch == "\r" || ch == "\t" {
      i += 1
    } else {
      i += 1
    }
  }
  kp("src length: " + srcLen)
  emit "ok"
}
