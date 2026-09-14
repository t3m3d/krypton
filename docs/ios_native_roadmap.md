# iOS Native Roadmap

Goal: make Krypton, KryptScript, and Objective-K build real iOS apps from
pure Krypton source. No C source, no Swift source, no Objective-C source in user
apps.

This path starts with simulator support, then device support, then App Store
rules. Simulator proves the compiler and UIKit bridge. Device proves signing and
bundle shape. App Store rules decide what a shipped KryptScript runtime may do.

## Ground Rules

- Host builds run on macOS with Xcode tools available.
- iOS target is `arm64` first.
- User-facing UI imports `k:okui`, not `k:objc`, `k:uikit`, or raw selectors.
- Objective-K remains the facade. Platform backend changes below it.
- KryptScript on iOS starts as bundled, self-contained scripts only.
- No downloaded executable code for normal App Store apps. Apple App Review
  guideline 2.5.2 restricts downloading, installing, or executing code that
  changes app features. Educational/source-visible modes can be evaluated later.

## Current Status

Implemented:

- `--target ios-sim-arm64` and `--target ios-device-arm64`
- target-aware `k:okui` and `k:objk` routing
- shared arm64 Mach-O emitter profiles: platform 7 simulator, platform 2 device
- UIKit, Foundation, and Objective-C runtime linking
- first UIKit lifecycle bridge and `examples/ios/hello.ks`
- shared `k:visual` SpriteKit scene API with shapes, sprites, text, motion,
  physics bodies, touch coordinates, and interpolated stroke painting
- animated `examples/ios/visual_scene.ks`
- interactive `examples/ios/visual_touch.ks`
- flat iOS `.app` bundle generation and ad-hoc simulator signing

Verified on macOS:

- simulator and device Mach-O load commands
- UIKit/Foundation/SpriteKit/libobjc dylib commands
- signed simulator bundle shape
- iOS 27 simulator install, launch, UIKit rendering, and SpriteKit animation

Current limitation:

- SpriteKit one-shot actions work. Repeat/sequence action wrappers still need
  an ABI-safe implementation.

## KryptScript And Objective-K

KryptScript (`.ks`) is compiled by `kcc`. It can use Objective-K directly
through normal imports:

```krypton
import "k:okui"
import "k:visual"
```

`k:okui` selects the platform Objective-K UI implementation. On iOS it routes
through Choc to UIKit. `k:visual` adds the SpriteKit-backed scene API. Apps stay
Krypton source: no C, Swift, or Objective-C source is generated or compiled.

Imports are explicit so command-line scripts do not load GUI frameworks unless
they use them.

## Target Stack

```
app.ks / app.k
    |
    v
stdlib/okui.k              app-facing UI words
    |
    v
stdlib/okui_ios.k          iOS route
    |
    v
stdlib/objk_ios.k          Objective-K facade for UIKit
    |
    v
stdlib/choc_ios.k          UIKit backend
    |
    v
stdlib/objc.k              Objective-C runtime calls
    |
    v
headers/objc.krh
headers/uikit.krh
headers/foundation.krh
    |
    v
compiler/macos_arm64/macho_arm64_self.k --target ios-*
```

## Phase 0: Repo Shape

Add files without changing shipped macOS behavior.

Planned files:

- `compiler/ios_arm64/README.md`
- `headers/uikit.krh`
- `headers/foundation_ios.krh` if `headers/cocoa.krh` is too AppKit-shaped
- `stdlib/choc_ios.k`
- `stdlib/objk_ios.k`
- `stdlib/okui_ios.k`
- `examples/ios/hello.ks`
- `examples/ios/okui_counter.ks`
- `scripts/build-ios-app.ks`
- `scripts/check_ios.ks`

Acceptance:

- `./build.sh` still passes on macOS.
- `scripts/check_okui.ks` still passes on macOS.
- New iOS scripts fail cleanly when Xcode tools or signing config are missing.

## Phase 1: Compiler Target Flag

Current platform routing mostly uses host OS. iOS needs target OS because builds
happen on macOS.

Spec:

- Add target input: `--target ios-sim-arm64` and `--target ios-device-arm64`.
- Add env fallback: `KRYPTON_TARGET=ios-sim-arm64`.
- Route `k:okui` to `stdlib/okui_ios.k` when target starts with `ios-`.
- Route backend to iOS profile in `compiler/macos_arm64/macho_arm64_self.k`.
- Keep host macOS route unchanged when no iOS target is set.

Acceptance:

```
KRYPTON_TARGET=ios-sim-arm64 ./compiler/macos_arm64/kcc-arm64 --ir examples/ios/hello.ks
```

Expected: IR emits and imports iOS files, not AppKit files.

## Phase 2: iOS Mach-O Emitter

Reuse macOS arm64 backend with explicit target profiles. Keep one arm64 code
generator and isolate platform-specific Mach-O details behind target checks.

Spec:

- Emit iOS-compatible arm64 Mach-O.
- Emit correct platform load commands for simulator/device.
- Link/import Foundation, UIKit, and libobjc symbols.
- Preserve Krypton runtime builtins from macOS backend where possible.
- Keep ad-hoc signing for simulator if accepted.
- For device, allow external signing through Xcode tools.

Known hard parts:

- iOS code signing is stricter than macOS.
- Simulator and device use different platform load-command values.
- UIKit entry lifecycle differs from AppKit.

Acceptance:

```
KRYPTON_TARGET=ios-sim-arm64 ./kcc --target ios-sim-arm64 examples/ios/hello.ks -o /tmp/hello_ios
file /tmp/hello_ios
```

Expected: Mach-O arm64 iOS/simulator executable, no C compiler step.

## Phase 3: UIKit Objective-K

Build enough UIKit to show a window, label, text field, button, and callback.

Spec:

- `chocIosApp()`
- `chocIosWindow(title)`
- `chocIosLabel(win, text, x, y, w, h)`
- `chocIosButton(win, text, x, y, w, h)`
- `chocIosTextField(win, x, y, w, h)`
- `chocIosSetText(control, text)`
- `chocIosGetText(control)`
- `chocIosOnTap(control, fnPtr)`
- `chocIosRun(app)`

Objective-K wrappers:

- `okApp`
- `okWindow`
- `okLabelR`
- `okButtonR`
- `okFieldR`
- `okSetText`
- `okText`
- `okOn`
- `okRun`

Acceptance:

```
KRYPTON_TARGET=ios-sim-arm64 ./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-ios-app.ks examples/ios/okui_counter.ks KryptonCounter
```

Expected: simulator app opens, button increments label.

## Phase 4: App Bundle Script

`scripts/build-ios-app.ks` owns packaging. It should not compile C. It may call
Apple tools for signing, simulator install, and launch.

Spec:

- Create `.app` directory.
- Copy compiled Mach-O executable into bundle.
- Write `Info.plist`.
- Copy icons/assets when present.
- Sign simulator bundle if needed.
- Sign device bundle when `IOS_TEAM_ID` and provisioning profile are present.
- Optional launch:
  - `--sim install`
  - `--sim launch`

Inputs:

- `IOS_BUNDLE_ID`, default `org.krypton-lang.demo.<name>`
- `IOS_TEAM_ID`, required for device
- `IOS_DEPLOYMENT_TARGET`, default current safe minimum chosen by Xcode
- `IOS_DEVICE_ID` or simulator name

Acceptance:

```
KRYPTON_TARGET=ios-sim-arm64 ./bootstrap/kcc_driver_macos_aarch64 -r scripts/build-ios-app.ks examples/ios/hello.ks KryptonHello --sim launch
```

Expected: app installs and launches in iOS Simulator.

## Phase 5: KryptScript on iOS

Start safe. Bundled KryptScript only. No network-loaded scripts.

Spec:

- Bundle `.ks` resources inside app.
- Add read-only script loader for app resources.
- Add tiny sample: `examples/ios/ks_bundle_demo.ks`.
- Allow scripts to drive OKUI only through approved host functions.
- Keep filesystem writes inside app container.

Non-goal first pass:

- No on-device compiler UI.
- No downloaded script execution.
- No plugin installer.

Acceptance:

- App opens bundled `.ks` resource.
- App displays script output in UIKit text view.
- No external network fetch or executable download.

## Phase 6: Krypton-Lang iOS App

This is the public demo app path.

Scope:

- Offline docs pulled from `krypton-lang` or `web/site/dist`.
- Example browser.
- OKUI demo runner.
- Build status/about screen.
- Optional FTP/web deploy tools later, only if iOS sandbox permits sane workflow.

Acceptance:

- `Krypton` iOS app opens offline docs.
- Runs bundled demos.
- Shows Objective-K UIKit UI.
- Does not violate App Store code-execution rules.

## Release Gates

Simulator alpha:

- `examples/ios/hello.ks` launches in simulator.
- `examples/ios/okui_counter.ks` launches in simulator.
- `scripts/check_ios.ks` passes on a clean Mac with Xcode.

Device beta:

- Device app signs with user Team ID.
- Installs on real iPhone/iPad.
- OKUI counter works.
- No private API warnings.

Public/TestFlight:

- Bundle identifier final.
- Icons present.
- Privacy strings present.
- No network script execution.
- Source-visible educational mode documented if used.

## Open Decisions

- Minimum iOS version.
- Bundle id naming: `org.krypton-lang.Krypton` vs `org.krypton-lang.ios`.
- Whether first app is "Krypton Lab" or "Krypton".
- Whether to support iPad layout in first alpha.
- Whether KryptScript execution is dev-only, educational, or hidden until after
  first TestFlight.

## Work Order

1. Add iOS target routing in compiler.
2. Stub `headers/uikit.krh`.
3. Add iOS profiles to shared arm64 Mach-O emitter.
4. Produce simulator "hello" Mach-O.
5. Add UIKit `choc_ios.k` minimal controls.
6. Add `okui_ios.k` route.
7. Build `examples/ios/okui_counter.ks`.
8. Add `scripts/build-ios-app.ks`.
9. Install/launch in simulator.
10. Add device signing path.
11. Add bundled KryptScript demo.
12. Build Krypton-Lang iOS demo app.

## Collaboration Notes

- macOS agent owns iOS backend and UIKit Objective-K because iOS build host is
  macOS/Xcode.
- Windows agent should avoid changing OKUI public words without updating
  `stdlib/okui_core.k`.
- Shared API contract remains `k:okui`.
- Platform wrappers may be hardcoded. App code should not be.
