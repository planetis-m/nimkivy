An object constructor in an `{.untyped.}` template that sets an inherited field gives invalid C ("has no member named 'value_0'") when a proc has the field's name

Fixed in nimony b1ffdf8d.

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

In a template marked `{.untyped.}`, `T(value: 1.0)` with `T` a subtype whose parent declares `value` compiles in nimsem, but the C code sets `.value_0` on the subtype's own struct instead of on its parent part, and gcc rejects it. It happens only when some proc in scope is also called `value` (here an accessor of an unrelated type). The same constructor written directly, or without the proc, works.

## Reproduction

Save each file in an empty directory and run the command shown under Actual.

`ctor.nim`:

```nim
import std/syncio

type
  Mid = ref object of RootObj
    value: float
  Leaf = ref object of Mid
    c: float
  Other = object
    m: float

proc value(o: Other): float = o.m

template make(T: untyped) {.untyped.} =
  let x = T(value: 1.0)
  echo x.value

make(Leaf)
```

`noproc.nim` (control): `ctor.nim` without the line `proc value(o: Other): float = o.m`.

`direct.nim` (control): `ctor.nim` with `make(Leaf)` replaced by the template's two lines, `let x = Leaf(value: 1.0)` and `echo x.value`.

## Actual

```
$ nimony c -r --nimcache:nc ctor.nim
<nimcache>/c/<hash>/<hash>.c: In function 'main':
<nimcache>/c/<hash>/<hash>.c:554:44: error: 'Leaf_Obj_0_ctoxhy5111' has no member named 'value_0'
  554 |           (&Leaf_ObjX60Qvt_0_ctoxhy5111), .value_0 = 1.0, .c_0 = ((NF64)0.0)}}
      |                                            ^~~~~~~
nifmake: command failed (exit code 1): gcc -c -Wno-attributes -fwrapv -fno-math-errno -Wno-stringop-overflow -O1 -I. <nimcache>/c/<hash>/<hash>.c -o <nimcache>/c/<hash>/<hash>.o
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 <nimcache>/c/<hash>.final.build.nif
```

```
$ nimony c -r --nimcache:nc noproc.nim
1.0
$ nimony c -r --nimcache:nc direct.nim
1.0
```

## Expected

`ctor.nim` prints `1.0`, as both controls do. The field is `Mid.value`, so the C initializer should set it on the parent part (`.Q.value_0`, as the direct constructor does).

## Notes

- Found with a template run on two types (`template t(T: untyped) {.untyped.} = let w = T(baseValue: 1.0) ...`) where another type has a property accessor `baseValue`.
- Related: #318 (a parent's case selector loses its inheritance depth in `=wasMoved`), a different path to the same invalid C.
- Not checked: other backends; `{.feature: "untyped".}` instead of the pragma.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/339
