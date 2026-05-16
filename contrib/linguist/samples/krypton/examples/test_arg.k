just run {
  let src = "hello\r\nworld"
  let i = 0
  let srcLen = len(src)
  kp("len=" + srcLen)
  while i < srcLen {
    let ch = src[i]
    i += 1
  }
  kp("done, i=" + i)
  emit "ok"
}