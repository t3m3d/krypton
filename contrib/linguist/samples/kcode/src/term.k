// term.k — terminal driver: raw mode, key reading, window size, ANSI helpers.
//
// Lives in cfunc { } because Krypton's stdlib has line-buffered input only
// (`input()` reads to newline). A TUI editor needs single-keystroke reads,
// so we drop into termios + read(2).
//
// Public API:
//   tInit()            -> "1" on success; sets raw mode, alt screen, hides cursor
//   tRestore()         -> "1"; undo everything tInit did
//   tSize()            -> "rows,cols"
//   tReadKey()         -> token: "a", "ENTER", "TAB", "BACKSPACE", "ESC",
//                                 "UP", "DOWN", "LEFT", "RIGHT", "HOME", "END",
//                                 "PAGEUP", "PAGEDOWN", "DEL",
//                                 "C-a".."C-z", "M-x" (alt+letter), or "?" for unknown
//   tWrite(s)          -> raw bytes to stdout, no newline
//   tFlush()           -> flush stdout
//
// All other ANSI sequences are emitted by the renderer via tWrite().

module term

jxt {
    func krTermInit() -> char_ptr
    func krTermRestore() -> char_ptr
    func krTermSize() -> char_ptr
    func krTermReadKey() -> char_ptr
    func krTermWrite(s) -> char_ptr
    func krTermFlush() -> char_ptr
}

cfunc {
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>
    #include <termios.h>
    #include <sys/ioctl.h>
    #include <signal.h>

    static struct termios g_orig_termios;
    static int g_have_orig = 0;
    static int g_in_raw = 0;

    static void kr_term_restore_internal(void) {
        if (g_have_orig && g_in_raw) {
            // Set the flag FIRST so signal handlers / atexit don't double-fire.
            g_in_raw = 0;
            // Disable mouse reporting, show cursor, leave alt screen.
            const char *seq = "\x1b[?1006l\x1b[?1000l\x1b[?25h\x1b[?1049l";
            write(STDOUT_FILENO, seq, strlen(seq));
            // TCSANOW — TCSAFLUSH was hanging in some pty configurations.
            tcsetattr(STDIN_FILENO, TCSANOW, &g_orig_termios);
        }
    }

    static void kr_term_signal(int sig) {
        kr_term_restore_internal();
        // Re-raise with default handler so the parent sees the right exit code.
        signal(sig, SIG_DFL);
        raise(sig);
    }

    char* krTermInit(void) {
        if (g_in_raw) return (char*)"1";
        if (tcgetattr(STDIN_FILENO, &g_orig_termios) == -1) return (char*)"0";
        g_have_orig = 1;

        struct termios raw = g_orig_termios;
        // cfmakeraw clears: BRKINT, ICRNL, INPCK, ISTRIP, IXON, OPOST,
        //                   ECHO, ECHONL, ICANON, ISIG, IEXTEN
        // and sets CS8.
        cfmakeraw(&raw);
        raw.c_cc[VMIN]  = 1;   // block for at least one byte
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == -1) return (char*)"0";
        g_in_raw = 1;

        // Enter alt screen, hide cursor, clear, enable SGR mouse reporting
        // (?1000h = button events, ?1006h = SGR extended encoding for
        //  coordinates >=224 and clean parsing).
        const char *seq = "\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H\x1b[?1000h\x1b[?1006h";
        write(STDOUT_FILENO, seq, strlen(seq));

        atexit(kr_term_restore_internal);
        signal(SIGINT,  kr_term_signal);
        signal(SIGTERM, kr_term_signal);
        signal(SIGHUP,  kr_term_signal);
        // Window resize: leave SIGWINCH at default; we poll size via tSize().
        return (char*)"1";
    }

    char* krTermRestore(void) {
        kr_term_restore_internal();
        return (char*)"1";
    }

    char* krTermSize(void) {
        struct winsize ws;
        int rows = 24, cols = 80;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0 && ws.ws_col > 0) {
            rows = ws.ws_row;
            cols = ws.ws_col;
        }
        char *out = (char*)malloc(32);
        if (!out) return (char*)"24,80";
        snprintf(out, 32, "%d,%d", rows, cols);
        return out;
    }

    // Read a single byte, blocking. Returns -1 on EOF / fatal error.
    static int kr_read_byte_blocking(void) {
        unsigned char c;
        ssize_t n = read(STDIN_FILENO, &c, 1);
        if (n == 1) return (int)c;
        if (n == 0) return -1;
        // Interrupted by signal — retry once.
        if (n < 0) {
            n = read(STDIN_FILENO, &c, 1);
            if (n == 1) return (int)c;
        }
        return -1;
    }

    // Read a byte with a short timeout (ms). Returns -1 if no byte available.
    static int kr_read_byte_timeout(int ms) {
        struct termios cur, tmp;
        tcgetattr(STDIN_FILENO, &cur);
        tmp = cur;
        tmp.c_cc[VMIN]  = 0;
        tmp.c_cc[VTIME] = (ms + 99) / 100;   // tenths of a second, min 1
        if (tmp.c_cc[VTIME] < 1) tmp.c_cc[VTIME] = 1;
        tcsetattr(STDIN_FILENO, TCSANOW, &tmp);
        unsigned char c;
        ssize_t n = read(STDIN_FILENO, &c, 1);
        tcsetattr(STDIN_FILENO, TCSANOW, &cur);
        if (n == 1) return (int)c;
        return -1;
    }

    // Fill `out` with a normalized key token. `out` must be at least 16 bytes.
    static void kr_format_key(int b, char *out) {
        if (b < 0)         { strcpy(out, "EOF");       return; }
        if (b == 13)       { strcpy(out, "ENTER");     return; }
        if (b == 10)       { strcpy(out, "ENTER");     return; }
        if (b == 9)        { strcpy(out, "TAB");       return; }
        if (b == 127)      { strcpy(out, "BACKSPACE"); return; }
        if (b == 8)        { strcpy(out, "BACKSPACE"); return; }
        if (b >= 1 && b <= 26) {
            // Map Ctrl-A..Ctrl-Z to "C-a".."C-z". Skip TAB / ENTER / BACKSPACE
            // which were handled above.
            out[0] = 'C';
            out[1] = '-';
            out[2] = (char)('a' + b - 1);
            out[3] = 0;
            return;
        }
        if (b >= 32 && b < 127) {
            out[0] = (char)b;
            out[1] = 0;
            return;
        }
        // Fall through: byte 28..31, or high bytes (UTF-8 leads handled by caller)
        snprintf(out, 16, "?%d", b);
    }

    char* krTermReadKey(void) {
        int b = kr_read_byte_blocking();
        char *out = (char*)malloc(32);
        if (!out) return (char*)"EOF";

        if (b == 27) {
            // ESC — could be lone Escape, ALT-<key>, or CSI/SS3 sequence.
            int b2 = kr_read_byte_timeout(50);
            if (b2 < 0) { strcpy(out, "ESC"); return out; }

            if (b2 == '[') {
                int b3 = kr_read_byte_timeout(50);
                if (b3 < 0) { strcpy(out, "ESC"); return out; }
                if (b3 == 'A') { strcpy(out, "UP");    return out; }
                if (b3 == 'B') { strcpy(out, "DOWN");  return out; }
                if (b3 == 'C') { strcpy(out, "RIGHT"); return out; }
                if (b3 == 'D') { strcpy(out, "LEFT");  return out; }
                if (b3 == 'H') { strcpy(out, "HOME");  return out; }
                if (b3 == 'F') { strcpy(out, "END");   return out; }
                if (b3 == 'Z') { strcpy(out, "S-TAB"); return out; }
                if (b3 == '<') {
                    // SGR mouse: ESC [ < btn ; x ; y (M|m).
                    // M = press, m = release. We surface presses + wheel only.
                    char num[64]; int ni = 0;
                    int term;
                    for (;;) {
                        int bx = kr_read_byte_timeout(50);
                        if (bx < 0) { strcpy(out, "ESC"); return out; }
                        if ((bx >= '0' && bx <= '9') || bx == ';') {
                            if (ni < 63) num[ni++] = (char)bx;
                            continue;
                        }
                        term = bx;
                        break;
                    }
                    num[ni] = 0;
                    int btn = 0, mx = 0, my = 0;
                    sscanf(num, "%d;%d;%d", &btn, &mx, &my);
                    // x,y are 1-based — convert to 0-based.
                    if (mx > 0) mx -= 1;
                    if (my > 0) my -= 1;
                    if (term == 'M') {
                        // Wheel: btn 64 = up, 65 = down (modifiers in high bits).
                        int low = btn & 0x43;
                        if (low == 0x40) { strcpy(out, "WHEEL-UP");   return out; }
                        if (low == 0x41) { strcpy(out, "WHEEL-DOWN"); return out; }
                        // Plain click: btn 0 = left, 1 = middle, 2 = right.
                        const char *bs = "L";
                        int bb = btn & 0x03;
                        if (bb == 1) bs = "M";
                        else if (bb == 2) bs = "R";
                        snprintf(out, 32, "MOUSE\t%d\t%d\t%s", my, mx, bs);
                        return out;
                    }
                    // Release ('m') — ignore for v0.1.
                    strcpy(out, "MOUSE-UP");
                    return out;
                }
                if (b3 >= '0' && b3 <= '9') {
                    // CSI <digits> <final>. Read digits then the terminator.
                    char num[16]; int ni = 0;
                    num[ni++] = (char)b3;
                    int term;
                    for (;;) {
                        int bx = kr_read_byte_timeout(50);
                        if (bx < 0) { strcpy(out, "ESC"); return out; }
                        if (bx == ';' && ni < 15) { num[ni++] = (char)bx; continue; }
                        if (bx >= '0' && bx <= '9' && ni < 15) { num[ni++] = (char)bx; continue; }
                        term = bx;
                        break;
                    }
                    num[ni] = 0;
                    if (term == '~') {
                        int n = atoi(num);
                        if (n == 1 || n == 7)  { strcpy(out, "HOME");     return out; }
                        if (n == 4 || n == 8)  { strcpy(out, "END");      return out; }
                        if (n == 3)            { strcpy(out, "DEL");      return out; }
                        if (n == 5)            { strcpy(out, "PAGEUP");   return out; }
                        if (n == 6)            { strcpy(out, "PAGEDOWN"); return out; }
                        if (n == 2)            { strcpy(out, "INS");      return out; }
                        snprintf(out, 32, "CSI~%d", n);
                        return out;
                    }
                    // CSI <digits> <letter> — e.g. modifier sequences.
                    snprintf(out, 32, "CSI%s%c", num, (char)term);
                    return out;
                }
                snprintf(out, 32, "CSI%c", (char)b3);
                return out;
            }
            if (b2 == 'O') {
                // SS3 sequences (some terminals send these for F-keys / arrows in app mode).
                int b3 = kr_read_byte_timeout(50);
                if (b3 < 0) { strcpy(out, "ESC"); return out; }
                if (b3 == 'A') { strcpy(out, "UP");    return out; }
                if (b3 == 'B') { strcpy(out, "DOWN");  return out; }
                if (b3 == 'C') { strcpy(out, "RIGHT"); return out; }
                if (b3 == 'D') { strcpy(out, "LEFT");  return out; }
                if (b3 == 'H') { strcpy(out, "HOME");  return out; }
                if (b3 == 'F') { strcpy(out, "END");   return out; }
                if (b3 >= 'P' && b3 <= 'S') {
                    snprintf(out, 32, "F%d", b3 - 'P' + 1);
                    return out;
                }
                snprintf(out, 32, "SS3%c", (char)b3);
                return out;
            }

            // ALT + <printable>
            if (b2 >= 32 && b2 < 127) {
                if (b2 >= 'A' && b2 <= 'Z') b2 = b2 - 'A' + 'a';  // normalize
                snprintf(out, 32, "M-%c", (char)b2);
                return out;
            }
            // ALT + control char
            snprintf(out, 32, "M-?%d", b2);
            return out;
        }

        // Multi-byte UTF-8: reassemble so the buffer stores the full codepoint.
        if ((b & 0x80) != 0) {
            int more = 0;
            if      ((b & 0xE0) == 0xC0) more = 1;
            else if ((b & 0xF0) == 0xE0) more = 2;
            else if ((b & 0xF8) == 0xF0) more = 3;
            if (more > 0 && more <= 3) {
                unsigned char buf[5];
                buf[0] = (unsigned char)b;
                int ok = 1;
                for (int i = 1; i <= more; i++) {
                    int bx = kr_read_byte_timeout(50);
                    if (bx < 0) { ok = 0; break; }
                    buf[i] = (unsigned char)bx;
                }
                if (ok) {
                    buf[more + 1] = 0;
                    strcpy(out, (char*)buf);
                    return out;
                }
            }
            // Fall through if malformed.
        }

        kr_format_key(b, out);
        return out;
    }

    char* krTermWrite(char *s) {
        if (s) {
            size_t n = strlen(s);
            if (n > 0) write(STDOUT_FILENO, s, n);
        }
        return (char*)"1";
    }

    char* krTermFlush(void) {
        fflush(stdout);
        return (char*)"1";
    }
}

func tInit()      { emit krTermInit() }
func tRestore()   { emit krTermRestore() }
func tSize()      { emit krTermSize() }
func tReadKey()   { emit krTermReadKey() }
func tWrite(s)    { emit krTermWrite(s) }
func tFlush()     { emit krTermFlush() }

// ── Entry: lives here so editor.k stays under the kcc 1.8.0 size threshold

func _dirOf(p) {
    let n = len(p)
    let i = n - 1
    while i >= 0 {
        if p[i] == "/" {
            if i == 0 { emit "/" }
            emit substring(p, 0, i)
        }
        i -= 1
    }
    emit "."
}

func kcodeMain() {
    let path = ""
    if argCount() >= 1 { path = arg(0) }
    let openFile = ""
    let treeRoot = "."
    if path != "" {
        // shellRun returns system(3)'s exit status; test -d returns 0 when path is a dir.
        if shellRun("test -d \"" + path + "\"") == "0" {
            treeRoot = path
        } else {
            openFile = path
            treeRoot = _dirOf(path)
        }
    }
    if tInit() != "1" {
        printErr("kcode: cannot enter raw mode (is stdin a tty?)")
        exit(1)
    }
    let e = edNew(openFile, treeRoot)
    e = _setMsg(e, "kcode — Ctrl-Q quit · Ctrl-S save · Ctrl-B build · Tab tree", "")
    e = edRun(e)
    tRestore()
    kp("")
    emit "1"
}
