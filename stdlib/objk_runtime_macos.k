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
        if bufGetQwordAt(runtime, cursor + 16) == 0 {
            let next = cursor + bufGetQwordAt(runtime, cursor)
            while next < used && bufGetQwordAt(runtime, next + 16) == 0 {
                bufSetQwordAt(runtime, cursor, bufGetQwordAt(runtime, cursor) + bufGetQwordAt(runtime, next))
                next = cursor + bufGetQwordAt(runtime, cursor)
            }
            let available = bufGetQwordAt(runtime, cursor)
            if available >= size {
                if available - size >= 24 {
                    let remainder = cursor + size
                    bufSetQwordAt(runtime, remainder, available - size)
                    bufSetQwordAt(runtime, remainder + 8, 0)
                    bufSetQwordAt(runtime, remainder + 16, 0)
                    bufSetQwordAt(runtime, cursor, size)
                }
                break
            }
        }
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

// Record layouts: class {kind,parent,name,methods,sealed,cleanup,protocols}; method
// {kind,next,name,arity,fn,argClassA,argClassB,resultClass}; object
// {kind,class,refs,fields,alive}; field
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
    let handle = okKAllocate(runtime, 56)
    okKWrite(runtime, handle, 0, 1)
    okKWrite(runtime, handle, 8, parent)
    okKWrite(runtime, handle, 16, storedName)
    okKWrite(runtime, handle, 24, 0)
    okKWrite(runtime, handle, 32, 0)
    okKWrite(runtime, handle, 40, 0)
    okKWrite(runtime, handle, 48, 0)
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
    let inherited = okKFindMethod(runtime, okKRead(runtime, klass, 8), name)
    let firstClass = 0
    let secondClass = 0
    let resultClass = 0
    if inherited != 0 {
        firstClass = okKRead(runtime, inherited, 40)
        secondClass = okKRead(runtime, inherited, 48)
        resultClass = okKRead(runtime, inherited, 56)
        if firstClass != 0 || secondClass != 0 || resultClass != 0 {
            if arity != okKRead(runtime, inherited, 24) { okKFail("typed override argument count") }
        }
    }
    let storedName = okKText(runtime, name)
    let method = okKAllocate(runtime, 64)
    okKWrite(runtime, method, 0, 2)
    okKWrite(runtime, method, 8, okKRead(runtime, klass, 24))
    okKWrite(runtime, method, 16, storedName)
    okKWrite(runtime, method, 24, arity)
    okKWrite(runtime, method, 32, fnPtr)
    okKWrite(runtime, method, 40, firstClass)
    okKWrite(runtime, method, 48, secondClass)
    okKWrite(runtime, method, 56, resultClass)
    okKWrite(runtime, klass, 24, method)
    emit method
}

func okKObjectMethod(runtime, klass, name, arity, fnPtr, firstClass, secondClass, resultClass) {
    if arity < 1 && firstClass != 0 { okKFail("type for absent argument") }
    if arity < 2 && secondClass != 0 { okKFail("type for absent argument") }
    if firstClass != 0 { okKRequire(runtime, firstClass, 1) }
    if secondClass != 0 { okKRequire(runtime, secondClass, 1) }
    if resultClass != 0 { okKRequire(runtime, resultClass, 1) }
    let method = okKMethod(runtime, klass, name, arity, fnPtr)
    let inherited = okKFindMethod(runtime, okKRead(runtime, klass, 8), name)
    if inherited != 0 {
        let oldFirst = okKRead(runtime, inherited, 40)
        let oldSecond = okKRead(runtime, inherited, 48)
        let oldResult = okKRead(runtime, inherited, 56)
        if oldFirst != 0 || oldSecond != 0 || oldResult != 0 {
            if oldFirst != firstClass || oldSecond != secondClass || oldResult != resultClass {
                okKFail("typed override signature")
            }
        }
    }
    okKWrite(runtime, method, 40, firstClass)
    okKWrite(runtime, method, 48, secondClass)
    okKWrite(runtime, method, 56, resultClass)
    emit method
}

func okKCheckObjectType(runtime, value, klass) {
    if klass != 0 {
        if okKIsA(runtime, value, klass) != 1 { okKFail("method object type mismatch") }
    }
    emit value
}

func doKRegister(runtime, klass) {
    okKRequire(runtime, klass, 1)
    let current = klass
    while current != 0 {
        let declaration = okKRead(runtime, current, 48)
        while declaration != 0 {
            okKCheckProtocol(runtime, klass, okKRead(runtime, declaration, 16))
            declaration = okKRead(runtime, declaration, 8)
        }
        current = okKRead(runtime, current, 8)
    }
    okKWrite(runtime, klass, 32, 1)
    emit klass
}

func okKProtocol(runtime, name, parent) {
    if name == "" { okKFail("empty protocol name") }
    if parent != 0 {
        okKRequire(runtime, parent, 7)
        if okKRead(runtime, parent, 32) != 1 { okKFail("parent protocol not registered") }
    }
    let storedName = okKText(runtime, name)
    let protocol = okKAllocate(runtime, 40)
    okKWrite(runtime, protocol, 0, 7)
    okKWrite(runtime, protocol, 8, parent)
    okKWrite(runtime, protocol, 16, storedName)
    okKWrite(runtime, protocol, 24, 0)
    okKWrite(runtime, protocol, 32, 0)
    emit protocol
}

func okKProtocolRequirement(runtime, protocol, name) {
    let current = protocol
    while current != 0 {
        okKRequire(runtime, current, 7)
        let requirement = okKRead(runtime, current, 24)
        while requirement != 0 {
            if okKTextEquals(runtime, okKRead(runtime, requirement, 16), name) { emit requirement }
            requirement = okKRead(runtime, requirement, 8)
        }
        current = okKRead(runtime, current, 8)
    }
    emit 0
}

func doKRequireMethod(runtime, protocol, name, arity, firstClass, secondClass, resultClass) {
    okKRequire(runtime, protocol, 7)
    if okKRead(runtime, protocol, 32) != 0 { okKFail("protocol already registered") }
    if name == "" { okKFail("empty requirement name") }
    if arity < 0 || arity > 2 { okKFail("method arity out of range") }
    if arity < 1 && firstClass != 0 { okKFail("type for absent argument") }
    if arity < 2 && secondClass != 0 { okKFail("type for absent argument") }
    if firstClass != 0 { okKRequire(runtime, firstClass, 1) }
    if secondClass != 0 { okKRequire(runtime, secondClass, 1) }
    if resultClass != 0 { okKRequire(runtime, resultClass, 1) }
    if okKProtocolRequirement(runtime, protocol, name) != 0 { okKFail("duplicate requirement") }
    let storedName = okKText(runtime, name)
    let requirement = okKAllocate(runtime, 64)
    okKWrite(runtime, requirement, 0, 8)
    okKWrite(runtime, requirement, 8, okKRead(runtime, protocol, 24))
    okKWrite(runtime, requirement, 16, storedName)
    okKWrite(runtime, requirement, 24, arity)
    okKWrite(runtime, requirement, 32, 0)
    okKWrite(runtime, requirement, 40, firstClass)
    okKWrite(runtime, requirement, 48, secondClass)
    okKWrite(runtime, requirement, 56, resultClass)
    okKWrite(runtime, protocol, 24, requirement)
    emit protocol
}

func doKRegisterProtocol(runtime, protocol) {
    okKRequire(runtime, protocol, 7)
    okKWrite(runtime, protocol, 32, 1)
    emit protocol
}

func doKConform(runtime, klass, protocol) {
    okKRequire(runtime, klass, 1)
    okKRequire(runtime, protocol, 7)
    if okKRead(runtime, klass, 32) != 0 { okKFail("class already registered") }
    if okKRead(runtime, protocol, 32) != 1 { okKFail("protocol not registered") }
    let declaration = okKRead(runtime, klass, 48)
    while declaration != 0 {
        if okKRead(runtime, declaration, 16) == protocol { okKFail("duplicate conformance") }
        declaration = okKRead(runtime, declaration, 8)
    }
    declaration = okKAllocate(runtime, 24)
    okKWrite(runtime, declaration, 0, 9)
    okKWrite(runtime, declaration, 8, okKRead(runtime, klass, 48))
    okKWrite(runtime, declaration, 16, protocol)
    okKWrite(runtime, klass, 48, declaration)
    emit klass
}

func okKCheckProtocol(runtime, klass, protocol) {
    let current = protocol
    while current != 0 {
        let requirement = okKRead(runtime, current, 24)
        while requirement != 0 {
            let name = okKTextValue(runtime, okKRead(runtime, requirement, 16))
            let method = okKFindMethod(runtime, klass, name)
            if method == 0 { okKFail("protocol missing method: " + name) }
            if okKRead(runtime, method, 24) != okKRead(runtime, requirement, 24) { okKFail("protocol method arity: " + name) }
            if okKRead(runtime, method, 40) != okKRead(runtime, requirement, 40) ||
                okKRead(runtime, method, 48) != okKRead(runtime, requirement, 48) ||
                okKRead(runtime, method, 56) != okKRead(runtime, requirement, 56) {
                okKFail("protocol method signature: " + name)
            }
            requirement = okKRead(runtime, requirement, 8)
        }
        current = okKRead(runtime, current, 8)
    }
    emit klass
}

func okKConforms(runtime, object, protocol) {
    okKRequire(runtime, protocol, 7)
    if okKRead(runtime, protocol, 32) != 1 { okKFail("protocol not registered") }
    let klass = okKObjectClass(runtime, object)
    while klass != 0 {
        let declaration = okKRead(runtime, klass, 48)
        while declaration != 0 {
            let current = okKRead(runtime, declaration, 16)
            while current != 0 {
                if current == protocol { emit 1 }
                current = okKRead(runtime, current, 8)
            }
            declaration = okKRead(runtime, declaration, 8)
        }
        klass = okKRead(runtime, klass, 8)
    }
    emit 0
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
    if arity > 0 { okKCheckObjectType(runtime, a, okKRead(runtime, method, 40)) }
    if arity > 1 { okKCheckObjectType(runtime, b, okKRead(runtime, method, 48)) }
    let fnPtr = okKRead(runtime, method, 32)
    let result = 0
    if arity == 0 { result = callPtr(fnPtr, runtime, object) }
    else if arity == 1 { result = callPtr(fnPtr, runtime, object, a) }
    else { result = callPtr(fnPtr, runtime, object, a, b) }
    emit okKCheckObjectType(runtime, result, okKRead(runtime, method, 56))
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
            field = okKRead(runtime, field, 8)
        }
        // Child hooks can still read their releasing owner's entire field list.
        field = okKRead(runtime, object, 24)
        while field != 0 {
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
