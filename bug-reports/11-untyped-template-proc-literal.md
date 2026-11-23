A proc literal in the body of an `{.untyped.}` template crashes nimsem: "index -1 not in 0 .. 436" [IndexDefect], even when the template is never used

Fixed in nimony b1ffdf8d.

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

A template marked `{.untyped.}` (or every template under `{.feature: "untyped".}` or `"v2"`) whose body contains an anonymous proc crashes nimsem with an `IndexDefect`. The template does not need to be called. The same template without `{.untyped.}` compiles and runs.

## Reproduction

Save each file in an empty directory and run the command shown under Actual.

`lambda.nim`:

```nim
import std/syncio

template run(n: int) {.untyped.} =
  let f = proc (): int = n
  echo f()

run(3)
```

`unused.nim` (the template alone, never called):

```nim
import std/syncio

template run(n: int) {.untyped.} =
  let f = proc (): int = n
```

`checked.nim` (control, the same template without `{.untyped.}`):

```nim
import std/syncio

template run(n: int) =
  let f = proc (): int = n
  echo f()

run(3)
```

## Actual

```
$ nimony c -r --nimcache:nc lambda.nim
fatal.nim(62)            sysFatal
Error: unhandled exception: index -1 not in 0 .. 436 [IndexDefect]
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:<nimcache> --stdcache:<stdcache> --optionkey:AFDAA66A71115EA29948A0E3A3D327162A8EAF17 m --isMain <nimcache>/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 <nimcache>/<hash>.build.nif
```

```
$ nimony c -r --nimcache:nc unused.nim
fatal.nim(62)            sysFatal
Error: unhandled exception: index -1 not in 0 .. 436 [IndexDefect]
(the same nifmake lines)
```

```
$ nimony c -r --nimcache:nc checked.nim
3
```

## Expected

`lambda.nim` prints `3`, as `checked.nim` does, and `unused.nim` compiles. `{.untyped.}` only turns off the check of the template body at its definition.

## Notes

- The same with `{.feature: "untyped".}` or `{.feature: "v2".}` at the top of the module instead of the pragma, with a `proc () = discard` literal, with `{.closure.}` on the literal, and with an `untyped` parameter.
- Related, the same `IndexDefect` with a proc literal in another place nimsem defers: #315 (a parameter default), #64 and #86 (an object field default).
- Not checked: other backends.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/338
