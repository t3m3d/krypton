just run { 
  let src = readFile(arg(0));
  let tokens = "";
  let i = 0;
  let len_src = len(src);
  let tokCount = 0;
  kp("Source length: " + len_src);
  emit "ok"
}
