`if c: x else: nil` assigned to a `nil T` is "expected non-nil value"; `if not c: nil else: x` compiles

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

An `if` expression whose first branch is a non-nil `ref` and whose `else` branch is `nil` is rejected with "expected non-nil value", although it is assigned to a nullable `nil Node` result. Swapping the branches (`nil` first) compiles, so the expression seems to take the not-nil type of its first branch instead of the expected type.

## Reproduction

Save the file in an empty directory and run the command below.

`if_nil_branch.nim`:

```nim
type Node = ref object
  x: int

proc pick(s: seq[Node]; i: int): nil Node =
  result = if i >= 0: s[i] else: nil

discard pick(@[Node(x: 1)], 0)
```

```
nimony c --nimcache:nc -o:if_nil_branch if_nil_branch.nim
```

## Actual

```
if_nil_branch.nim(5, 34) Error: expected non-nil value [pass --verbose for the Final IR]
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:<key> m --isMain nc/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 nc/<hash>.build.nif
```

The same proc with the branches swapped, `result = if i < 0: nil else: s[i]`, compiles. With `{.feature: "v2".}` (which makes `ref` nullable) it compiles too.

## Expected

It compiles: the `if` expression has the expected type `nil Node`, which both branches fit, whatever their order.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/328
