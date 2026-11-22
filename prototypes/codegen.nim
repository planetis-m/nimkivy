## Code generation helpers shared by the prototype plugins: generated code is
## written as Nim text with placeholder names, parsed with `nimparser`, and
## copied with the placeholders replaced by names and input subtrees.

import std/strutils
import plugins, nimparser

type
  Subst* = object
    ## The replacements: `Owner` becomes `owner`; with a non-empty `prop`,
    ## an identifier starting with `prop` or containing `Prop` gets the
    ## property's name there; an identifier equal to a key of `trees`
    ## becomes that subtree.
    owner*: string
    prop*: string
    trees*: seq[(string, NifCursor)]

proc capital*(s: string): string =
  result = s
  if result.len > 0: result[0] = toUpperAscii(result[0])

proc rename*(s: Subst; id: string): string =
  # `Owner` is the type; `prop...` and `...Prop...` carry the property name.
  if id == "Owner" and s.owner.len > 0: return s.owner
  if s.prop.len == 0: return id
  if id.startsWith("prop"): return s.prop & id.substr(4)
  let i = id.find("Prop")
  if i >= 0: return id.substr(0, i - 1) & capital(s.prop) & id.substr(i + 4)
  result = id

proc emit*(dest: var NifBuilder; n: var NifCursor; s: Subst) =
  ## Copies `n` with the placeholders of `s` replaced, and advances it.
  case n.kind
  of Ident:
    let id = n.identText
    for (key, tree) in s.trees:
      if key == id:
        dest.addSubtree tree
        skip n
        return
    let renamed = s.rename(id)
    if renamed == id:
      dest.takeTree n          # keeps the token's position
    else:
      # The plugin API has no `addIdent` with a position: a renamed
      # identifier has none, and an error at it prints `???`.
      dest.addIdent renamed
      skip n
  of TagLit:
    dest.copyInto(n):
      while n.hasMore:
        emit(dest, n, s)
  else:
    dest.takeTree n

proc emitStmts*(dest: var NifBuilder; code: string; s: Subst; info: LineInfo) =
  ## Parses `code` and emits its statements with `s` applied.
  let parsed = parseStmt(code, info)
  var c = firstChild(parsed)
  while c.hasMore:
    emit(dest, c, s)

proc emitFields*(dest: var NifBuilder; fields: string; s: Subst; info: LineInfo) =
  ## Emits the fields of `type Owner = object` + `fields` with `s` applied.
  let parsed = parseStmt("type Owner = object\n" & fields, info)
  let decl = asTypeDecl(firstChild(parsed))
  var f = firstChild(decl.body)
  skip f                       # the base type slot
  while f.hasMore:
    emit(dest, f, s)


proc handleTree*(sym: SymId; info: LineInfo): NifBuilder =
  ## A one-token tree that uses the generated symbol `sym` at `info`.
  result = createTree()
  result.addSymUse sym, info
