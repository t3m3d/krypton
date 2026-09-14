// Arena handles are offsets, never interior pointers: macOS GC scans roots,
// not object graphs. Names/text live inside the same rooted arena.

module objk_runtime_macos

func okKFail(message) {
    kp("Objective-K: " + message)
    exit("1")
}

func okKRuntime(capacity) {
    if capacity < 64 || capacity > 1048576 { okKFail("arena capacity out of range") }
    let runtime = bufNew(capacity)
    bufSetQwordAt(runtime, 0, capacity)
    bufSetQwordAt(runtime, 8, 16)
    emit runtime
}

func okKAllocate(runtime, bytes) {
    let cursor = bufGetQwordAt(runtime, 8)
    let size = ((bytes + 7) / 8) * 8 + 8
    if cursor + size > bufGetQwordAt(runtime, 0) { okKFail("arena full") }
    bufSetQwordAt(runtime, cursor, size)
    bufSetQwordAt(runtime, 8, cursor + size)
    emit cursor + 8
}

func okKRequire(runtime, handle, kind) {
    let used = bufGetQwordAt(runtime, 8)
    if handle < 24 || handle >= used || handle % 8 != 0 { okKFail("invalid handle") }
    let cursor = 16
    while cursor < used {
        if cursor + 8 == handle {
            if bufGetQwordAt(runtime, handle) != kind { okKFail("wrong handle kind") }
            emit handle
        }
        cursor += bufGetQwordAt(runtime, cursor)
    }
    okKFail("invalid handle")
}

// Record layouts: class {kind,parent,name,methods,sealed,cleanup}; method
// {kind,next,name,arity,fn}; object {kind,class,refs,fields,alive}; field
// {kind,next,name,value,policy}; text {kind,length,bytes...}.
// Field policy: 0 borrowed, 1 owned, 2 weak.
func okKText(runtime, text) {
    let n = len(text)
    let handle = okKAllocate(runtime, 16 + n)
    bufSetQwordAt(runtime, handle, 5)
    bufSetQwordAt(runtime, handle + 8, n)
    let i = 0
    while i < n {
        bufSetByte(runtime, handle + 16 + i, charCode(text[i]))
        i += 1
    }
    emit handle
}

func okKTextEquals(runtime, handle, text) {
    okKRequire(runtime, handle, 5)
    let n = bufGetQwordAt(runtime, handle + 8)
    if n != len(text) { emit 0 }
    let i = 0
    while i < n {
        if bufGetByte(runtime, handle + 16 + i) != charCode(text[i]) { emit 0 }
        i += 1
    }
    emit 1
}

func okKTextValue(runtime, handle) {
    okKRequire(runtime, handle, 5)
    let n = bufGetQwordAt(runtime, handle + 8)
    let text = ""
    let i = 0
    while i < n {
        text = text + fromCharCode(bufGetByte(runtime, handle + 16 + i))
        i += 1
    }
    emit text
}

func okKClass(runtime, name, parent) {
    if name == "" { okKFail("empty class name") }
    if parent != 0 {
        okKRequire(runtime, parent, 1)
        if bufGetQwordAt(runtime, parent + 32) != 1 { okKFail("parent class not registered") }
    }
    let storedName = okKText(runtime, name)
    let handle = okKAllocate(runtime, 48)
    bufSetQwordAt(runtime, handle, 1)
    bufSetQwordAt(runtime, handle + 8, parent)
    bufSetQwordAt(runtime, handle + 16, storedName)
    bufSetQwordAt(runtime, handle + 24, 0)
    bufSetQwordAt(runtime, handle + 32, 0)
    bufSetQwordAt(runtime, handle + 40, 0)
    emit handle
}

func okKClassName(runtime, klass) {
    okKRequire(runtime, klass, 1)
    emit okKTextValue(runtime, bufGetQwordAt(runtime, klass + 16))
}

func okKOwnMethod(runtime, klass, name) {
    okKRequire(runtime, klass, 1)
    let method = bufGetQwordAt(runtime, klass + 24)
    while method != 0 {
        if okKTextEquals(runtime, bufGetQwordAt(runtime, method + 16), name) { emit method }
        method = bufGetQwordAt(runtime, method + 8)
    }
    emit 0
}

func okKMethod(runtime, klass, name, arity, fnPtr) {
    okKRequire(runtime, klass, 1)
    if bufGetQwordAt(runtime, klass + 32) != 0 { okKFail("class already registered") }
    if name == "" || fnPtr == 0 { okKFail("invalid method") }
    if arity < 0 || arity > 2 { okKFail("method arity out of range") }
    if okKOwnMethod(runtime, klass, name) != 0 { okKFail("duplicate method") }
    let storedName = okKText(runtime, name)
    let method = okKAllocate(runtime, 40)
    bufSetQwordAt(runtime, method, 2)
    bufSetQwordAt(runtime, method + 8, bufGetQwordAt(runtime, klass + 24))
    bufSetQwordAt(runtime, method + 16, storedName)
    bufSetQwordAt(runtime, method + 24, arity)
    bufSetQwordAt(runtime, method + 32, fnPtr)
    bufSetQwordAt(runtime, klass + 24, method)
    emit method
}

func doKRegister(runtime, klass) {
    okKRequire(runtime, klass, 1)
    bufSetQwordAt(runtime, klass + 32, 1)
    emit klass
}

func doKCleanup(runtime, klass, fnPtr) {
    okKRequire(runtime, klass, 1)
    if bufGetQwordAt(runtime, klass + 32) != 0 { okKFail("class already registered") }
    if fnPtr == 0 { okKFail("invalid cleanup callback") }
    if bufGetQwordAt(runtime, klass + 40) != 0 { okKFail("cleanup already registered") }
    bufSetQwordAt(runtime, klass + 40, fnPtr)
    emit klass
}

func okKNew(runtime, klass) {
    okKRequire(runtime, klass, 1)
    if bufGetQwordAt(runtime, klass + 32) != 1 { okKFail("class not registered") }
    let object = okKAllocate(runtime, 40)
    bufSetQwordAt(runtime, object, 3)
    bufSetQwordAt(runtime, object + 8, klass)
    bufSetQwordAt(runtime, object + 16, 1)
    bufSetQwordAt(runtime, object + 24, 0)
    bufSetQwordAt(runtime, object + 32, 1)
    emit object
}

func okKAlive(runtime, object) {
    okKRequire(runtime, object, 3)
    if bufGetQwordAt(runtime, object + 32) == 0 { okKFail("object released") }
    emit object
}

func okKWritable(runtime, object) {
    okKAlive(runtime, object)
    if bufGetQwordAt(runtime, object + 32) != 1 { okKFail("object releasing") }
    emit object
}

func okKObjectClass(runtime, object) {
    okKAlive(runtime, object)
    emit bufGetQwordAt(runtime, object + 8)
}

func okKIsA(runtime, object, klass) {
    okKRequire(runtime, klass, 1)
    let current = okKObjectClass(runtime, object)
    while current != 0 {
        if current == klass { emit 1 }
        current = bufGetQwordAt(runtime, current + 8)
    }
    emit 0
}

func okKFindMethod(runtime, klass, name) {
    let current = klass
    while current != 0 {
        let method = okKOwnMethod(runtime, current, name)
        if method != 0 { emit method }
        current = bufGetQwordAt(runtime, current + 8)
    }
    emit 0
}

func okKResponds(runtime, object, name) {
    emit okKFindMethod(runtime, okKObjectClass(runtime, object), name) != 0
}

func okKInvoke(runtime, object, klass, name, arity, a, b) {
    okKAlive(runtime, object)
    let method = okKFindMethod(runtime, klass, name)
    if method == 0 { okKFail("unknown method: " + name) }
    if bufGetQwordAt(runtime, method + 24) != arity { okKFail("method argument count: " + name) }
    let fnPtr = bufGetQwordAt(runtime, method + 32)
    if arity == 0 { emit callPtr(fnPtr, runtime, object) }
    if arity == 1 { emit callPtr(fnPtr, runtime, object, a) }
    emit callPtr(fnPtr, runtime, object, a, b)
}

func okKSend(runtime, object, name) {
    emit okKInvoke(runtime, object, okKObjectClass(runtime, object), name, 0, 0, 0)
}
func okKSend1(runtime, object, name, a) {
    emit okKInvoke(runtime, object, okKObjectClass(runtime, object), name, 1, a, 0)
}
func okKSend2(runtime, object, name, a, b) {
    emit okKInvoke(runtime, object, okKObjectClass(runtime, object), name, 2, a, b)
}
func okKSuper(runtime, object, definingClass, name) {
    if okKIsA(runtime, object, definingClass) != 1 { okKFail("super class not in object ancestry") }
    let parent = bufGetQwordAt(runtime, definingClass + 8)
    emit okKInvoke(runtime, object, parent, name, 0, 0, 0)
}

func okKField(runtime, object, name) {
    okKAlive(runtime, object)
    let field = bufGetQwordAt(runtime, object + 24)
    while field != 0 {
        if okKTextEquals(runtime, bufGetQwordAt(runtime, field + 16), name) { emit field }
        field = bufGetQwordAt(runtime, field + 8)
    }
    emit 0
}

func okKWriteField(runtime, object, name, value, policy) {
    okKWritable(runtime, object)
    if policy != 0 && value != 0 { okKWritable(runtime, value) }
    let field = okKField(runtime, object, name)
    let previous = 0
    if field != 0 && bufGetQwordAt(runtime, field + 32) == 1 {
        if policy != 1 { okKFail("owned field needs doKOwn") }
        previous = bufGetQwordAt(runtime, field + 24)
    }
    if field != 0 && bufGetQwordAt(runtime, field + 32) == 2 && policy != 2 {
        okKFail("weak field needs doKWeak")
    }
    if field == 0 {
        let storedName = okKText(runtime, name)
        field = okKAllocate(runtime, 40)
        bufSetQwordAt(runtime, field, 4)
        bufSetQwordAt(runtime, field + 8, bufGetQwordAt(runtime, object + 24))
        bufSetQwordAt(runtime, field + 16, storedName)
        bufSetQwordAt(runtime, object + 24, field)
    }
    // Retain before replacement so assigning the same child cannot destroy it.
    if policy == 1 && value != 0 { okKRetain(runtime, value) }
    bufSetQwordAt(runtime, field + 24, value)
    bufSetQwordAt(runtime, field + 32, policy)
    if previous != 0 { doKRelease(runtime, previous) }
    emit value
}

func doKSet(runtime, object, name, value) {
    // Store integer values/arena handles only, never external heap pointers.
    if value < (0 - 1000000000) || value > 1000000000 { okKFail("field needs integer or arena handle") }
    emit okKWriteField(runtime, object, name, value, 0)
}

func doKOwn(runtime, object, name, child) {
    emit okKWriteField(runtime, object, name, child, 1)
}

func doKWeak(runtime, object, name, target) {
    emit okKWriteField(runtime, object, name, target, 2)
}

func okKHas(runtime, object, name) { emit okKField(runtime, object, name) != 0 }
func okKGet(runtime, object, name) {
    let field = okKField(runtime, object, name)
    if field == 0 { okKFail("unknown field: " + name) }
    let value = bufGetQwordAt(runtime, field + 24)
    if bufGetQwordAt(runtime, field + 32) == 2 && value != 0 {
        // Handles never reuse offsets, so a dead target cannot alias a new one.
        if bufGetQwordAt(runtime, value + 32) != 1 { emit 0 }
    }
    emit value
}

func okKRetain(runtime, object) {
    okKWritable(runtime, object)
    let refs = bufGetQwordAt(runtime, object + 16)
    if refs >= 1000000000 { okKFail("reference count overflow") }
    bufSetQwordAt(runtime, object + 16, refs + 1)
    emit object
}

func okKRefCount(runtime, object) {
    okKRequire(runtime, object, 3)
    emit bufGetQwordAt(runtime, object + 16)
}

func doKRelease(runtime, object) {
    okKWritable(runtime, object)
    let refs = bufGetQwordAt(runtime, object + 16) - 1
    bufSetQwordAt(runtime, object + 16, refs)
    if refs == 0 {
        // State 2 permits cleanup reads, but blocks resurrection and mutation.
        bufSetQwordAt(runtime, object + 32, 2)
        let klass = bufGetQwordAt(runtime, object + 8)
        while klass != 0 {
            let cleanup = bufGetQwordAt(runtime, klass + 40)
            if cleanup != 0 { callPtr(cleanup, runtime, object) }
            klass = bufGetQwordAt(runtime, klass + 8)
        }
        let field = bufGetQwordAt(runtime, object + 24)
        while field != 0 {
            if bufGetQwordAt(runtime, field + 32) == 1 {
                let child = bufGetQwordAt(runtime, field + 24)
                bufSetQwordAt(runtime, field + 24, 0)
                if child != 0 { doKRelease(runtime, child) }
            }
            field = bufGetQwordAt(runtime, field + 8)
        }
        // Tombstone handles, do not reuse offsets. Arena storage is reclaimed
        // by the host GC only when the whole runtime becomes unreachable.
        bufSetQwordAt(runtime, object + 24, 0)
        bufSetQwordAt(runtime, object + 32, 0)
    }
    emit refs
}
