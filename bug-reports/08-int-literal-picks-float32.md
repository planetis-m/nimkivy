An integer literal passed where `float32` and `float` overloads both fit picks `float32` instead of reporting the ambiguity: `let b: float = 1 / 3` is `0.3333333432674408`

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

An integer literal argument matches a `float32` parameter and a `float` parameter equally well: both are an "integral conversion match" in `doc/language.md` (Overload resolution, First Trial), and equal matches are to be "reported during semantic analysis" as ambiguous. Instead the `float32` overload is always chosen, whatever the declaration order. The system has no `/` for `int`, so `1 / 3` resolves to `/`(float32, float32) and is computed in single precision, even when the result is assigned to a `float`. The same happens with `{.feature: "v2".}`. Nim 2 gives `0.3333333333333333` (its `/`(int, int): float).

In real code, a test wrote `abs(length - 61828 / 44100) < 1e-12` and failed: `61828 / 44100` was `1.4019954204559326`, not `1.4019954648526076`.

## Reproduction

Save the file in an empty directory and run the command below.

`lit.nim`:

```nim
import std/syncio

proc f(x: float): string = "float"
proc f(x: float32): string = "float32"

echo f(3)
echo 1 / 3
let b: float = 1 / 3
echo b
```

```
nimony c --nimcache:nc -o:lit lit.nim && ./lit
```

## Actual

```
float32
0.3333333432674408
0.3333333432674408
```

## Expected

Either an ambiguity error for `f(3)` and `1 / 3` (as the overload resolution rules say), or `float` preferred for an integer literal, so that `1 / 3` is `0.3333333333333333` as in Nim 2.

Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`; none of them resolves overloads).

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/335
