A `typedesc[Base]` parameter rejects a subtype: `key(Sub)` is "expected: Base.Obj but got: Sub.Obj"

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

A proc with a parameter `t: typedesc[Base]` accepts `Base` but not a type that inherits from it (`Sub = ref object of Base`): the call `key(Sub)` is a type mismatch. A value of type `Sub` is accepted where a `Base` is expected, and Nim 2.4.1 accepts the type as well (`key(Sub)` prints 1). `{.feature: "v2".}` does not change it. Without it, a family of procs keyed by type (here: `opacityTo(Widget, 1.0)` for a property that `Widget` inherits) must name the exact type that declares them.

## Reproduction

Save the file in an empty directory and run the command shown under Actual.

`typedesc_subtype.nim`:

```nim
import std/syncio

type
  Base = ref object of RootObj
  Sub = ref object of Base

proc key(t: typedesc[Base]): int = 1

echo key(Base)
echo key(Sub)
```

## Actual

```
$ nimony c -r --nimcache:nc typedesc_subtype.nim
typedesc_subtype.nim(10, 1) Trace: instantiation from here
typedesc_subtype.nim(10, 9) Error: Type mismatch at [position]
key(Sub)
[1] expected: Base.Obj but got: Sub.Obj (declared in typedesc_subtype.nim(7, 1))
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:<key> m --isMain <nimcache>/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 <nimcache>/<hash>.build.nif
```

## Expected

```
1
1
```

as Nim 2.4.1 prints (`nim c -r typedesc_subtype.nim`).

## Notes

- The same with `{.feature: "v2".}` at the top of the module.
- Related, but a different construct: planetis-m/nimony-bugs-llms#330 (a subtype does not match a generic constraint `[T: Base]`).
- Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`); the error comes from `nimsem`, which is current.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/342
