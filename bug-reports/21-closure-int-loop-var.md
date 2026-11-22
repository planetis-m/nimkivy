Closures capturing an int `for` loop variable all see a value the loop never had: `for i in 0 ..< 3` prints `3 3 3`

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/350 (miscompile, phase:hexer-closures, found:llm-agents). Companion: #351.

Nimony 0.6.3, commit `88d04ab0` (current master), Linux amd64, C backend (`nimony c`).

Closures created in a `for i in 0 ..< 3` loop that capture `i` all print `3`, a value the loop variable never has in the loop body. Closures capture by reference (language.md, Closures), so all three seeing one shared variable would give its last value, `2`; what they see is the iterator's counter after the loop ended.

## Reproduction

Save the file in an empty directory and run the command below.

`ints.nim`:

```nim
import std/syncio
var cbs: seq[proc () {.closure.}] = @[]
for i in 0 ..< 3:
  cbs.add proc () {.closure.} = echo i
for cb in cbs: cb()
```

```
nimony c -r --nimcache:nc ints.nim
```

## Actual

```
3
3
3
```

## Expected

Each closure sees a value `i` had in the body: `0 1 2` if each iteration has its own `i`, or `2 2 2` if the iterations share one variable. Never `3`, which is outside `0 ..< 3`.

## Notes

- Related, different: #191 (a closure capturing a read-only loop variable may write it).
- The same loop over `["a", "b", "c"]` does not compile at all: see the companion issue on string loop variables.
