// Handles are IDs, not interior pointers: macOS GC scans roots, not graphs.

module objk_runtime_macos

func okKFail(message) {
    kp("Objective-K: " + message)
    exit("1")
}

func okKRuntime(capacity) {
    if capacity < 64 || capacity > 1048576 { okKFail("arena capacity out of range") }
    let runtime = bufNew(capacity)
    bufSetQwordAt(runtime, 0, capacity)
    bufSetQwordAt(runtime, 8, 32)
    bufSetQwordAt(runtime, 16, 24)
    emit runtime
}

func okKAllocate(runtime, bytes) {
    let used = bufGetQwordAt(runtime, 8)
    let size = ((bytes + 7) / 8) * 8 + 16
    let cursor = 32
    while cursor < used {
        if bufGetQwordAt(runtime, cursor + 16) == 0 && bufGetQwordAt(runtime, cursor) >= size { break }
        cursor += bufGetQwordAt(runtime, cursor)
    }
    if cursor == used {
        if cursor + size > bufGetQwordAt(runtime, 0) { okKFail("arena full") }
        bufSetQwordAt(runtime, cursor, size)
        bufSetQwordAt(runtime, 8, cursor + size)
    }
    let handle = bufGetQwordAt(runtime, 16)
    if handle > 999999984 { okKFail("handle ID exhausted") }
    bufSetQwordAt(runtime, 16, handle + 16)
    bufSetQwordAt(runtime, cursor + 8, handle)
    bufSetQwordAt(runtime, cursor + 16, 6)
    emit handle
}

func okKLookup(runtime, handle) {
    if handle < 24 || handle >= bufGetQwordAt(runtime, 16) || handle % 16 != 8 { okKFail("invalid handle") }
    let cursor = 32
    while cursor < bufGetQwordAt(runtime, 8) {
        if bufGetQwordAt(runtime, cursor + 8) == handle && bufGetQwordAt(runtime, cursor + 16) != 0 { emit cursor + 16 }
        cursor += bufGetQwordAt(runtime, cursor)
    }
    emit 0
}

func okKOffset(runtime, handle) {
    let offset = okKLookup(runtime, handle)
    if offset == 0 { okKFail("object released or stale handle") }
    emit offset
}

func okKRead(runtime, handle, offset) {
    emit bufGetQwordAt(runtime, okKOffset(runtime, handle) + offset)
}

func okKWrite(runtime, handle, offset, value) {
    bufSetQwordAt(runtime, okKOffset(runtime, handle) + offset, value)
}

func okKRequire(runtime, handle, kind) {
    if okKRead(runtime, handle, 0) != kind { okKFail("wrong handle kind") }
    emit handle
}

func doKFree(runtime, handle) {
    bufSetQwordAt(runtime, okKOffset(runtime, handle), 0)
}

// Record layouts: class {kind,parent,name,methods,sealed,cleanup}; method
// {kind,next,name,arity,fn}; object {kind,class,refs,fields,alive}; field
// {kind,next,name,value,policy}; text {kind,length,bytes...}.
// Field policy: 0 borrowed, 1 owned, 2 weak.
func okKText(runtime, text) {
    let n = len(text)
    let handle = okKAllocate(runtime, 16 + n)
    okKWrite(runtime, handle, 0, 5)
    okKWrite(runtime, handle, 8, n)
    let i = 0
    while i < n {
        bufSetByte(runtime, okKOffset(runtime, handle) + 16 + i, charCode(text[i]))
        i += 1
    }
    emit handle
}

func okKTextEquals(runtime, handle, text) {
    okKRequire(runtime, handle, 5)
    let n = okKRead(runtime, handle, 8)
    if n != len(text) { emit 0 }
    let i = 0
    while i < n {
        if bufGetByte(runtime, okKOffset(runtime, handle) + 16 + i) != charCode(text[i]) { emit 0 }
        i += 1
    }
    emit 1
}

func okKTextValue(runtime, handle) {
    okKRequire(runtime, handle, 5)
    let n = okKRead(runtime, handle, 8)
    let text = ""
    let i = 0
    while i < n {
        text = text + fromCharCode(bufGetByte(runtime, okKOffset(runtime, handle) + 16 + i))
        i += 1
    }
    emit text
}

func okKClass(runtime, name, parent) {
    if name == "" { okKFail("empty class name") }
    if parent != 0 {
        okKRequire(runtime, parent, 1)
        if okKRead(runtime, parent, 32) != 1 { okKFail("parent class not registered") }
    }
    let storedName = okKText(runtime, name)
    let handle = okKAllocate(runtime, 48)
    okKWrite(runtime, handle, 0, 1)
    okKWrite(runtime, handle, 8, parent)
    okKWrite(runtime, handle, 16, storedName)
    okKWrite(runtime, handle, 24, 0)
    okKWrite(runtime, handle, 32, 0)
    okKWrite(runtime, handle, 40, 0)
    emit handle
}

func okKClassName(runtime, klass) {
    okKRequire(runtime, klass, 1)
    emit okKTextValue(runtime, okKRead(runtime, klass, 16))
}

func okKOwnMethod(runtime, klass, name) {
    okKRequire(runtime, klass, 1)
    let method = okKRead(runtime, klass, 24)
    while method != 0 {
        if okKTextEquals(runtime, okKRead(runtime, method, 16), name) { emit method }
        method = okKRead(runtime, method, 8)
    }
    emit 0
}

func okKMethod(runtime, klass, name, arity, fnPtr) {
    okKRequire(runtime, klass, 1)
    if okKRead(runtime, klass, 32) != 0 { okKFail("class already registered") }
    if name == "" || fnPtr == 0 { okKFail("invalid method") }
    if arity < 0 || arity > 2 { okKFail("method arity out of range") }
    if okKOwnMethod(runtime, klass, name) != 0 { okKFail("duplicate method") }
    let storedName = okKText(runtime, name)
    let method = okKAllocate(runtime, 40)
    okKWrite(runtime, method, 0, 2)
    okKWrite(runtime, method, 8, okKRead(runtime, klass, 24))
    okKWrite(runtime, method, 16, storedName)
    okKWrite(runtime, method, 24, arity)
    okKWrite(runtime, method, 32, fnPtr)
    okKWrite(runtime, klass, 24, method)
    emit method
}

func doKRegister(runtime, klass) {
    okKRequire(runtime, klass, 1)
    okKWrite(runtime, klass, 32, 1)
    emit klass
}

func doKCleanup(runtime, klass, fnPtr) {
    okKRequire(runtime, klass, 1)
    if okKRead(runtime, klass, 32) != 0 { okKFail("class already registered") }
    if fnPtr == 0 { okKFail("invalid cleanup callback") }
    if okKRead(runtime, klass, 40) != 0 { okKFail("cleanup already registered") }
    okKWrite(runtime, klass, 40, fnPtr)
    emit klass
}

func okKNew(runtime, klass) {
    okKRequire(runtime, klass, 1)
    if okKRead(runtime, klass, 32) != 1 { okKFail("class not registered") }
    let object = okKAllocate(runtime, 40)
    okKWrite(runtime, object, 0, 3)
    okKWrite(runtime, object, 8, klass)
    okKWrite(runtime, object, 16, 1)
    okKWrite(runtime, object, 24, 0)
    okKWrite(runtime, object, 32, 1)
    emit object
}

func okKAlive(runtime, object) {
    okKRequire(runtime, object, 3)
    if okKRead(runtime, object, 32) == 0 { okKFail("object released") }
    emit object
}

func okKWritable(runtime, object) {
    okKAlive(runtime, object)
    if okKRead(runtime, object, 32) != 1 { okKFail("object releasing") }
    emit object
}

func okKObjectClass(runtime, object) {
    okKAlive(runtime, object)
    emit okKRead(runtime, object, 8)
}

func okKIsA(runtime, object, klass) {
    okKRequire(runtime, klass, 1)
    let current = okKObjectClass(runtime, object)
    while current != 0 {
        if current == klass { emit 1 }
        current = okKRead(runtime, current, 8)
    }
    emit 0
}

func okKFindMethod(runtime, klass, name) {
    let current = klass
    while current != 0 {
        let method = okKOwnMethod(runtime, current, name)
        if method != 0 { emit method }
        current = okKRead(runtime, current, 8)
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
    if okKRead(runtime, method, 24) != arity { okKFail("method argument count: " + name) }
    let fnPtr = okKRead(runtime, method, 32)
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
    let parent = okKRead(runtime, definingClass, 8)
    emit okKInvoke(runtime, object, parent, name, 0, 0, 0)
}

func okKField(runtime, object, name) {
    okKAlive(runtime, object)
    let field = okKRead(runtime, object, 24)
    while field != 0 {
        if okKTextEquals(runtime, okKRead(runtime, field, 16), name) { emit field }
        field = okKRead(runtime, field, 8)
    }
    emit 0
}

func okKWriteField(runtime, object, name, value, policy) {
    okKWritable(runtime, object)
    if policy != 0 && value != 0 { okKWritable(runtime, value) }
    let field = okKField(runtime, object, name)
    let previous = 0
    if field != 0 && okKRead(runtime, field, 32) == 1 {
        if policy != 1 { okKFail("owned field needs doKOwn") }
        previous = okKRead(runtime, field, 24)
    }
    if field != 0 && okKRead(runtime, field, 32) == 2 && policy != 2 {
        okKFail("weak field needs doKWeak")
    }
    if field == 0 {
        let storedName = okKText(runtime, name)
        field = okKAllocate(runtime, 40)
        okKWrite(runtime, field, 0, 4)
        okKWrite(runtime, field, 8, okKRead(runtime, object, 24))
        okKWrite(runtime, field, 16, storedName)
        okKWrite(runtime, object, 24, field)
    }
    // Retain before replacement so assigning the same child cannot destroy it.
    if policy == 1 && value != 0 { okKRetain(runtime, value) }
    okKWrite(runtime, field, 24, value)
    okKWrite(runtime, field, 32, policy)
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
    let value = okKRead(runtime, field, 24)
    if okKRead(runtime, field, 32) == 2 && value != 0 {
        if okKLookup(runtime, value) == 0 { emit 0 }
        if okKRead(runtime, value, 32) != 1 { emit 0 }
    }
    emit value
}

func okKRetain(runtime, object) {
    okKWritable(runtime, object)
    let refs = okKRead(runtime, object, 16)
    if refs >= 1000000000 { okKFail("reference count overflow") }
    okKWrite(runtime, object, 16, refs + 1)
    emit object
}

func okKRefCount(runtime, object) {
    if okKLookup(runtime, object) == 0 { emit 0 }
    okKRequire(runtime, object, 3)
    emit okKRead(runtime, object, 16)
}

func doKRelease(runtime, object) {
    okKWritable(runtime, object)
    let refs = okKRead(runtime, object, 16) - 1
    okKWrite(runtime, object, 16, refs)
    if refs == 0 {
        // State 2 permits cleanup reads, but blocks resurrection and mutation.
        okKWrite(runtime, object, 32, 2)
        let klass = okKRead(runtime, object, 8)
        while klass != 0 {
            let cleanup = okKRead(runtime, klass, 40)
            if cleanup != 0 { callPtr(cleanup, runtime, object) }
            klass = okKRead(runtime, klass, 8)
        }
        let field = okKRead(runtime, object, 24)
        while field != 0 {
            if okKRead(runtime, field, 32) == 1 {
                let child = okKRead(runtime, field, 24)
                okKWrite(runtime, field, 24, 0)
                if child != 0 { doKRelease(runtime, child) }
            }
            let next = okKRead(runtime, field, 8)
            doKFree(runtime, okKRead(runtime, field, 16))
            doKFree(runtime, field)
            field = next
        }
        okKWrite(runtime, object, 24, 0)
        doKFree(runtime, object)
    }
    emit refs
}
