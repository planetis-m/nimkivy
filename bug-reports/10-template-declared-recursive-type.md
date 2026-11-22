A type declared by a module-level template that refers to itself through `seq`: as `ref object` it crashes shoggoth ("could not find symbol: Node.Obj.0"), as `object` it is "undeclared identifier: Node" in its own field

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

A type whose field is a `seq` of the type itself compiles when declared directly, but not when the declaration comes from a template expanded at module level (a plain template or a template plugin): the `ref object` form passes sem and then shoggoth aborts with `[Bug] could not find symbol`; the `object` form reports the type as undeclared inside its own field and then `got: Node but wanted: Node` in `seqimpl.nim`.

## Reproduction

Save each file in an empty directory and run the command shown under Actual.

`tree.nim`:

```nim
import std/syncio

template declare(body: untyped) = body

declare:
  type
    Node = ref object
      kids: seq[Node]

let n = Node(kids: @[])
echo n.kids.len
```

`tree2.nim`:

```nim
import std/syncio

template declare(body: untyped) = body

declare:
  type
    Node = object
      kids: seq[Node]

let n = Node(kids: @[])
echo n.kids.len
```

`tree3.nim` (control, no template):

```nim
import std/syncio

type
  Node = ref object
    kids: seq[Node]

let n = Node(kids: @[])
echo n.kids.len
```

## Actual

```
$ nimony c -r --nimcache:nc tree.nim
No stack traceback available
[Bug] could not find symbol: Node.Obj.0.treotj3m41
nifmake: command failed (exit code 1): <nimony>/bin/shoggoth c --bits:64 --cpu:le --os:Linux --stdcache:<stdcache> --flags:br --isMain --app:console --outdir:<nimcache>/c/<hash> <nimcache>/<hash>.s.nif
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 <nimcache>/c/<hash>.final.build.nif
```

```
$ nimony c -r --nimcache:nc tree2.nim
tree2.nim(5, 1) Trace: instantiation from here
tree2.nim(8, 17) Error: undeclared identifier: Node
<nimony>/lib/std/system/seqimpl.nim(138, 1) Trace: instantiation from here
<nimony>/lib/std/system/seqimpl.nim(145, 32) Error: type mismatch: got: Node but wanted: Node
<nimony>/lib/std/system/seqimpl.nim(208, 1) Trace: instantiation from here
<nimony>/lib/std/system/seqimpl.nim(210, 11) Trace: instantiation from here
<nimony>/lib/std/system/seqimpl.nim(205, 50) Error: type mismatch: got: Node but wanted: Node
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:AFDAA66A71115EA29948A0E3A3D327162A8EAF17 m --isMain <nimcache>/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 <nimcache>/<hash>.build.nif
```

```
$ nimony c -r --nimcache:nc tree3.nim
0
```

## Expected

`tree.nim` and `tree2.nim` print `0`, as `tree3.nim` does.

## Notes

- The same with `{.feature: "v2".}` and with `{.untyped.}` on the template.
- The same with a template plugin that returns its block unchanged (`template declare(body: untyped) {.plugin: "p".}`), and when the type is `ref object of RootObj` and is used from another module.
- Related: #290 (a type declared by a module-level template is undeclared in a later proc signature).
- Not checked: other backends.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/337
