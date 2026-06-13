// stdlib/time.k -- Python `time` module surface on Krypton's existing
// GetTickCount / Sleep IAT bindings.
//
// Names use the `*k` suffix convention.
//
// FE lowering:
//   time.time()           -> timek()
//   time.monotonic()      -> timeMonotonick()
//   time.sleep(seconds)   -> timeSleepk(seconds)
//   time.perf_counter()   -> timePerfCounterk()
//   time.process_time()   -> timeProcessTimek()
//   time.time_ns()        -> timeNsk()

module time

import "head:windows"


// time.time() -- seconds since the epoch.
// Today: returns milliseconds-since-boot / 1000 since we don't have a
// proper time(2) builtin wired.  Real epoch seconds need
// GetSystemTimeAsFileTime + the FILETIME->epoch conversion; ships in
// a follow-up.
func timek() {
    let ms = GetTickCount64()
    emit toInt(ms) / 1000
}

// time.monotonic() -- monotonic seconds.  Same source today.
func timeMonotonick() {
    emit timek()
}

// time.perf_counter() -- high-resolution monotonic, seconds.  Today
// same source as monotonic; a real impl uses QueryPerformanceCounter.
func timePerfCounterk() {
    emit timek()
}

// time.process_time() -- CPU time consumed by this process, seconds.
// Today: defer to monotonic until GetProcessTimes is wired.
func timeProcessTimek() {
    emit timek()
}

// time.time_ns() -- nanoseconds.  Today returns milliseconds * 10^6.
func timeNsk() {
    let ms = GetTickCount64()
    emit toInt(ms) * 1000000
}

// time.sleep(seconds) -- block for `seconds` seconds.  Sleep is wired
// in milliseconds; multiply.
func timeSleepk(seconds) {
    let ms = toInt(seconds) * 1000
    Sleep(toStr(ms))
    emit ""
}

// time.sleep_ms(ms) -- Krypton-native millisecond variant.  Python
// doesn't have this but it's strictly more useful than `Sleep(1)`
// being the smallest interval.
func timeSleepMsk(ms) {
    Sleep(toStr(toInt(ms)))
    emit ""
}
