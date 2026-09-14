// visual.k -- human visual scene API backed by SpriteKit.
// Shared API target: scenes, games, animation, simulation, rich visuals.

module visual

import "head:objc"
import "head:spritekit"
import "k:objc"

func visualView(parent, x, y, w, h) {
    let view = msg_frame(msg(cls("SKView"), "alloc"), "initWithFrame:", x, y, w, h)
    msg_1(parent, "addSubview:", view)
    emit view
}

func visualScene(w, h) {
    let scene = msg_d2(cls("SKScene"), "sceneWithSize:", w, h)
    msg_1(scene, "setScaleMode:", 1)
    emit scene
}

func visualSceneClass(name, touchFn) {
    let c = objc_allocateClassPair(cls("SKScene"), name, 0)
    class_addMethod(c, sel("touchesBegan:withEvent:"), touchFn, "v@:@@")
    class_addMethod(c, sel("touchesMoved:withEvent:"), touchFn, "v@:@@")
    objc_registerClassPair(c)
    emit name
}

func visualCustomScene(className, w, h) {
    let raw = msg(cls(className), "alloc")
    let scene = msg_d2(raw, "initWithSize:", w, h)
    msg_1(scene, "setScaleMode:", 1)
    emit scene
}

func visualShow(view, scene) {
    msg_1(view, "presentScene:", scene)
    emit scene
}

func visualBackground(scene, color) {
    msg_1(scene, "setBackgroundColor:", color)
    emit scene
}

func visualCircle(radius, color) {
    let node = msg_d1(cls("SKShapeNode"), "shapeNodeWithCircleOfRadius:", radius)
    msg_1(node, "setFillColor:", color)
    msg_1(node, "setStrokeColor:", color)
    emit node
}

func visualSprite(imageName) {
    emit msg_1(cls("SKSpriteNode"), "spriteNodeWithImageNamed:", nsString(imageName))
}

func visualSize(node, w, h) {
    msg_d2(node, "setSize:", w, h)
    emit node
}

func visualLabel(text, size, color) {
    let node = msg_1(cls("SKLabelNode"), "labelNodeWithFontNamed:", nsString("AvenirNext-Bold"))
    msg_1(node, "setText:", nsString(text))
    msg_d1(node, "setFontSize:", size)
    msg_1(node, "setFontColor:", color)
    emit node
}

func visualPosition(node, x, y) {
    msg_d2(node, "setPosition:", x, y)
    emit node
}

func visualAdd(parent, node) {
    msg_1(parent, "addChild:", node)
    emit node
}

func visualTouch(touches) {
    emit msg(touches, "anyObject")
}

func visualTouchX(touch, scene) {
    emit msgPointX(touch, "locationInNode:", scene)
}

func visualTouchY(touch, scene) {
    emit msgPointY(touch, "locationInNode:", scene)
}

func visualTouchPreviousX(touch, scene) {
    emit msgPointX(touch, "previousLocationInNode:", scene)
}

func visualTouchPreviousY(touch, scene) {
    emit msgPointY(touch, "previousLocationInNode:", scene)
}

func visualPaintTouch(scene, touch, radius, color) {
    let x = visualTouchX(touch, scene)
    let y = visualTouchY(touch, scene)
    let previousX = visualTouchPreviousX(touch, scene)
    let previousY = visualTouchPreviousY(touch, scene)
    let dx = x - previousX
    let dy = y - previousY
    let width = dx
    let height = dy
    if width < 0 { width = 0 - width }
    if height < 0 { height = 0 - height }

    let span = width
    if height > span { span = height }
    let spacing = radius / 2
    if spacing < 1 { spacing = 1 }
    let steps = span / spacing
    if steps < 1 { steps = 1 }

    let i = 0
    while i <= steps {
        let dot = visualCircle(radius, color)
        let dotX = previousX + (dx * i / steps)
        let dotY = previousY + (dy * i / steps)
        visualPosition(dot, dotX, dotY)
        visualAdd(scene, dot)
        i = i + 1
    }
    emit 1
}

func visualPhysicsCircle(node, radius) {
    let body = msg_d1(cls("SKPhysicsBody"), "bodyWithCircleOfRadius:", radius)
    msg_1(node, "setPhysicsBody:", body)
    emit body
}

func visualDynamic(body, enabled) {
    msg_1(body, "setDynamic:", enabled)
    emit body
}

func visualMove(node, dx, dy, seconds) {
    let action = msg_d3(cls("SKAction"), "moveByX:y:duration:", dx, dy, seconds)
    msg_1(node, "runAction:", action)
    emit action
}
