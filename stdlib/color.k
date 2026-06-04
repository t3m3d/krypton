// stdlib/color.k — Color conversion + manipulation in pure Krypton.
//
// Round-trip between #RRGGBB hex and (r,g,b) integer triples; HSL ↔
// RGB conversion; lighten/darken/mix utilities. RGB channels are 0..255.
// HSL hue is 0..360, sat/light 0..100. Companion to k:gui and the site
// theme work.
//
// Krypton's comma-separated "list" string convention is used for triples
// (e.g. "255,128,64" for RGB or "210,80,55" for HSL).
//
// API:
//   colorHexToRgb(hex)         -> "r,g,b" (e.g. "#7722ff" -> "119,34,255")
//   colorRgbToHex(r, g, b)     -> "#rrggbb"
//   colorRgbToHsl(r, g, b)     -> "h,s,l"
//   colorHslToRgb(h, s, l)     -> "r,g,b"
//   colorLighten(hex, percent) -> #hex (clamps at white)
//   colorDarken(hex, percent)  -> #hex (clamps at black)
//   colorMix(hexA, hexB, t)    -> #hex (t in 0..100; 0=A, 100=B)

module color

func _hexNibble(n) {
    let d = "0123456789abcdef"
    emit d[n]
}

func _hexValue(c) {
    let v = charCode(c)
    if v >= 48 && v <= 57  { emit v - 48 }
    if v >= 97 && v <= 102 { emit v - 87 }
    if v >= 65 && v <= 70  { emit v - 55 }
    emit 0
}

func _hexPair(s, off) {
    emit _hexValue(s[off]) * 16 + _hexValue(s[off + 1])
}

func _clamp(v, lo, hi) {
    if v < lo { emit lo }
    if v > hi { emit hi }
    emit v
}

func colorHexToRgb(hex) {
    let s = hex
    if s[0] == "#" { s = substring(s, 1, len(s)) }
    if len(s) != 6 { emit "0,0,0" }
    let r = _hexPair(s, 0)
    let g = _hexPair(s, 2)
    let b = _hexPair(s, 4)
    emit r + "," + g + "," + b
}

func colorRgbToHex(r, g, b) {
    let rc = _clamp(r, 0, 255)
    let gc = _clamp(g, 0, 255)
    let bc = _clamp(b, 0, 255)
    emit "#" + _hexNibble(rc / 16) + _hexNibble(rc % 16) +
              _hexNibble(gc / 16) + _hexNibble(gc % 16) +
              _hexNibble(bc / 16) + _hexNibble(bc % 16)
}

// HSL→RGB: standard formula at /100 precision. h in 0..360, s in 0..100,
// l in 0..100. Output rgb in 0..255.
func colorHslToRgb(h, s, l) {
    if s == 0 {
        let v = (l * 255) / 100
        emit v + "," + v + "," + v
    }
    let hh = h
    while hh < 0 { hh = hh + 360 }
    while hh >= 360 { hh = hh - 360 }
    // c = (1 - |2L-1|) * S, scaled by 10000 to avoid floats.
    let m2 = (2 * l) - 100
    if m2 < 0 { m2 = 0 - m2 }
    let c = ((100 - m2) * s)            // /10000 later
    let seg = hh / 60                   // 0..5
    let segRem = hh - seg * 60          // 0..59
    // x = c * (1 - |((h/60) mod 2) - 1|), but in integer terms:
    let mod2 = seg % 2
    let xnum = segRem
    if mod2 == 1 { xnum = 60 - segRem }
    let x = (c * xnum) / 60             // still /10000
    let m = l * 100 - c / 2             // l% * 100 - c/2 in /10000 units
    let rp = 0  let gp = 0  let bp = 0
    if seg == 0 { rp = c  gp = x }
    else if seg == 1 { rp = x  gp = c }
    else if seg == 2 { gp = c  bp = x }
    else if seg == 3 { gp = x  bp = c }
    else if seg == 4 { rp = x  bp = c }
    else             { rp = c  bp = x }
    let r = ((rp + m) * 255) / 10000
    let g = ((gp + m) * 255) / 10000
    let b = ((bp + m) * 255) / 10000
    emit _clamp(r, 0, 255) + "," + _clamp(g, 0, 255) + "," + _clamp(b, 0, 255)
}

// RGB→HSL: returns h,s,l where h∈[0,360), s∈[0,100], l∈[0,100].
func colorRgbToHsl(r, g, b) {
    let maxV = r
    if g > maxV { maxV = g }
    if b > maxV { maxV = b }
    let minV = r
    if g < minV { minV = g }
    if b < minV { minV = b }
    let l = ((maxV + minV) * 100) / 510    // (max+min)/2/255 * 100
    if maxV == minV { emit "0,0," + l }
    let d = maxV - minV
    let denom = maxV + minV
    if l > 50 { denom = 510 - maxV - minV }
    let s = (d * 100) / denom
    let h = 0
    if maxV == r { h = ((g - b) * 60) / d  if g < b { h = h + 360 } }
    else if maxV == g { h = ((b - r) * 60) / d + 120 }
    else              { h = ((r - g) * 60) / d + 240 }
    while h < 0 { h = h + 360 }
    while h >= 360 { h = h - 360 }
    emit h + "," + s + "," + l
}

// Pull r/g/b from a "r,g,b" string. (split is broken on Linux per
// LINUX_RELEASE_TODO — manual parse.)
func _pickRgb(s, idx) {
    let rest = s
    let i = 0
    while i < idx {
        let c = indexOf(rest, ",")
        if c < 0 { emit 0 }
        rest = substring(rest, c + 1, len(rest))
        i += 1
    }
    let c = indexOf(rest, ",")
    if c >= 0 { rest = substring(rest, 0, c) }
    emit toInt(rest)
}

func colorLighten(hex, percent) {
    let rgb = colorHexToRgb(hex)
    let r = _pickRgb(rgb, 0)
    let g = _pickRgb(rgb, 1)
    let b = _pickRgb(rgb, 2)
    let dr = ((255 - r) * percent) / 100
    let dg = ((255 - g) * percent) / 100
    let db = ((255 - b) * percent) / 100
    emit colorRgbToHex(r + dr, g + dg, b + db)
}

func colorDarken(hex, percent) {
    let rgb = colorHexToRgb(hex)
    let r = _pickRgb(rgb, 0)
    let g = _pickRgb(rgb, 1)
    let b = _pickRgb(rgb, 2)
    emit colorRgbToHex(r - (r * percent) / 100,
                       g - (g * percent) / 100,
                       b - (b * percent) / 100)
}

func colorMix(hexA, hexB, t) {
    let a = colorHexToRgb(hexA)
    let b = colorHexToRgb(hexB)
    let ar = _pickRgb(a, 0)  let ag = _pickRgb(a, 1)  let ab = _pickRgb(a, 2)
    let br = _pickRgb(b, 0)  let bg = _pickRgb(b, 1)  let bb = _pickRgb(b, 2)
    emit colorRgbToHex(ar + ((br - ar) * t) / 100,
                       ag + ((bg - ag) * t) / 100,
                       ab + ((bb - ab) * t) / 100)
}
