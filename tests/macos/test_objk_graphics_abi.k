import "k:objk"

just run {
    let pool = okAutoreleasePool()
    let image = okImage(64)
    if image == 0 { kp("[FAIL] image size ABI"); exit("1") }
    okImageBegin(image)
    okGraphicsSave()

    let path = okRoundedPath(4, 4, 56, 56, 12, 12)
    if path == 0 || msg(path, "isEmpty") != 0 { kp("[FAIL] rounded NSRect ABI"); exit("1") }
    let start = okRGBA(20, 40, 80, 255)
    let finish = okRGBA(180, 90, 220, 128)
    if start == 0 || finish == 0 { kp("[FAIL] RGBA ABI"); exit("1") }
    let gradient = okGradient(start, finish)
    if gradient == 0 { kp("[FAIL] gradient creation"); exit("1") }
    okGradientPath(gradient, path, -90)

    okGraphicsRestore()
    okImageEnd(image)
    let output = "/tmp/objk-graphics-abi.png"
    if okImagePNG(image, output) == 0 { kp("[FAIL] pointer + CGFloat ABI"); exit("1") }
    if trim(exec("test -s " + output + " && echo yes")) != "yes" { kp("[FAIL] PNG output"); exit("1") }
    okDrainPool(pool)
    kp("[PASS] Objective-K graphics ABI")
}
