// vault_crypto_macos.k -- native macOS crypto for Krypton Vault.
//
// Uses Security.framework + CommonCrypto through native Mach-O imports:
// - SecRandomCopyBytes for salt/IV
// - HMAC-SHA256 derives 64 bytes using native CCHmac
// - first 32 bytes encrypt with AES-256-CBC/PKCS7
// - second 32 bytes authenticate with HMAC-SHA256 over ciphertext

module vault_crypto_macos

import "head:commoncrypto"
import "head:security"
import "k:bitwise"

func _hexNib(c) {
    if c >= "0" && c <= "9" {
        emit charCode(c) - charCode("0")
    } else if c >= "a" && c <= "f" {
        emit charCode(c) - charCode("a") + 10
    } else if c >= "A" && c <= "F" {
        emit charCode(c) - charCode("A") + 10
    } else {
        emit 0
    }
}

func _hexByte(b) {
    let chars = "0123456789abcdef"
    emit chars[(b / 16) % 16] + chars[b % 16]
}

func _bytesToHex(buf, n) {
    let out = sbNew()
    let i = 0
    while i < n {
        out = sbAppend(out, _hexByte(toInt(bufGetByte(buf, i))))
        i += 1
    }
    emit sbToString(out)
}

func _hexToBuf(hex) {
    let n = len(hex) / 2
    let buf = bufNew(n)
    let i = 0
    while i < n {
        let b = _hexNib(hex[i * 2]) * 16 + _hexNib(hex[i * 2 + 1])
        bufSetByte(buf, i, b)
        i += 1
    }
    emit buf
}

func _copyBuf(src, n) {
    let out = bufNew(n)
    let i = 0
    while i < n {
        bufSetByte(out, i, bufGetByte(src, i))
        i += 1
    }
    emit out
}

func _joinBuf(a, an, b, bn) {
    let out = bufNew(an + bn)
    let i = 0
    while i < an {
        bufSetByte(out, i, bufGetByte(a, i))
        i += 1
    }
    let j = 0
    while j < bn {
        bufSetByte(out, an + j, bufGetByte(b, j))
        j += 1
    }
    emit out
}

func _bufToString(buf, n) {
    let out = sbNew()
    let i = 0
    while i < n {
        out = sbAppend(out, fromCharCode(bufGetByte(buf, i)))
        i += 1
    }
    emit sbToString(out)
}

func _stringToBuf(s) {
    let buf = bufNew(len(s))
    let i = 0
    while i < len(s) {
        bufSetByte(buf, i, charCode(s[i]))
        i += 1
    }
    emit buf
}

func _randHex(nBytes) {
    let buf = bufNew(nBytes)
    let st = SecRandomCopyBytes(0, nBytes, buf)
    if st != 0 { emit "" }
    emit _bytesToHex(buf, nBytes)
}

func vaultDeriveKeys(master, saltHex) {
    let salt = _hexToBuf(saltHex)
    let masterBuf = _stringToBuf(master)
    let msg1 = bufNew(20)
    let i = 0
    while i < 16 {
        bufSetByte(msg1, i, bufGetByte(salt, i))
        i += 1
    }
    bufSetByte(msg1, 16, 0)
    bufSetByte(msg1, 17, 0)
    bufSetByte(msg1, 18, 0)
    bufSetByte(msg1, 19, 1)
    let b1 = bufNew(32)
    CCHmac(2, masterBuf, len(master), msg1, 20, b1)

    let msg2 = bufNew(20)
    i = 0
    while i < 16 {
        bufSetByte(msg2, i, bufGetByte(salt, i))
        i += 1
    }
    bufSetByte(msg2, 16, 0)
    bufSetByte(msg2, 17, 0)
    bufSetByte(msg2, 18, 0)
    bufSetByte(msg2, 19, 2)
    let b2 = bufNew(32)
    CCHmac(2, masterBuf, len(master), msg2, 20, b2)
    emit _bytesToHex(b1, 32) + _bytesToHex(b2, 32)
}

func _lineVal(blob, key) {
    let needle = key + "="
    let n = lineCount(blob)
    let i = 0
    while i < n {
        let line = getLine(blob, i)
        if startsWith(line, needle) { emit substring(line, len(needle), len(line)) }
        i += 1
    }
    emit ""
}

func _sliceKey(keysHex, which) {
    if which == "enc" {
        emit _hexToBuf(substring(keysHex, 0, 64))
    } else {
        emit _hexToBuf(substring(keysHex, 64, 128))
    }
}

func _hmacHex(macKey, dataBuf, dataLen) {
    let out = bufNew(32)
    CCHmac(2, macKey, 32, dataBuf, dataLen, out)
    emit _bytesToHex(out, 32)
}

func _hmacHexWithKeyLen(keyBuf, keyLen, dataBuf, dataLen) {
    let out = bufNew(32)
    CCHmac(2, keyBuf, keyLen, dataBuf, dataLen, out)
    emit _bytesToHex(out, 32)
}

func _constantEq(a, b) {
    if len(a) != len(b) { emit 0 }
    let diff = 0
    let i = 0
    while i < len(a) {
        if a[i] != b[i] { diff = 1 }
        i += 1
    }
    if diff == 0 {
        emit 1
    } else {
        emit 0
    }
}

func vaultSeal(master, plain) {
    if len(master) < 12 { emit "" }
    let salt = _randHex(16)
    let ivHex = _randHex(16)
    if salt == "" || ivHex == "" { emit "" }
    let keys = vaultDeriveProbeBlock(master, salt, 1) + vaultDeriveProbeBlock(master, salt, 2)
    if len(keys) < 128 { emit "" }

    let encKey = _sliceKey(keys, "enc")
    let macKey = _sliceKey(keys, "mac")
    let iv = _hexToBuf(ivHex)
    let cref = bufNew(8)
    let create = CCCryptorCreate(0, 0, 1, encKey, 32, iv, cref)
    if create != 0 { emit "" }
    let cryptor = bufGetQwordAt(cref, 0)
    let out = bufNew(len(plain) + 16)
    let moved = bufNew(8)
    let st = CCCryptorUpdate(cryptor, plain, len(plain), out, len(plain) + 16, moved)
    if st != 0 { CCCryptorRelease(cryptor)  emit "" }
    let n1 = toInt(bufGetQwordAt(moved, 0))
    let finalOut = bufNew(16)
    let finalMoved = bufNew(8)
    let finalSt = CCCryptorFinal(cryptor, finalOut, 16, finalMoved)
    CCCryptorRelease(cryptor)
    if finalSt != 0 { emit "" }
    let n2 = toInt(bufGetQwordAt(finalMoved, 0))
    let cipherBuf = _joinBuf(out, n1, finalOut, n2)
    let cipherLen = n1 + n2
    let cipherHex = _bytesToHex(cipherBuf, cipherLen)
    let tag = _hmacHex(macKey, cipherBuf, cipherLen)
    emit "KV2\n" +
        "kdf=hmac-sha256-2block\n" +
        "iterations=1\n" +
        "cipher=aes-256-cbc-hmac-sha256\n" +
        "salt=" + salt + "\n" +
        "iv=" + ivHex + "\n" +
        "tag=" + tag + "\n" +
        "ciphertext=" + cipherHex + "\n"
}

func vaultOpen(master, sealed) {
    if !startsWith(sealed, "KV2\n") { emit "" }
    let salt = _lineVal(sealed, "salt")
    let ivHex = _lineVal(sealed, "iv")
    let tag = _lineVal(sealed, "tag")
    let cipherHex = _lineVal(sealed, "ciphertext")
    if salt == "" || ivHex == "" || tag == "" || cipherHex == "" { emit "" }
    let keys = vaultDeriveProbeBlock(master, salt, 1) + vaultDeriveProbeBlock(master, salt, 2)
    if len(keys) < 128 { emit "" }
    let encKey = _sliceKey(keys, "enc")
    let macKey = _sliceKey(keys, "mac")
    let cipher = _hexToBuf(cipherHex)
    let cipherLen = len(cipherHex) / 2
    let actual = _hmacHex(macKey, cipher, cipherLen)
    if _constantEq(actual, tag) == 0 { emit "" }

    let iv = _hexToBuf(ivHex)
    let cref = bufNew(8)
    let create = CCCryptorCreate(1, 0, 1, encKey, 32, iv, cref)
    if create != 0 { emit "" }
    let cryptor = bufGetQwordAt(cref, 0)
    let out = bufNew(cipherLen + 16)
    let moved = bufNew(8)
    let st = CCCryptorUpdate(cryptor, cipher, cipherLen, out, cipherLen + 16, moved)
    if st != 0 { CCCryptorRelease(cryptor)  emit "" }
    let n1 = toInt(bufGetQwordAt(moved, 0))
    let finalOut = bufNew(16)
    let finalMoved = bufNew(8)
    let finalSt = CCCryptorFinal(cryptor, finalOut, 16, finalMoved)
    CCCryptorRelease(cryptor)
    if finalSt != 0 { emit "" }
    let n2 = toInt(bufGetQwordAt(finalMoved, 0))
    emit _bufToString(out, n1) + _bufToString(finalOut, n2)
}

func localVaultPath() {
    emit environ("HOME") + "/.config/krypton-vault/vault.kv"
}

func sealLocalVault(master, plain) {
    let sealed = vaultSeal(master, plain)
    if sealed == "" { emit "0" }
    exec("mkdir -p \"" + environ("HOME") + "/.config/krypton-vault\"")
    writeFile(localVaultPath(), sealed)
    emit "1"
}

func openLocalVault(master) {
    emit vaultOpen(master, readFile(localVaultPath()))
}

func vaultDeriveKeys2(master, saltHex) {
    emit vaultDeriveProbeBlock(master, saltHex, 1) + vaultDeriveProbeBlock(master, saltHex, 2)
}

func vaultDeriveProbe(master, saltHex) {
    let salt = _hexToBuf(saltHex)
    let masterBuf = _stringToBuf(master)
    emit _hmacHexWithKeyLen(masterBuf, len(master), salt, 16)
}

func vaultDeriveProbeBlock(master, saltHex, blockIndex) {
    let salt = _hexToBuf(saltHex)
    let masterBuf = _stringToBuf(master)
    let msg = bufNew(20)
    let i = 0
    while i < 16 {
        bufSetByte(msg, i, bufGetByte(salt, i))
        i += 1
    }
    bufSetByte(msg, 16, 0)
    bufSetByte(msg, 17, 0)
    bufSetByte(msg, 18, 0)
    bufSetByte(msg, 19, blockIndex)
    emit _hmacHexWithKeyLen(masterBuf, len(master), msg, 20)
}
