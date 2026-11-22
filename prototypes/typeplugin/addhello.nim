## A type plugin that adds a proc to the module declaring its type: the shape
## a property type plugin needs (accessors and setters next to the type).

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
