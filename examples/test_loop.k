just run {
  let src = readFile(arg(0))
  let srcLen = len(src)
  kp("len=" + srcLen)
  let i = 0
  while i < 3 {
    kp("i=" + i)
    let ch = src[i]
    kp("ch=" + ch)
    i = i + 1
  }
  kp("looped to i=" + i)
  emit "ok"
}
