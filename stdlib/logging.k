// stdlib/logging.k — leveled console logging in PURE KRYPTON. No C.
//
// Colored, leveled log lines to stdout. Levels are integers so callers can
// filter: DEBUG=0 INFO=1 WARN=2 ERROR=3. State (the active level) is threaded
// explicitly — module globals don't persist across the import boundary — so
// pass the current level to the *If helpers, or just call the always-on ones.
//
//   import "k:logging"
//   just run {
//       logInfo("server up")
//       logWarn("disk 80%")
//       logError("connection refused")
//       let lvl = LEVEL_INFO()          // hold this yourself
//       logIf(lvl, LEVEL_DEBUG(), "noisy")   // suppressed (debug < info)
//   }
//
// Self-contained: ANSI color codes are inlined (nested module imports don't
// link transitively on this backend), so you only `import "k:logging"`.

module logging

func _sgr(code) { emit fromCharCode(27) + "[" + code + "m" }

func LEVEL_DEBUG() { emit 0 }
func LEVEL_INFO()  { emit 1 }
func LEVEL_WARN()  { emit 2 }
func LEVEL_ERROR() { emit 3 }

func _tagPlain(level) {
    if level == 0 { emit "DEBUG" }
    if level == 1 { emit "INFO " }
    if level == 2 { emit "WARN " }
    if level == 3 { emit "ERROR" }
    emit "LOG  "
}

func _color(code, s) { emit _sgr(code) + s + _sgr("0") }

func _tagColor(level) {
    if level == 0 { emit _color("90", "DEBUG") }   // gray
    if level == 1 { emit _color("36", "INFO ") }   // cyan
    if level == 2 { emit _color("33", "WARN ") }   // yellow
    if level == 3 { emit _color("91", "ERROR") }   // bright red
    emit "LOG  "
}

// logFormat(level, msg) -> a colored log line string (no trailing newline).
func logFormat(level, msg) { emit "[" + _tagColor(level) + "] " + msg }

// logFormatPlain(level, msg) -> same, without color codes (for files).
func logFormatPlain(level, msg) { emit "[" + _tagPlain(level) + "] " + msg }

// Always-on emitters (print immediately).
func logDebug(msg) { kp(logFormat(0, msg)) }
func logInfo(msg)  { kp(logFormat(1, msg)) }
func logWarn(msg)  { kp(logFormat(2, msg)) }
func logError(msg) { kp(logFormat(3, msg)) }

// logIf(activeLevel, msgLevel, msg): print only if msgLevel >= activeLevel.
// Lets the caller hold one threshold and gate everything through it.
func logIf(activeLevel, msgLevel, msg) {
    if msgLevel >= activeLevel { kp(logFormat(msgLevel, msg)) }
    emit ""
}
