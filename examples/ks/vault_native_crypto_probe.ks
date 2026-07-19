#!/usr/bin/env kr
// vault_native_crypto_probe.ks -- native macOS crypto call probe.

import "head:security"
import "head:commoncrypto"

func hexByte(b) {
    let chars = "0123456789abcdef"
    emit chars[(b / 16) % 16] + chars[b % 16]
}

func bytesToHex(buf, n) {
    let out = sbNew()
    let i = 0
    while i < n {
        out = sbAppend(out, hexByte(toInt(bufGetByte(buf, i))))
        i += 1
    }
    emit sbToString(out)
}

just run {
    let rnd = bufNew(16)
    let rst = SecRandomCopyBytes(0, 16, rnd)
    kp("random status=" + rst + " hex=" + bytesToHex(rnd, 16))

    let derived = bufNew(64)
    let di = 0
    while di < 64 {
        bufSetByte(derived, di, (di * 3 + 7) % 256)
        di += 1
    }
    kp("key=" + bytesToHex(derived, 8))

    let mac = bufNew(32)
    CCHmac(2, derived, 32, "hello", 5, mac)
    kp("hmac=" + bytesToHex(mac, 32))

    let cref = bufNew(8)
    let create = CCCryptorCreate(0, 0, 1, derived, 32, rnd, cref)
    kp("create status=" + create + " ref=" + bufGetQwordAt(cref, 0))
    let cryptor = bufGetQwordAt(cref, 0)
    let moved = bufNew(8)
    let out = bufNew(32)
    let cst = CCCryptorUpdate(cryptor, "hello", 5, out, 32, moved)
    kp("update status=" + cst + " moved=" + bufGetQwordAt(moved, 0) + " cipher=" + bytesToHex(out, toInt(bufGetQwordAt(moved, 0))))
    let finalMoved = bufNew(8)
    let finalOut = bufNew(32)
    let fst = CCCryptorFinal(cryptor, finalOut, 32, finalMoved)
    kp("final status=" + fst + " moved=" + bufGetQwordAt(finalMoved, 0) + " final=" + bytesToHex(finalOut, toInt(bufGetQwordAt(finalMoved, 0))))
    CCCryptorRelease(cryptor)
}
