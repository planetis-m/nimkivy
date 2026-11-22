A `sink` ref parameter captured by a closure is never freed: the closure environment's `=destroy` skips the captured field

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/348 (labels: miscompile, phase:hexer-closures, found:llm-agents)

Nimony 0.6.3, commit `88d04ab0`, Linux amd64, C backend (`nimony c`). Master (`9fa64ee4`, one commit ahead, a C++ `const` change) not checked.

When a routine captures one of its `sink` parameters in a closure, the object the parameter refers to is never freed: one reference is lost per call. The same routine with a plain parameter frees it. It happens with `--mm:atomicArc` (the default), `arc` and `orc`, and with `{.feature: "v2".}`. Under `--mm:orc` a `GC_fullCollect()` before the second `echo` changes nothing (also 32000 bytes).

## Reproduction

Save the file in an empty directory and run the commands shown under Actual.

`sinkcapture.nim`:

```nim
import std/syncio

type
  Node = ref object
    data: int

proc useSink(n: sink Node) =
  let p = proc (): int {.closure.} = n.data
  discard p()

proc usePlain(n: Node) =
  let p = proc (): int {.closure.} = n.data
  discard p()

let before = getOccupiedMem()
for i in 0 ..< 1000:
  usePlain(Node(data: i))
echo "plain parameter: ", getOccupiedMem() - before, " bytes still allocated"

let before2 = getOccupiedMem()
for i in 0 ..< 1000:
  useSink(Node(data: i))
echo "sink parameter: ", getOccupiedMem() - before2, " bytes still allocated"
```

## Actual

```
$ nimony c -r --mm:atomicArc --nimcache:nc_atomicArc sinkcapture.nim
plain parameter: 32 bytes still allocated
sink parameter: 16000 bytes still allocated
```

```
$ nimony c -r --mm:arc --nimcache:nc_arc sinkcapture.nim
plain parameter: 32 bytes still allocated
sink parameter: 16000 bytes still allocated
```

```
$ nimony c -r --mm:orc --nimcache:nc_orc sinkcapture.nim
plain parameter: 32 bytes still allocated
sink parameter: 32000 bytes still allocated
```

All 1000 `Node`s passed to `useSink` stay allocated (16 bytes each with `arc`, 32 with `orc`'s second header word).

## Expected

About the same as the plain parameter: each `Node` is freed when the closure environment that captured it is freed, at the end of `useSink`.

## Cause

In the generated C (`nc_arc/c/<hash>/sin4b9tm71.c`), `useSink` moves `n` into the environment (`env.n = n_0`, no increment), which is right for a `sink` parameter, but the environment's destructor does not release the field:

```c
void eQdestroyQ_SuseX53inkX60env0sin4b9tm71_0_sin4b9tm71(useSinkX60Qenv_0_sin4b9tm71* dest_0){
  eQdestroyQ_SX52ootX4fbj0sysvq0asl_0_sysvq0asl((&(*dest_0).Q));}
```

The destructor of `usePlain`'s environment decrements `n` and frees it, then destroys the base. Unverified: the captured field keeps the parameter's type `sink Node`, and the lifter treats a `sink`-typed field as needing no `=destroy` (nor `=trace` under `orc`).

## Notes

Found while measuring nimkivy (Kivy port) under `--mm:orc`: `WindowBase.addWidget(w; widget: sink WidgetBase)` captures `widget` in a closure, so every root widget added to and removed from the window stays allocated with its whole tree (about 550-750 KB per rebuilt kiosk screen set).
