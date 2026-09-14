# Objective-K K-Owned Runtime On macOS

Status: experimental object core. macOS arm64 only verified. Windows is not
available for testing and is not part of this stage.

This module owns classes, objects, fields, text storage, and message lookup in
Krypton. It does not import Cocoa, UIKit, Foundation, or `libobjc`. Existing
Objective-K GUI apps still use their Apple adapters; this core does not replace
those adapters yet.

## Use From Krypton Or KryptScript

```krypton
import "k:objk_runtime_macos"

func value(runtime, self) {
    emit okKGet(runtime, self, "value")
}

just run {
    let runtime = okKRuntime(65536)
    let counter = okKClass(runtime, "Counter", 0)
    okKMethod(runtime, counter, "value", 0, funcptr(value))
    doKRegister(runtime, counter)

    let object = okKNew(runtime, counter)
    doKSet(runtime, object, "value", 42)
    kp(okKSend(runtime, object, "value"))
    doKRelease(runtime, object)
}
```

Methods receive `(runtime, self)` followed by zero, one, or two user arguments.
Declare the user-argument count when registering a method. Send messages with
`okKSend`, `okKSend1`, or `okKSend2`. Missing methods and wrong argument counts
exit with an `Objective-K:` diagnostic instead of making an unchecked call.

## Classes And Inheritance

Create a root class with parent `0`. A child takes its registered parent's
handle. Register methods before `doKRegister`; registration seals the class.
Instances require a registered class. Lookup walks from instance class to its
parents, so child methods override parent methods.

`okKSuper(runtime, object, definingClass, name)` starts lookup at the parent of
the class defining the current method, not the parent of the instance's dynamic
class. The defining class must belong to the object's ancestry. This first
version supports zero-user-argument `super` messages.

`okKResponds` checks for a method; `okKIsA` checks class ancestry.

## Fields And Lifetime

- Fields contain integers in `[-1000000000, 1000000000]` or arena handles.
- Copy strings into the arena with `okKText`; read them with `okKTextValue`.
- `okKHas` distinguishes an absent field from a field holding `0`.
- Each new object starts with reference count `1`.
- `okKRetain` increments it; `doKRelease` decrements it.
- Final release tombstones the object. Later field access, messages, retain, or
  another release are rejected.
- `doKSet` stores borrowed handles or integers without changing references.
- `doKOwn` stores an object handle, retaining it and releasing the previous
  owned value. Assign `0` to clear it. Final owner release releases owned fields.
- `doKWeak` stores an object handle without retaining it. Reading the field
  returns `0` once the target starts releasing; `okKHas` still returns `1`.
- Owned and weak slots keep their reference policy. Update them with `doKOwn`
  or `doKWeak`, not `doKSet`; conversion between these policies is rejected.
- Assigning a borrowed slot with either reference API establishes its policy.

```krypton
doKOwn(runtime, parent, "child", child)
doKWeak(runtime, child, "parent", parent)
doKRelease(runtime, child)
doKRelease(runtime, parent)
```

The parent owns the child while the child has a weak back-reference. Releasing
the parent's last reference releases both objects. Strong reference cycles are
not collected; break them explicitly with `doKOwn(..., 0)` or use weak links.
Reference counts remain caller-balanced: a getter returns a borrowed handle;
retain it before taking an independent reference.

## Cleanup Hooks

Register `doKCleanup(runtime, klass, funcptr(cleanup))` before sealing the class.
The callback takes `(runtime, self)` and its return value is ignored. Each class
may register one callback; null pointers, duplicate hooks, and sealed-class
changes are rejected. The function signature remains caller-checked.

Final release invokes the most-derived class hook first, then each parent hook,
then releases owned fields and tombstones the object. Hooks are automatic; do
not manually invoke parent cleanup. Classes without hooks are skipped.
Owned field release order is unspecified and currently walks the field list.

During cleanup, getters and read-only messages still work, owned children remain
alive, and the object's reference count is `0`. Retain, release, field mutation,
and assigning the releasing object to another owned/weak field are rejected.
Weak references already read as `0`. A cleanup message that mutates the object
is rejected by the same write guard. Cleanup errors use the runtime's fail-fast
diagnostics; no exception unwinding is provided.

All records and copied text live in one fixed-capacity arena. Handles are
checked integer IDs, not raw pointers or offsets, and are never reused. Keep the
runtime buffer reachable for every handle's lifetime. Arena identity is implicit
in the runtime argument; do not mix handles from different runtimes.

Final release returns object records, field records, and their private field
names to a first-fit allocator, after cleanup and owned-child release finish.
Replacement allocations get fresh IDs: stale strong handles are rejected and
expired weak handles remain zero even after storage reuse. `okKRefCount` returns
zero for a previously issued ID whose record has been freed; it cannot recover
the old record kind after reuse, so pass only object IDs to this API.

Classes, methods, their names, and caller-created `okKText` remain allocated.
Free blocks are not split or coalesced yet; variable-size churn can fragment
the arena. ID exhaustion fails rather than wrapping (about 62 million issued
IDs per arena). Lookup scans allocation blocks; this is not a dispatch-speed
optimization. Arena identity remains implicit, and the runtime is single-threaded.
The host GC reclaims the whole arena once its buffer becomes unreachable.
This layout avoids relying on macOS GC object-graph traversal.

## Compiler Support

Imported `let`/`const` initializers are now prepended to executable `__main__` in
the import traversal's dependency-first order. Imported functions can read and
update those initialized globals. Local and parameter shadowing remains local.

This repairs initializers for modules discovered by the existing import loader;
it does not add arbitrary-depth import graph resolution, module namespaces, or
library-load initialization for entryless DLL/library IR. Native imported
floating-point type propagation is a separate compiler task.

The macOS arm64 emitter now handles `callPtr(fp, ...)` for zero through eight
native Krypton arguments. It preserves boxed values and returns, validates the
IR argument-count range, and traps on null pointers. This is a native Krypton
function-pointer call, not a general foreign ABI bridge. Correct target function
signature remains the caller's responsibility.

## Tests

```sh
KRYPTON_ROOT="$PWD" ./bootstrap/kcc_driver_macos_aarch64 -r \
  scripts/check_objk_runtime_macos.ks
```

Checks module initialization, indirect calls, class ancestry, method overrides,
`super`, fields, copied text, owned/weak references, cleanup ordering, GC
survival, and failure paths. Lifetime checks include same-child replacement,
shared ownership, cycle breaking, release chains, and resurrection rejection.
Also inspects the test binary to reject Apple object-runtime dependencies.
Pass `--gui` to also compile and run the native window/button callback smoke
test. It requires a macOS desktop session; the default checks do not launch GUI
apps.

## macOS GUI Demo

`examples/objk/k_owned_counter_macos.ks` connects a K-owned counter model to
existing native OKUI controls. Its model, fields, and message dispatch use the
new runtime; window/control adapters still use Apple frameworks.
Its K state owns the model. The app menu's `Quit` (`Command-Q`) releases that
state, which releases the model and invokes its cleanup callback.

```sh
KRYPTON_ROOT="$PWD" ./bootstrap/kcc_driver_macos_aarch64 -r \
  scripts/build-objk-app.ks examples/objk/k_owned_counter_macos.ks objk_counter
open dist/objk_counter.app
```

The built executable accepts `--smoke` to send three native button actions,
verify both K model and label reach `1`, then exit. This checks native callbacks
without requiring Accessibility click automation, and verifies state release
destroys the owned model with exactly one cleanup callback.
Window handles remain native pointers; converting them to text corrupts their
identity and previously caused `setMinSize:` to crash.

## Next Stages

1. Extend reclamation with block splitting/coalescing and explicit text lifetime.
2. Add typed method metadata and compiler-checked dispatch.
3. Add generated Apple bridge adapters for K-owned objects.
4. Extend Choc widget state and events around the K-owned core.

No automatic reference counting, protocols, thread safety, dispatch cache,
compiler class-syntax integration, or Cocoa replacement is claimed by this
prototype. No Windows runtime binaries are changed.
