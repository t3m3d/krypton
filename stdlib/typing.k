// stdlib/typing.k -- Python `typing` module surface.
//
// Type hints are erased by Krypton (no FE-level static checker yet),
// so this module is a placeholder that satisfies `from typing import
// List, Dict, Optional, Union, ...` lowerings without doing any
// runtime work.
//
// The Python FE strips type annotations during parsing; this file
// ensures the `import typing` resolves to actual definitions so
// programs that explicitly call `typing.List` or `typing.cast`
// don't blow up at lowering time.

module typing


// Generic type "factories" -- return the inner type unchanged so
// `List[int]` is just `int`-shaped at runtime.  These functions are
// identity wrappers.

func Listk(inner) {
    emit inner
}

func Tuplek(inner) {
    emit inner
}

func Dictk(k, v) {
    emit k
}

func Setk(inner) {
    emit inner
}

func Optionalk(inner) {
    emit inner
}

func Unionk(a, b) {
    emit a
}

func Anyk() {
    emit ""
}

// typing.cast(T, val) -- runtime no-op; the value passes through.
func castk(t, val) {
    emit val
}

// typing.TYPE_CHECKING -- the bool used to gate import-only-for-types
// blocks.  Always false at runtime in Krypton.
func TYPE_CHECKINGk() {
    emit 0
}

// typing.get_type_hints(obj) -- returns "" since we have no runtime
// type info.
func getTypeHintsk(obj) {
    emit ""
}

// typing.NewType(name, base) -- collapses to base.
func NewTypek(name, base) {
    emit base
}

// typing.TypeVar(name, ...) -- collapses to a generic placeholder.
func TypeVark(name) {
    emit name
}

// typing.Callable[[int, str], bool] -- collapse to "" (no runtime
// info).
func Callablek(args, ret) {
    emit ""
}
