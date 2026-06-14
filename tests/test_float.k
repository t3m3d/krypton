// A1 floating point — boxed-f64 arithmetic + comparisons (macOS arm64).
//
// Representation: a float is a pointer to an 8-byte f64 box (literals via runtime
// M/scale materialization; results via an 8-byte GC alloc). Float builtins know
// their operands are floats statically, so no runtime type tag — and they
// auto-promote int operands (value < 1<<32 → scvtf), e.g. fadd(5, 2.5).
//
// Printing (fformat) lands in F2; until then values are validated via feq/flt/fgt.
// macOS-only: the fp builtins have macho codegen; the ELF/PE backends don't
// implement them yet. build.sh skips this off macOS.
just run {
    if feq(fadd(1.5, 2.25), 3.75) == 0 { kp("[FAIL] fadd"); exit("1") }
    if feq(fsub(5.0, 1.25), 3.75) == 0 { kp("[FAIL] fsub"); exit("1") }
    if feq(fmul(2.5, 4.0), 10.0)  == 0 { kp("[FAIL] fmul"); exit("1") }
    if feq(fdiv(9.0, 2.0), 4.5)   == 0 { kp("[FAIL] fdiv"); exit("1") }
    if flt(1.5, 2.25)             == 0 { kp("[FAIL] flt"); exit("1") }
    if fgt(2.25, 1.5)             == 0 { kp("[FAIL] fgt"); exit("1") }
    if feq(ffloor(3.7), 3.0)      == 0 { kp("[FAIL] ffloor"); exit("1") }
    if feq(fceil(3.2), 4.0)       == 0 { kp("[FAIL] fceil"); exit("1") }
    if feq(fround(3.5), 4.0)      == 0 { kp("[FAIL] fround"); exit("1") }
    if feq(fadd(5, 2.5), 7.5)     == 0 { kp("[FAIL] int-promote"); exit("1") }
    kp("[PASS] float arith + compares (boxed f64)")
}
