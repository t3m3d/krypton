# Winsock-on-Windows plan (kryptlink prereq)

**Status:** blocked on x64.k surgery. kryptlink/run.k is structurally
complete and tested via WSL — it'll work the day Windows gets a
ws2_32.dll IAT slot.

**Why blocked:** `k:server_native` uses sockMake / sockBind /
sockListen / sockAccept / sockRecvStr / sockSend / sockClose builtins.
Windows x64.k binds 11 DLLs (kernel32, krypton_rt, advapi32, pdh,
user32, gdi32, comctl32, comdlg32, ole32, uxtheme, dwmapi) — none of
them export socket APIs. On Windows the socket API lives in
`ws2_32.dll`. Dynamic-load via LoadLibraryA + callPtr also fails:
`callPtr` to a raw Win32 function pointer crashes (runtime tries to
extract a closure env that isn't there).

## Scope

Add ws2_32.dll as the 12th IAT DLL. Required Win32 functions:

  WSAStartup    socket    bind         listen
  accept        recv      send         closesocket
  htons         setsockopt              ioctlsocket  (non-blocking)

## Edit sites (mirror what dwmapi did, last DLL added)

  1. `let KRWS2_FUNCS = "WSAStartup,socket,bind,..."`
  2. `let ws2count = countFuncs(KRWS2_FUNCS)` resolver block
  3. resolveSymbol loop (currently at ~line 1631)
  4. iltWs2Offset / iltWs2Size pair (mirror iltDwmOffset)
  5. iatWs2Offset / iatWs2Size pair
  6. dllWs2Name = "ws2_32.dll" + dllWs2Offset
  7. iltWs2Rva, iatWs2Rva, dllWs2Rva
  8. hint blob — append per-function hint+name entries
  9. IMAGE_IMPORT_DESCRIPTOR for ws2_32
 10. ILT + IAT builder loops add ws2_32 stripe
 11. Marshalling table: socket(int,int,int)→SOCKET ; bind(SOCKET, char*, int)→int
     ; listen(SOCKET,int)→int ; accept(SOCKET, char*, int*)→SOCKET ; etc.
 12. Per-call dispatch in compileWin32 routing
 13. `bsHelperBlockSize` recompute if any helper changes (probably none)

## Krypton-level wiring (after IAT lands)

Map existing names to Win32 surfaces so k:server_native works
unchanged on Windows:

  sockMake()        → WSAStartup(0x0202, &wsa) + socket(AF_INET, SOCK_STREAM, 0)
  sockBind(fd,port) → setsockopt SO_REUSEADDR + bind() with sin_family=AF_INET
                       + htons(port) + INADDR_ANY
  sockListen(fd)    → listen(fd, 128)
  sockAccept(fd)    → accept(fd, NULL, NULL)
  sockRecvStr(fd)   → recv loop until \r\n\r\n or buffer full
  sockSend(fd,s,n)  → send(fd, s, n, 0)
  sockClose(fd)     → closesocket(fd) + (deferred WSACleanup)

Cleanest: add as kr_sock* runtime helpers (~250 bytes of asm) so
behavior matches Linux/macOS server_native byte-for-byte.

## Validation

After surgery, smoke-test in this order:
  1. `kcc -o win_sock_smoke.exe` of a 10-line program that just calls
     sockMake() → sockClose(). If the FD round-trips, IAT is wired.
  2. Bind+listen+accept loopback test (no real client yet).
  3. Build kryptlink.exe, hit / from curl, get login form.
  4. POST /login → 302. Cookie back. GET / → admin page.
  5. POST /create → code. GET /r/<code> → 302 + click logged.

## Fallback (today's option)

Until Winsock lands, deploy kryptlink to Hostinger (Linux). The same
kryptlink/run.k compiles on Linux through `k:server_native` natively
since elf.k binds the syscalls directly.
