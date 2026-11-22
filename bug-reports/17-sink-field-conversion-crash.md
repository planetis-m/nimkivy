A `sink` ref parameter whose field is read inside a conversion or a tuple subscript crashes shoggoth: typenav "`result.hasMore` ParRi" on `(dot (deref x) d.00 0)`

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/346 (labels: crash, phase:hexer-arc, found:llm-agents)

Nimony 0.6.3, commit `88d04ab0` (current master), Linux amd64, C backend (`nimony c`).

A `sink` parameter of a `ref` type crashes shoggoth when a field read through it is the operand of a conversion (`float32(x.f)`, or the implicit conversion of a subtype field to a base-type parameter) or of a tuple subscript (`x.tup[0]`). The failure is an assertion in typenav on `(dot (deref x) d.00 0)`. The same programs without `sink` build and run. A plain field read (`result = x.f`, `x.f + 1.0`), a call on the field (`abs(x.f)`) and an array subscript (`x.arr[0]`) do not crash.

## Reproduction

Save each file in an empty directory and run the commands below.

`conv.nim` (an explicit conversion):

```nim
type
  Options = ref object
    height: float

proc layout(options: sink Options): float32 =
  result = float32(options.height)

discard layout(Options(height: 1.0))
```

`tuple.nim` (a tuple subscript):

```nim
type
  Touch = ref object
    pos: (float, float)

proc x(touch: sink Touch): float =
  result = touch.pos[0]

discard x(Touch(pos: (1.0, 2.0)))
```

`base.nim` (a subtype field passed to a base-type parameter):

```nim
type
  Base = ref object of RootObj
  Sub = ref object of Base
  Holder = ref object
    item: Sub

proc use(b: Base) = discard

proc f(h: sink Holder) =
  use(h.item)

f(Holder(item: Sub()))
```

```
nimony c --nimcache:nc_conv conv.nim
nimony c --nimcache:nc_tuple tuple.nim
nimony c --nimcache:nc_base base.nim
```

## Actual

```
== nimony c --nimcache:nc_conv conv.nim
assertions.nim(38)       raiseAssert
Error: unhandled exception: typenav.nim(749, 3) `result.hasMore` ParRi for expression: (dot
 (deref options.0)d.00 0) [AssertionDefect]
nifmake: command failed (exit code 1): <nimony>/bin/shoggoth c --bits:64 --cpu:le --os:Linux --stdcache:<stdcache> --flags:br --isMain --app:console --outdir:nc_conv/c/con6nooeu nc_conv/con6nooeu.s.nif
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 nc_conv/c/con6nooeu.final.build.nif
== nimony c --nimcache:nc_tuple tuple.nim
assertions.nim(38)       raiseAssert
Error: unhandled exception: typenav.nim(749, 3) `result.hasMore` ParRi for expression: (dot
 (deref touch.0)d.00 0) [AssertionDefect]
nifmake: command failed (exit code 1): <nimony>/bin/shoggoth c --bits:64 --cpu:le --os:Linux --stdcache:<stdcache> --flags:br --isMain --app:console --outdir:nc_tuple/c/tup2tadr6 nc_tuple/tup2tadr6.s.nif
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 nc_tuple/c/tup2tadr6.final.build.nif
== nimony c --nimcache:nc_base base.nim
assertions.nim(38)       raiseAssert
Error: unhandled exception: typenav.nim(749, 3) `result.hasMore` ParRi for expression: (dot
 (deref h.0)d.00 0) [AssertionDefect]
nifmake: command failed (exit code 1): <nimony>/bin/shoggoth c --bits:64 --cpu:le --os:Linux --stdcache:<stdcache> --flags:br --isMain --app:console --outdir:nc_base/c/bashrfblg1 nc_base/bashrfblg1.s.nif
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 nc_base/c/bashrfblg1.final.build.nif
```

## Expected

All three build: `sink` on a parameter that is only read is valid, and each file builds with the parameter's `sink` removed.

## Notes

- `d.00` is the data field of the lowered `ref`; the expression looks like the inlined destruction of the `sink` parameter at the end of the routine, applied where the parameter is wrapped in a conversion or a tuple subscript.
- Not crashing: `result = options.height`, `result = options.height + 1.0`, `result = abs(options.height)`, `result = touch.arr[0]` with `arr: array[2, float]`, `let p = touch.pos; result = p[0]`, and `x in h.items` with `items: seq[int]`.
- Found while adding `sink` to the parameters a UI library keeps (stores in a field, a seq or an observer list).
