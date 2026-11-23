`s.add ("a", proc ... = ...)` on a `seq` of tuples with a proc field crashes shoggoth: "symId on DotToken"

Fixed in nimony b1ffdf8d.

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

Adding a tuple constructor whose second element is an anonymous proc literal to a `seq[(string, P)]`, where `P` is a proc type, passes sem and then crashes `shoggoth c` with an `AssertionDefect`, "symId on DotToken". `{.closure.}` and `{.nimcall.}` crash the same way, and so does `{.feature: "v2".}`. Binding the tuple to a `let` first (`let t: (string, P) = ("a", proc ...)`, then `s.add t`) compiles and runs. Nim 2.4.1 compiles and runs the program and prints 1.

## Reproduction

Save the file in an empty directory and run the command below.

`add_tuple_proc_literal.nim`:

```nim
import std/syncio

type Setup = proc (x: int): int {.closure.}

var cases: seq[(string, Setup)] = @[]
cases.add ("a", proc (x: int): int {.closure.} = x + 1)
echo cases.len
```

```
nimony c --nimcache:nc -o:add_tuple_proc_literal add_tuple_proc_literal.nim
```

## Actual

```
assertions.nim(38)       raiseAssert
Error: unhandled exception: symId on DotToken [AssertionDefect]
nifmake: command failed (exit code 1): <nimony>/bin/shoggoth c --bits:64 --cpu:le --os:Linux --stdcache:<stdcache> --flags:br --isMain --app:console --outdir:nc/c/<hash> nc/<hash>.s.nif
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 nc/c/<hash>.final.build.nif
```

## Expected

It compiles and prints `1`, as with Nim 2.4.1 (`nim c -r`).

Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`); the crash is in `shoggoth`, which is current. The phase label is a guess from the failing tool.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/332
