## The `properties` plugin: Kivy properties and events as typed fields and
## procs (`props.nim` documents the block and what it generates).
##
## Input: `(stmts properties (stmts (type ...)...))`, the untyped block of the
## `properties:` template. Output: the types with storage and observer fields
## in place of the property fields, then per type the accessors, setters,
## bind/unbind procs, dispatchers, default handlers (base methods), Animation
## tracks (a `Track` subtype per numeric property) and the `initProps` chain,
## then the block's other statements as they are.
##
## Observer order is Kivy's: a ReferenceList or alias binds a trigger into
## each property it depends on when it is first used (read, set, bound or
## dispatched), or, for an `eager` alias with dependencies, when the
## instance is initialised; the `handler`s are bound after the eager links.
##
## The output is built node by node, by the modules in `properties/`, each
## importing only the ones before it: `reader` reads the block; `syntax`
## builds Nim syntax trees; `common` builds what the kinds share; `plain`,
## `refs`, `alias` and `event` build one kind each, `tracks` the Animation
## tracks and `initchain` the `initProps` chain.

import plugins
import trees
import properties/[reader, common, plain, refs, alias, event, tracks, initchain]

proc emitTypeDecl(dest: var NifBuilder; t: TypeInfo) =
  let decl = asTypeDecl(t.decl)
  dest.withTree TypeS, t.info:
    dest.addSubtree decl.name
    dest.addSubtree decl.exported
    dest.addSubtree decl.typevars
    dest.addEmptyNode t.info   # the `defaults` pragma is consumed here
    var body = decl.body
    let isRef = body.typeKind == RefT
    if isRef:
      dest.openTree(body.tagId, body.info)
      body = firstChild(body)
    dest.withTree ObjectT, body.info:
      var f = firstChild(body)
      dest.takeTree f          # the base type
      while f.hasMore:
        let local = asLocal(f)
        if local.pragmas.kind != TagLit:
          dest.addSubtree f    # a plain field
        else:
          let p = t.props[t.findProp(local.name.identText)]
          case p.kind
          of kProp: dest.emitPlainFields p
          of kRefs: dest.emitRefsFields p
          of kAlias: dest.emitAliasFields p
          of kEvent: dest.emitEventFields p
        skip f
    if isRef:
      dest.closeTree()

proc emitProcs(dest: var NifBuilder; t: TypeInfo; userMethods: seq[string]) =
  # `userMethods`: "Owner.name" of the methods the block declares; a default
  # handler the block declares is not generated.
  for p in t.props:
    case p.kind
    of kProp: dest.emitPlain p
    of kRefs: dest.emitRefs p
    of kAlias: dest.emitAlias p
    of kEvent: dest.emitEvent p, t.name & ".on" & capital(p.name) notin userMethods
    if p.handler and t.name & "." & changedHandler(p) notin userMethods:
      dest.emitChangedHandler p
    if animatable(p):
      dest.emitTrack p

proc transform(root: NifCursor): NifBuilder =
  var body = callArgs(root)
  if body.stmtKind != StmtsS:
    return errorTree("properties: unsupported syntax", root)
  var err = createTree()
  let b = readBlock(body, err)
  if not err.isEmpty: return err
  result = createTree()
  result.withTree StmtsS, root.info:
    for t in b.types:
      result.emitTypeDecl(t)
    for t in b.types:
      result.emitProcs(t, b.userMethods)
      result.emitInit(t)
    for r in b.rest:
      result.addSubtree r

saveTree transform(loadPluginInput())
