A plugin cannot position an identifier or literal it adds: `addIdent` and the literal procs take no `LineInfo`, and an error at one prints `???`

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/352 (bad-diagnostic, phase:stdlib, found:llm-agents).

Nimony 0.6.3, commit `6ccc8bf8` (current master), Linux amd64, C backend (`nimony c`).

`plugins.nim` gives a position to everything a plugin builds except identifiers and literals: `withTree`, `openTree`, `addSymUse`, `addSymDef` and `addEmptyNode` take a `LineInfo`, but `addIdent`, `addStrLit`, `addIntLit`, `addUIntLit`, `addFloatLit` and `addCharLit` are nifcore's, re-exported without one. A template plugin's output is checked again, and an error at an identifier the plugin added prints `???` instead of a position. A plugin cannot give the identifier the position of the input it is made from: `nimparser` does it with nifcore's `appendLineInfo`, which `plugins` does not export.

## Reproduction

Save both files in an empty directory and run the command below.

`plug.nim`:

```nim
import plugins

proc transform(root: NifCursor): NifBuilder =
  let arg = callArgs(root)
  result = createTree()
  result.withTree StmtsS, arg.info:
    result.withTree CallS, arg.info:
      result.addIdent "undeclaredProc"
      result.addSubtree arg

saveTree transform(loadPluginInput())
```

`app.nim`:

```nim
template gen(x: untyped) {.plugin: "plug".}

gen 1
```

```
nimony c --nimcache:nc app.nim
```

## Actual

```
app.nim(3, 1) Trace: instantiation from here
??? Error: undeclared identifier: 'undeclaredProc'
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --base:. --define:nimNativeAlloc --nimcache:nc --stdcache:<cache>/nimony/stdlib/<hash>/bin/<hash> --optionkey:<key> m --isMain nc/<hash>.p.nif
FAILURE: <nimony>/bin/nifmake --base:. -j run --done:0,50 nc/<hash>.build.nif
```

## Expected

The error at a position of the input, for example `app.nim(3, 5) Error: undeclared identifier: 'undeclaredProc'`: `addIdent` (and the literal procs) taking a `LineInfo`, as `addSymUse` and `addEmptyNode` do, so a plugin can position what it adds at the node it comes from.

## Notes

A plugin that generates names (`bindX` from `onX`, `initX` from a default's `x`) has no way to position them other than writing Nim text and parsing it with `nimparser.parseStmt`/`parseExpr`.
