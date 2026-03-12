// Caesar cipher - encrypt and decrypt messages
// Shifts each letter by a given number of positions

func encryptChar(ch, shift) {
    let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let lower = "abcdefghijklmnopqrstuvwxyz"

    // Check uppercase
    let i = 0
    while i < 26 {
        if ch == upper[i] {
            let newIdx = (i + shift) % 26
            emit upper[newIdx]
        }
        i = i + 1
    }

    // Check lowercase
    i = 0
    while i < 26 {
        if ch == lower[i] {
            let newIdx = (i + shift) % 26
            emit lower[newIdx]
        }
        i = i + 1
    }

    // Non-letter characters pass through
    emit ch
}

func encrypt(text, shift) {
    let sb = sbNew()
    let i = 0
    while i < len(text) {
        sb = sbAppend(sb, encryptChar(text[i], shift))
        i = i + 1
    }
    emit sbToString(sb)
}

func decrypt(text, shift) {
    emit encrypt(text, 26 - shift)
}

just run {
    kp("Caesar Cipher")
    kp("=============")

    let message = "Hello World from Krypton"
    let shift = 3

    kp("Original:  " + message)
    let encrypted = encrypt(message, shift)
    kp("Encrypted: " + encrypted + " (shift=" + shift + ")")
    let decrypted = decrypt(encrypted, shift)
    kp("Decrypted: " + decrypted)
    kp("")

    // Try all shifts
    kp("All possible decryptions of '" + encrypted + "':")
    let s = 0
    while s < 26 {
        kp("  shift " + s + ": " + decrypt(encrypted, s))
        s = s + 1
    }
    emit "ok"
}
