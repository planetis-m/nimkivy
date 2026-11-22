A closure capturing the loop variable of `for id in ["a", "b", "c"]` produces invalid C: `nimStrWasMoved` gets a `string**`

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/351 (crash, phase:hexer-closures, found:llm-agents). Companion: #350.

Nimony 0.6.3, commit `88d04ab0` (current master), Linux amd64, C backend (`nimony c`).

A closure that captures the loop variable of `for id in ["a", "b", "c"]` (an array of strings) produces C that gcc rejects: `nimStrWasMoved` is passed a `string**` where it expects a `string*`.

## Reproduction

Save the file in an empty directory and run the command below.

`strs.nim`:

```nim
import std/syncio
var cbs: seq[proc () {.closure.}] = @[]
for id in ["a", "b", "c"]:
  cbs.add proc () {.closure.} = echo id
for cb in cbs: cb()
```

```
nimony c -r --nimcache:nc strs.nim
```

## Actual

```
nc/c/<hash>/<hash>.c: In function ‘X60Qini_0_<hash>’:
nc/c/<hash>/<hash>.c:828:21: error: passing argument 1 of ‘nimStrWasMoved’ from incompatible pointer type [-Wincompatible-pointer-types]
note: expected ‘string_0_sysvq0asl *’ but argument is of type ‘string_0_sysvq0asl **’
nifmake: command failed (exit code 1): gcc -c ... <hash>.c
```

## Expected

It compiles and each closure prints a value `id` had in the loop body (`a b c`, or `c c c` if the iterations share one variable).

## Notes

- With `for i in 0 ..< 3` (an `int` loop variable) the same program compiles but prints a value the loop variable never had: companion issue.
- The loop variable over an array of strings is a `lent string`; capturing it seems to put the address of the string into the environment, and the cleanup then treats that address as the string.
