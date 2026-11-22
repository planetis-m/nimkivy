`doc/tags.md` says the `acyclic` pragma is "currently ignored", but `{.acyclic.}` takes a type out of the cycle collector

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/349 (labels: bug, phase:hexer-arc, found:llm-agents)

Nimony 0.6.3, commit `88d04ab0`, Linux amd64, C backend (`nimony c`). Master (`9fa64ee4`, one commit ahead, a C++ `const` change) not checked.

`doc/tags.md` (and the doc comment of `AcyclicP` in `src/models/nimony_tags.nim`) describe `(acyclic)` as "`acyclic` pragma (currently ignored)". It is not ignored: under `--mm:orc` a type marked `{.acyclic.}` is never handed to the cycle collector, so a cycle of such objects is not freed by `GC_fullCollect()`, while the same type without the pragma is. `doc/stdlib.md` ("`{.acyclic.}` on a type exempts it") describes the actual behaviour.

## Reproduction

Save the file in an empty directory and run the command shown under Actual.

`acyclic.nim`:

```nim
import std/syncio

type
  Plain = ref object
    next: nil Plain
  Acy {.acyclic.} = ref object
    next: nil Acy

proc cyclePlain() =
  let a = Plain(next: nil)
  a.next = Plain(next: a)

proc cycleAcy() =
  let a = Acy(next: nil)
  a.next = Acy(next: a)

var before = getOccupiedMem()
for i in 0 ..< 1000: cyclePlain()
GC_fullCollect()
echo "without {.acyclic.}: ", getOccupiedMem() - before, " bytes left"
before = getOccupiedMem()
for i in 0 ..< 1000: cycleAcy()
GC_fullCollect()
echo "with {.acyclic.}: ", getOccupiedMem() - before, " bytes left"
```

## Actual

```
$ nimony c -r --mm:orc --nimcache:nc acyclic.nim
without {.acyclic.}: 32 bytes left
with {.acyclic.}: 64032 bytes left
```

The 1000 two-object cycles of `Acy` stay allocated: the pragma took effect (the generated `=destroy` of `Acy` uses `arcDec`, the one of `Plain` `nimDecRefCyclic` with a cell operation).

## Expected

Either the documentation says what the pragma does (as `doc/stdlib.md` does), or, if it is meant to be ignored, both types behave alike. The behaviour matches `doc/stdlib.md`, so the `tags.md` entry and the `AcyclicP` doc comment look stale.

## Cause

`src/hexer/lifter.nim`, `isAcyclicDecl`, used by `walksToCycle` and `canFormCycle`, stops the cycle walk at a type declared `{.acyclic.}` (also for a class: the check comes before the RTTI rule). `src/models/nimony_tags.nim` line 371 still says `## \`acyclic\` pragma (currently ignored)`.
