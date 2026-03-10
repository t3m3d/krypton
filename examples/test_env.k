just run {
  let e = envSet("", "__argOffset", "1")
  let v = envGet(e, "__argOffset")
  kp("argOffset from envSet: " + v)
  let e2 = envSet(e, "x", "42")
  let v2 = envGet(e2, "__argOffset")
  kp("argOffset after extend: " + v2)
  emit "ok"
}
