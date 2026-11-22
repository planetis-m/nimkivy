A type plugin that adds a proc to the module declaring its type: the proc cannot read the type's fields ("undeclared field"), and calling it from another module crashes nimsem (`sigmatch.nim(307, 3) res.status == LacksNothing`)

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

`doc/plugins.md` says a type plugin receives the whole typed module and "must return the full module". Its output is checked again (a proc parsed with `nimparser` comes back fully typed), but a declaration the plugin adds to the module that declares the type does not work: a field access in the added proc is "undeclared field", and an added proc without a field access is written as `hello.0.` (no module suffix) in the module's `.s.nif` and its index, and a call from another module crashes nimsem.

This is what a type plugin needs to generate accessors next to a type (the use case: typed properties with setters that dispatch to observers).

## Reproduction 1: the added proc reads a field

Save the three files in an empty directory and run the command below.

`addhello.nim` (the plugin):

```nim
import plugins, nimparser

const added = "proc hello*(t: Thing): int = t.x + 41"

proc declares(n: NifCursor; sym: SymId): bool =
  # Whether this module is the one that declares the triggering type.
  result = false
  for c in n.children:
    if c.stmtKind == TypeS and asTypeDecl(c).name.kind == SymbolDef and
        asTypeDecl(c).name.symId == sym:
      return true

proc tr(n: NifCursor; sym: SymId): NifBuilder =
  result = createTree()
  result.withTree StmtsS, n.info:
    for c in n.children:
      result.addSubtree c
    if declares(n, sym):
      let code = parseStmt(added, n.info)
      for c in code.children:
        result.addSubtree c

let input = loadPluginInput()
let types = loadTypeDefinitions()
saveTree tr(input, firstChild(types).symId)
```

`thing.nim`:

```nim
type
  Thing* {.plugin: "addhello".} = object
    x*: int

proc newThing*(): Thing = Thing(x: 1)
```

`app.nim`:

```nim
import std/syncio
import thing

echo hello(newThing())
```

```
nimony c -r --nimcache:nc app.nim
```

## Actual 1

```
thing.nim(1, 1) Error: undeclared field: 'x' for type Thing
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:AFDAA66A71115EA29948A0E3A3D327162A8EAF17 m <nimcache>/<hash>.p.nif
```

## Reproduction 2: the added proc reads no field

The same, in a new empty directory, with this `addhello.nim` (only `added` differs):

```nim
import plugins, nimparser

const added = "proc hello*(t: Thing): int = 42"

proc declares(n: NifCursor; sym: SymId): bool =
  # Whether this module is the one that declares the triggering type.
  result = false
  for c in n.children:
    if c.stmtKind == TypeS and asTypeDecl(c).name.kind == SymbolDef and
        asTypeDecl(c).name.symId == sym:
      return true

proc tr(n: NifCursor; sym: SymId): NifBuilder =
  result = createTree()
  result.withTree StmtsS, n.info:
    for c in n.children:
      result.addSubtree c
    if declares(n, sym):
      let code = parseStmt(added, n.info)
      for c in code.children:
        result.addSubtree c

let input = loadPluginInput()
let types = loadTypeDefinitions()
saveTree tr(input, firstChild(types).symId)
```

and the same `thing.nim` and `app.nim` as above.

```
nimony c -r --nimcache:nc app.nim
```

## Actual 2

```
assertions.nim(38)       raiseAssert
Error: unhandled exception: sigmatch.nim(307, 3) `res.status == LacksNothing`  [AssertionDefect]
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<stdcache> --optionkey:AFDAA66A71115EA29948A0E3A3D327162A8EAF17 m --isMain <nimcache>/<hash>.p.nif
```

`thing.nim`'s `.s.nif` holds `(proc :hello.0. x . . ...)` and its index `(x hello.0. 204)`, where the module's own procs are `newThing.0.<suffix>`. With `Thing* = ref object` instead of `object`, Reproduction 2 fails the same way.

## Expected

Both print `42`: the added proc is a top-level declaration of `thing.nim`, typed like `newThing`, exported and callable from `app.nim`. If a type plugin is not meant to add declarations, `doc/plugins.md` should say so and the compiler should report it.

## Notes

- `{.feature: "v2".}` in `thing.nim` gives the same error.
- The plugin also runs for `app.nim` only when `app.nim` names `Thing`; with `let t = newThing()` (the type inferred) it does not run there. A plugin that rewrites uses (`t.x = 7`) would miss such modules. Not part of this report; `doc/plugins.md` says "every module that uses the type".
- Unverified: the type-plugin loop in `semmain.nim` runs `semcheckCore` again with the original parsed module (`n0`) for phase 1, so top-level symbols the plugin added are not registered.
- Not checked: other backends.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/336
