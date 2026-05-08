// stdlib/proc.k — bidirectional process pipes for Krypton.
//
// Spawn a child process with stdin/stdout connected to pipes, write
// to its stdin, read from its stdout. Built for LSP / JSON-RPC
// clients (kls.exe, kbackend.exe) where the parent has to drive a
// long-running child over a stream.
//
//   import "stdlib/proc.k"
//
//   let p = procSpawn("kls.exe", "")
//   procWrite(p, "Content-Length: 26\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1}")
//   let reply = procRead(p, 4096)
//   procClose(p)
//
// Reads block until data is available or EOF / pipe-broken.
// procReadAvail returns immediately with whatever's buffered ("" on
// nothing). procAlive lets a caller poll without reading.
//
// Backend: cfunc { } body compiled into runtime/ckrypton_proc.dll
// the same way stdlib/gui.k feeds runtime/ckrypton_gui.dll. End-user
// `kcc -o foo.exe foo.k` IAT-links the krProc* exports — no per-build
// gcc.

module proc


jxt {
    func krProcSpawn(exe, args)         -> char_ptr
    func krProcWrite(handle, data)      -> char_ptr
    func krProcRead(handle, maxBytes)   -> char_ptr
    func krProcReadAvail(handle, maxBytes) -> char_ptr
    func krProcAlive(handle)            -> char_ptr
    func krProcClose(handle)            -> char_ptr
    func krProcSleep(ms)                -> char_ptr
}


cfunc {
#if defined(_WIN32)

    #ifndef _WIN32_WINNT
    #define _WIN32_WINNT 0x0601
    #endif
    #include <windows.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>

    // Per-spawned-process state. Krypton sees this as an opaque
    // pointer encoded as "0x...".
    typedef struct kr_proc_state {
        HANDLE hChildStdoutRead;   // we read from this
        HANDLE hChildStdinWrite;   // we write to this
        HANDLE hProcess;           // child process handle
        DWORD  pid;
    } kr_proc_state;

    // Krypton string ownership: every kr_* return value must be a
    // freshly-malloc'd, NUL-terminated string. The runtime never
    // frees these (they live in the GC arena), so each call mallocs
    // a fresh copy.
    static char* kr_proc_dup(const char* s) {
        size_t n = strlen(s);
        char* p = (char*)malloc(n + 1);
        if (!p) return (char*)"";
        memcpy(p, s, n + 1);
        return p;
    }

    // Spawn `exe` with `args` (single string, appended after exe
    // name). Returns "0x..." pointer to kr_proc_state, or "0" on
    // failure.
    __declspec(dllexport) char* krProcSpawn(char* exe, char* args) {
        // Inheritable security attrs so the pipe handles cross the
        // CreateProcess boundary into the child.
        SECURITY_ATTRIBUTES sa;
        sa.nLength = sizeof(sa);
        sa.bInheritHandle = TRUE;
        sa.lpSecurityDescriptor = NULL;

        HANDLE hOutRead = NULL, hOutWrite = NULL;
        HANDLE hInRead = NULL, hInWrite = NULL;

        // 1 MB pipe buffer — Windows default is ~4 KB, which is
        // smaller than a typical didOpen body and stalls our
        // WriteFile until the child reads. UI freezes during that
        // wait.
        DWORD pipeSize = 1024 * 1024;
        if (!CreatePipe(&hOutRead, &hOutWrite, &sa, pipeSize)) return (char*)"0";
        // Read end (parent side) must NOT be inherited.
        SetHandleInformation(hOutRead, HANDLE_FLAG_INHERIT, 0);

        if (!CreatePipe(&hInRead, &hInWrite, &sa, pipeSize)) {
            CloseHandle(hOutRead); CloseHandle(hOutWrite);
            return (char*)"0";
        }
        SetHandleInformation(hInWrite, HANDLE_FLAG_INHERIT, 0);

        // Build full command line: exe + " " + args (if any).
        // CreateProcessA wants a single mutable string.
        size_t exelen  = exe  ? strlen(exe)  : 0;
        size_t arglen  = args ? strlen(args) : 0;
        char* cmd = (char*)malloc(exelen + 1 + arglen + 1);
        if (!cmd) {
            CloseHandle(hOutRead); CloseHandle(hOutWrite);
            CloseHandle(hInRead);  CloseHandle(hInWrite);
            return (char*)"0";
        }
        memcpy(cmd, exe ? exe : "", exelen);
        cmd[exelen] = ' ';
        memcpy(cmd + exelen + 1, args ? args : "", arglen);
        cmd[exelen + 1 + arglen] = '\0';

        STARTUPINFOA si;
        memset(&si, 0, sizeof(si));
        si.cb         = sizeof(si);
        si.dwFlags    = STARTF_USESTDHANDLES;
        si.hStdInput  = hInRead;
        si.hStdOutput = hOutWrite;
        si.hStdError  = hOutWrite;   // merge stderr into stdout

        PROCESS_INFORMATION pi;
        memset(&pi, 0, sizeof(pi));

        BOOL ok = CreateProcessA(
            NULL, cmd,
            NULL, NULL,
            TRUE,                        // inherit handles
            CREATE_NO_WINDOW,            // no console flash
            NULL, NULL,
            &si, &pi);
        free(cmd);

        // Child has its own copies; close the parent's handles to
        // those ends so EOF propagates correctly.
        CloseHandle(hInRead);
        CloseHandle(hOutWrite);

        if (!ok) {
            CloseHandle(hOutRead);
            CloseHandle(hInWrite);
            return (char*)"0";
        }

        kr_proc_state* st = (kr_proc_state*)malloc(sizeof(*st));
        if (!st) {
            TerminateProcess(pi.hProcess, 1);
            CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
            CloseHandle(hOutRead); CloseHandle(hInWrite);
            return (char*)"0";
        }
        st->hChildStdoutRead = hOutRead;
        st->hChildStdinWrite = hInWrite;
        st->hProcess         = pi.hProcess;
        st->pid              = pi.dwProcessId;
        CloseHandle(pi.hThread);   // unused

        char buf[32];
        snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)(ULONG_PTR)st);
        return kr_proc_dup(buf);
    }

    static kr_proc_state* kr_proc_resolve(char* h) {
        if (!h || !(h[0] == '0' && h[1] == 'x')) return NULL;
        kr_proc_state* st = NULL;
        sscanf(h, "0x%llx", (unsigned long long*)&st);
        return st;
    }

    // Write data to the child's stdin. Returns "1" on success, "0"
    // on failure or broken pipe.
    __declspec(dllexport) char* krProcWrite(char* h, char* data) {
        kr_proc_state* st = kr_proc_resolve(h);
        if (!st || !data) return (char*)"0";
        DWORD len = (DWORD)strlen(data);
        DWORD wrote = 0;
        BOOL ok = WriteFile(st->hChildStdinWrite, data, len, &wrote, NULL);
        if (!ok || wrote != len) return (char*)"0";
        // No FlushFileBuffers — Windows pipes deliver data
        // immediately, and the flush BLOCKS until the reader
        // (kls.exe etc.) has consumed everything. That stalled the
        // IDE's UI thread on every didOpen/didChange.
        return (char*)"1";
    }

    // Blocking read from child stdout. Reads up to maxBytes bytes
    // (or whatever's available — pipes return short reads). Empty
    // string on EOF / broken pipe / error.
    __declspec(dllexport) char* krProcRead(char* h, char* maxBytesStr) {
        kr_proc_state* st = kr_proc_resolve(h);
        if (!st) return (char*)"";
        int maxBytes = atoi(maxBytesStr ? maxBytesStr : "4096");
        if (maxBytes <= 0) maxBytes = 4096;
        if (maxBytes > 1048576) maxBytes = 1048576;  // 1 MB cap

        char* buf = (char*)malloc(maxBytes + 1);
        if (!buf) return (char*)"";
        DWORD got = 0;
        BOOL ok = ReadFile(st->hChildStdoutRead, buf, maxBytes, &got, NULL);
        if (!ok || got == 0) { free(buf); return (char*)""; }
        buf[got] = '\0';
        char* dup = kr_proc_dup(buf);
        free(buf);
        return dup;
    }

    // Non-blocking read: returns whatever's buffered, "" if nothing.
    // PeekNamedPipe checks without consuming, then ReadFile drains.
    __declspec(dllexport) char* krProcReadAvail(char* h, char* maxBytesStr) {
        kr_proc_state* st = kr_proc_resolve(h);
        if (!st) return (char*)"";
        int maxBytes = atoi(maxBytesStr ? maxBytesStr : "4096");
        if (maxBytes <= 0) maxBytes = 4096;
        if (maxBytes > 1048576) maxBytes = 1048576;

        DWORD avail = 0;
        BOOL peek = PeekNamedPipe(st->hChildStdoutRead, NULL, 0, NULL, &avail, NULL);
        if (!peek || avail == 0) return (char*)"";

        DWORD want = (DWORD)maxBytes;
        if (avail < want) want = avail;

        char* buf = (char*)malloc(want + 1);
        if (!buf) return (char*)"";
        DWORD got = 0;
        BOOL ok = ReadFile(st->hChildStdoutRead, buf, want, &got, NULL);
        if (!ok || got == 0) { free(buf); return (char*)""; }
        buf[got] = '\0';
        char* dup = kr_proc_dup(buf);
        free(buf);
        return dup;
    }

    // Sleep for `ms` milliseconds. Wrapper because direct
    // `import "process.krh"; Sleep(n)` from Krypton doesn't marshal
    // ints to Win32 yet — Win64 ABI gets a string pointer in RCX.
    __declspec(dllexport) char* krProcSleep(char* msStr) {
        int ms = atoi(msStr ? msStr : "0");
        if (ms < 0) ms = 0;
        Sleep((DWORD)ms);
        return (char*)"1";
    }

    // "1" if the child is still running, "0" if it has exited or
    // failed. Doesn't reap — call procClose to free resources.
    __declspec(dllexport) char* krProcAlive(char* h) {
        kr_proc_state* st = kr_proc_resolve(h);
        if (!st) return (char*)"0";
        DWORD code = 0;
        if (!GetExitCodeProcess(st->hProcess, &code)) return (char*)"0";
        return code == STILL_ACTIVE ? (char*)"1" : (char*)"0";
    }

    // Close all handles. After this, the handle is invalid and
    // should not be reused. Always returns "1" so callers can chain.
    __declspec(dllexport) char* krProcClose(char* h) {
        kr_proc_state* st = kr_proc_resolve(h);
        if (!st) return (char*)"1";
        // Attempt graceful close: shut stdin so the child sees EOF,
        // then wait briefly, then terminate if still alive.
        if (st->hChildStdinWrite) CloseHandle(st->hChildStdinWrite);
        WaitForSingleObject(st->hProcess, 500);
        DWORD code = 0;
        if (GetExitCodeProcess(st->hProcess, &code) && code == STILL_ACTIVE) {
            TerminateProcess(st->hProcess, 1);
        }
        if (st->hChildStdoutRead) CloseHandle(st->hChildStdoutRead);
        CloseHandle(st->hProcess);
        free(st);
        return (char*)"1";
    }

#else
    // Non-Windows: no-op stubs so the module at least links. POSIX
    // implementation (pipe + fork + exec) goes here when needed.
    __declspec(dllexport) char* krProcSpawn(char* e, char* a)         { (void)e;(void)a; return (char*)"0"; }
    __declspec(dllexport) char* krProcWrite(char* h, char* d)         { (void)h;(void)d; return (char*)"0"; }
    __declspec(dllexport) char* krProcRead(char* h, char* m)          { (void)h;(void)m; return (char*)""; }
    __declspec(dllexport) char* krProcReadAvail(char* h, char* m)     { (void)h;(void)m; return (char*)""; }
    __declspec(dllexport) char* krProcAlive(char* h)                  { (void)h; return (char*)"0"; }
    __declspec(dllexport) char* krProcClose(char* h)                  { (void)h; return (char*)"1"; }
    __declspec(dllexport) char* krProcSleep(char* m)                  { (void)m; return (char*)"1"; }

#endif
}


// ── Krypton public API ─────────────────────────────────────────

func procSpawn(exe, args)         { emit krProcSpawn(exe, args) }
func procWrite(handle, data)      { emit krProcWrite(handle, data) }
func procRead(handle, maxBytes)   { emit krProcRead(handle, maxBytes + "") }
func procReadAvail(handle, maxBytes) { emit krProcReadAvail(handle, maxBytes + "") }
func procAlive(handle)            { emit krProcAlive(handle) }
func procClose(handle)            { emit krProcClose(handle) }
func procSleep(ms)                { emit krProcSleep(ms + "") }
