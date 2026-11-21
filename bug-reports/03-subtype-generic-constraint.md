A subtype does not match a generic constraint `[T: Base]`: "ref Sub.Obj not nil does not match constraint T"

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

A generic proc whose type parameter is constrained by an object or `ref object` type, `proc same[T: Base](v: T)`, accepts `Base` but rejects a type that inherits from it (`Sub = ref object of Base`) with "does not match constraint T". The same happens for a plain `object of Base`, with `{.untyped.}` on the proc, and with `{.feature: "v2".}`. Nim 2.4.1 compiles and runs the program. Without it, a helper over a class hierarchy (here: build any vertex instruction and return it with its own type) needs one overload per subtype.

## Reproduction

Save the file in an empty directory and run the command below.

`subtype_constraint.nim`:

```nim
type
  Base = ref object of RootObj
  Sub = ref object of Base

proc same[T: Base](v: T): T =
  result = v

discard same(Base())
discard same(Sub())
```

```
nimony c --nimcache:nc -o:subtype_constraint subtype_constraint.nim
```

## Actual

```
subtype_constraint.nim(9, 13) Error: Type mismatch at [position]
same((ref Sub.Obj not nil)())
[1] ref Sub.Obj not nil does not match constraint T (declared in subtype_constraint.nim(5, 1))
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:<key> m --isMain nc/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 nc/<hash>.build.nif
```

`same(Base())` alone compiles. The non-ref form (`Base = object of RootObj`, `Sub = object of Base`, `same(Sub())`) fails the same way. `{.untyped.}` on `same` and `{.feature: "v2".}` do not change it. `nim c -r subtype_constraint.nim` with Nim 2.4.1 compiles and runs.

## Expected

It compiles, `T` inferred as `Sub`: a type that inherits from `Base` satisfies the constraint `T: Base`, as in Nim 2.

Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`); the error comes from `nimsem`, which is current.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/330
