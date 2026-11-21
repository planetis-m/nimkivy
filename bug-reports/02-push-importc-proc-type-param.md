Under `{.push importc.}`, a proc with a proc-typed parameter is "??? Error: expected `string` but got: auto"

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

Inside a `{.push importc.}` section, a body-less proc declaration whose parameter has a proc type (inline, or a named `proc ... {.cdecl.}` type) is rejected with "expected `string` but got: auto", with `???` in place of the position. The same declaration with `{.importc, cdecl.}` written on the proc itself compiles, so the pushed `importc` seems to reach the parameter's proc type as well. This is the usual way to bind a C function that takes a callback (here SDL3's `SDL_OpenAudioDeviceStream`).

## Reproduction

Save the file in an empty directory and run the command below.

`push_importc_proctype.nim`:

```nim
{.push importc, cdecl.}
proc atexit(fn: proc () {.cdecl.}): cint
{.pop.}
```

```
nimony c --nimcache:nc -o:push_importc_proctype push_importc_proctype.nim
```

## Actual

```
??? Error: expected `string` but got: auto
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:<key> m --isMain nc/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 nc/<hash>.build.nif
```

`proc atexit(fn: proc () {.cdecl.}): cint {.importc, cdecl.}` without the push compiles. With a named type, `type Cb = proc (x: cint) {.cdecl.}` and `proc f(cb: Cb): cint` under `{.push importc.}`, the error is the same; with `{.push header: "<stdlib.h>".}` and `importc` on the proc it compiles. `{.feature: "v2".}` does not change it.

## Expected

It compiles: a pushed `importc` applies to the procs declared in the section, not to the proc types of their parameters, as in Nim 2.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/329
