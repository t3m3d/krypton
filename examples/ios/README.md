# Krypton iOS Examples

These apps are pure KryptScript compiled by `kcc`. Objective-K is available
through `k:okui`; SpriteKit visuals are available through `k:visual`.

## Build And Launch

```sh
./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-ios-app.ks \
  examples/ios/hello.ks KryptonHello --launch
```

Use another source and app name for the visual demos:

```sh
./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-ios-app.ks \
  examples/ios/visual_scene.ks KryptonVisual --launch

./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-ios-app.ks \
  examples/ios/visual_touch.ks KryptonTouch --launch
```

The build script finds the newest Xcode installation, creates the `.app` in
`dist-ios`, signs it for the simulator, and optionally installs and launches it.

## Source Imports

Use Objective-K UIKit controls:

```krypton
import "k:okui"
```

Use scenes, shapes, sprites, motion, physics, and touch:

```krypton
import "k:okui"
import "k:visual"
```

No C, Swift, or Objective-C source is required.
