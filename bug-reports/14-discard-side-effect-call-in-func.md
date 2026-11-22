`discard` of a call with side effects in a `func` (or iterator) crashes nimsem ("[Bug] bug in isTrival computation") instead of reporting the side effect

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

Calling a `proc` (which has side effects) from a `func` is an error, and `let x = noisy()` in a `func` reports it at the call. When the result is discarded, `discard noisy()`, nimsem aborts with an internal error that only quotes the message. The same happens in an iterator, which has no side effects by default. `{.feature: "v2".}` changes nothing.

## Reproduction

Save the file in an empty directory and run the command shown under Actual.

`i.nim`:

```nim
import std/syncio

proc noisy(): bool =
  echo "noisy"
  result = true

func f(): int =
  discard noisy()
  result = 1

echo f()
```

## Actual

```
$ nimony c -r --nimcache:nc i.nim
isTrivial: (err . "cannot call a routine with side effects from a `.noSideEffect` context")
No stack traceback available
[Bug] bug in isTrival computation
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:<key> m --isMain <nimcache>/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 <nimcache>/<hash>.build.nif
```

## Expected

```
i.nim(8, 11) Error: cannot call a routine with side effects from a `.noSideEffect` context
```

as with `let x = noisy()` in place of `discard noisy()`.

## Notes

- The same in an iterator (`iterator walk(): int` with `discard fill(acc)`), where it was found.
- The same with `{.feature: "v2".}` at the top of the module.
- Different from nim-lang/nimony#2605 (closed; `isTrivial: (nilt)` in hexer).
- Not checked: other backends.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/341
