// Windows stdin single-byte read smoke. Pipe input when running:
//   echo Zed | winio_get_smoke.exe

import "k:winio"

just run {
    let ch = winioGet()
    print("get=" + ch)
}