// Caesar-cipher brute-force: try all 25 shifts on a ciphertext.
// Useful when you don't know the original key.

func shift(s, k) {
    let out = ""
    let i = 0
    let n = len(s)
    while i < n {
        let ch = s[i]
        let code = charCode(ch)
        if code >= 65 && code <= 90 {
            // uppercase A-Z
            let r = ((code - 65) + k) % 26
            out = out + fromCharCode("" + (r + 65))
        } else if code >= 97 && code <= 122 {
            // lowercase a-z
            let r = ((code - 97) + k) % 26
            out = out + fromCharCode("" + (r + 97))
        } else {
            out = out + ch
        }
        i += 1
    }
    emit out
}

just run {
    let cipher = "Khoor, Nubswrq!"
    kp("Brute-forcing: " + cipher)
    kp("")
    let k = 1
    while k <= 25 {
        kp("shift " + k + ": " + shift(cipher, k))
        k += 1
    }
}
