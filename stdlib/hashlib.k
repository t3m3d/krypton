// stdlib/hashlib.k -- Python `hashlib` module surface on top of the
// existing stdlib/crypto.k (which wraps bcrypt.dll).
//
// Names use the `*k` suffix convention (matches builtins.k +
// string.k + list.k + dict.k + sys.k + os.k + math.k + jsonk.k +
// time.k + randomk.k + itertools.k + functools.k).
//
// FE lowering:
//   hashlib.sha256(s).hexdigest()    -> sha256Hexk(s)
//   hashlib.sha256(s).digest()       -> sha256Bytesk(s)
//   hashlib.md5(s).hexdigest()       -> md5Hexk(s)       (stub today)
//   hashlib.sha1(s).hexdigest()      -> sha1Hexk(s)      (stub today)
//   hashlib.sha512(s).hexdigest()    -> sha512Hexk(s)    (stub today)
//   hashlib.new(name, data)          -> newHashk(name, data)
//   hashlib.pbkdf2_hmac(...)         -> pbkdf2Hmack(...)
//
// Python's hashlib is class-based (hashlib.sha256() returns an
// updateable hash object).  Until classes ship, we expose the
// finalized-hash equivalents directly -- pass the data in one go,
// get the digest back.  The streaming Hash class lands when Tier B
// structural types ship.

module hashlib

import "k:crypto"


// SHA-256 -- hex string of the 32-byte digest.
func sha256Hexk(s) {
    emit sha256Hex(s)
}

// SHA-256 -- raw 32-byte buf.
func sha256Bytesk(s) {
    emit sha256Bytes(s)
}

// HMAC-SHA-256 -- key + message -> hex string.
func hmacSha256Hexk(key, msg) {
    emit hmacSha256Hex(key, msg)
}

// MD5 -- not exposed by bcrypt.dll's high-level API today.  Stub for
// the FE lowering to resolve; real impl needs either BCRYPT_MD5_ALGORITHM
// wired through BCryptCreateHash (streaming path) or a Krypton-side
// MD5 polyfill (~100 lines).  Most callers want SHA-256 anyway.
func md5Hexk(s) {
    printErr("hashlib.md5: not yet wired.  Use sha256 for non-legacy hashing; md5 will land via BCryptCreateHash streaming path.")
    exit("1")
}

// SHA-1 -- same situation as MD5.  Legacy hash, mostly unwanted.
func sha1Hexk(s) {
    printErr("hashlib.sha1: not yet wired.  Use sha256 (collision-resistant) for any new code.")
    exit("1")
}

// SHA-512 -- bcrypt.dll exposes BCRYPT_SHA512_ALGORITHM via
// BCryptOpenAlgorithmProvider but stdlib/crypto.k only wraps sha256
// today.  Stub.
func sha512Hexk(s) {
    printErr("hashlib.sha512: not yet wired.  stdlib/crypto.k currently exposes only SHA-256.")
    exit("1")
}

// hashlib.new(name, data) -- dispatch by algorithm name.  Accepts the
// canonical Python names.
func newHashk(name, data) {
    if name == "sha256" || name == "SHA256" { emit sha256Hexk(data) }
    if name == "sha1"   || name == "SHA1"   { emit sha1Hexk(data) }
    if name == "md5"    || name == "MD5"    { emit md5Hexk(data) }
    if name == "sha512" || name == "SHA512" { emit sha512Hexk(data) }
    printErr("hashlib.new: unsupported algorithm \"" + name + "\"")
    exit("1")
}

// PBKDF2-HMAC-SHA256 -- key-derivation, very common for password
// hashing.  bcrypt.dll has BCryptDeriveKeyPBKDF2 but stdlib/crypto.k
// doesn't wrap it yet.  Stub.
func pbkdf2Hmack(hashName, password, salt, iterations, dklen) {
    printErr("hashlib.pbkdf2_hmac: not yet wired.  BCryptDeriveKeyPBKDF2 needs a wrapper in stdlib/crypto.k.")
    exit("1")
}


// hashlib.algorithms_guaranteed -- the set of algorithms always
// available.  Python's full set; we report what we actually have.
func algorithmsGuaranteedk() {
    emit "sha256"
}

// hashlib.algorithms_available -- whatever the backend supports.
// Today same as guaranteed; will expand as the bcrypt wrapper fills in.
func algorithmsAvailablek() {
    emit "sha256"
}
