// ROT13 encoder/decoder
// Special case of Caesar cipher with shift of 13

func rot13char(ch) {
    let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let lower = "abcdefghijklmnopqrstuvwxyz"

    let i = 0
    while i < 26 {
        if ch == upper[i] {
            emit upper[(i + 13) % 26]
        }
        if ch == lower[i] {
            emit lower[(i + 13) % 26]
        }
        i += 1
    }
    emit ch
}

func rot13(text) {
    let sb = sbNew()
    let i = 0
    while i < len(text) {
        sb = sbAppend(sb, rot13char(text[i]))
        i += 1
    }
    emit sbToString(sb)
}

just run {
    kp("ROT13 Encoder/Decoder")
    kp("=====================")

    let messages = "Hello World,The Quick Brown Fox,Krypton Language,ROT13 is symmetric"
    let total = count(messages)
    let i = 0
    while i < total {
        let msg = split(messages, i)
        let encoded = rot13(msg)
        let decoded = rot13(encoded)
        kp("  Original: " + msg)
        kp("  ROT13:    " + encoded)
        kp("  Decoded:  " + decoded)
        kp("")
        i += 1
    }

    // Verify roundtrip
    let test = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    let roundtrip = rot13(rot13(test))
    if roundtrip == test {
        kp("Roundtrip verification: PASSED")
    } else {
        kp("Roundtrip verification: FAILED")
    }
    emit "ok"
}
