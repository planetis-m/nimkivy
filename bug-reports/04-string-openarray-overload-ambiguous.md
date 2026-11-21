`f(s, [3, 4])` with overloads `f(openArray[char], openArray[int])` and `f(string, openArray[int])` is an "ambiguous call"; `unicode.strip(s, runes = ...)` fails the same way

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

With two overloads that differ only in the first parameter, `string` and `openArray[char]`, a call with a `string` first argument is rejected as ambiguous as soon as a second argument is passed to an `openArray` parameter. The `string` overload matches the first argument exactly and the `openArray[char]` one only by conversion, so by the category rules in `doc/language.md` ("Overload resolution", First Trial) the `string` overload wins. Without the second argument (both overloads given a default) the call resolves. The same happens with a seq argument (`@[3, 4]`) and with `{.feature: "v2".}`. Nim 2.4.1 compiles the program and prints 2.

The stdlib hits it: `std/unicode` has `strip(s: openArray[char], ..., runes: openArray[Rune])` and `strip(s: string, ..., runes: openArray[Rune])`, so `unicode.strip(s, runes = [Rune(0x20)])` with a `string` `s` is "ambiguous call: ''" (an empty name in the message), while `unicode.strip(s)` and `unicode.strip(s.toOpenArray(0, s.high), runes = [Rune(0x20)])` compile.

## Reproduction

Save the file in an empty directory and run the command below.

`overload_openarray.nim`:

```nim
import std/syncio

proc f(s: openArray[char]; xs: openArray[int]): int = 1
proc f(s: string; xs: openArray[int]): int = 2

let s = "ab"
echo f(s, [3, 4])
```

```
nimony c --nimcache:nc -o:overload_openarray overload_openarray.nim
```

## Actual

```
overload_openarray.nim(7, 1) Trace: instantiation from here
overload_openarray.nim(7, 7) Error: ambiguous call: 'f'
proc (s: openArray[char], xs: openArray[int64]): int64 (declared in overload_openarray.nim(3, 1))
proc (s: string, xs: openArray[int64]): int64 (declared in overload_openarray.nim(4, 1))
proc (s: openArray[char], xs: openArray[int64]): int64 (declared in overload_openarray.nim(3, 1))
proc (s: string, xs: openArray[int64]): int64 (declared in overload_openarray.nim(4, 1))
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:<key> m --isMain nc/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 nc/<hash>.build.nif
```

The two candidates are also listed twice.

The stdlib case, `import std/unicode` and `discard unicode.strip("  a  ", runes = [Rune(0x20)])` with a `let` string:

```
t.nim(4, 19) Error: ambiguous call: ''
func (s: openArray[char], leading: bool = true, trailing: bool = true, runes: openArray[Rune] = unicodeSpaces): string {.noSideEffect.} (declared in <nimony>/lib/std/unicode.nim(1151, 1))
func (s: string, leading: bool = true, trailing: bool = true, runes: openArray[Rune] = unicodeSpaces): string {.noSideEffect, inline.} (declared in <nimony>/lib/std/unicode.nim(1584, 1))
```

## Expected

It compiles and prints `2`: the `string` overload has one exact match where the `openArray[char]` overload has none, as in Nim 2 (`nim c -r` with Nim 2.4.1 prints `2`).

Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`); the error comes from `nimsem`, which is current.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/331
