// Phase C: field default-value initializers. `let local Type x` runs
// the captured default for each field that has one.

struct Pixel { let r: u8 = 200  let g: u8 = 100  let b: u8 = 50  let a: u8 = 255 }

struct Counts { let n: u32 = 42  let big: u64 = 1234567 }

just run {
    // All fields initialised from their declared defaults.
    let local Pixel pix
    print("pix = (" + pix.r + ", " + pix.g + ", " + pix.b + ", " + pix.a + ")  expect (200, 100, 50, 255)")

    let local Counts c
    print("c.n   = " + c.n   + " (expect 42)")
    print("c.big = " + c.big + " (expect 1234567)")

    // Defaults can still be overridden after.
    c.n = 99
    print("c.n   = " + c.n   + " (expect 99)")
}
