## The `properties` plugin (prototype): Kivy properties and events as typed
## fields and procs.
##
## Input: `(stmts properties (stmts (type ...)...))`, the untyped block of the
## `properties:` template. Each type declares its properties as fields with a
## pragma:
##
## - `x* {.prop.}: float = 0.0`: a property (Numeric, String, Boolean,
##   Object, List, Option and Color properties are all this, with a Nim type)
## - `opacity* {.bounds: 0.0 .. 1.0.}: float = 1.0`: a bounded property
## - `pos* {.refs: (x, y).}: (float, float)`: a ReferenceListProperty of
##   properties declared in the same type
## - `press* {.event.}: proc ()`: an event (its arguments in the proc type)
## - a field without a pragma stays a plain field
##
## and `{.defaults: (name: value, ...).}` on the type overrides inherited
## defaults. Other statements in the block (the types' methods) are copied
## after the generated code. Output: the types with storage and observer fields, then the
## accessors, setters, bind/unbind procs, event dispatchers, default event
## handlers (base methods) and `initProps`.
##
## The generated code is written as Nim text below with placeholder names
## (`Owner`, `Base`, `PropT`, `DefaultV`, `prop...`, `...Prop...`), parsed
## once per use, and copied with the placeholders replaced (`codegen`).

import std/[strutils, syncio]
import plugins, nimparser
import ../codegen

type
  Kind = enum
    kPlain, kBounds, kRefs, kEvent

  Prop = object
    name: string
    exported: bool
    kind: Kind
    typ: NifCursor             # the field's type
    default: NifCursor         # its default value; exhausted when none
    lo, hi: NifCursor          # kBounds
    refs: seq[string]          # kRefs: the referenced properties
    args: seq[NifCursor]       # kEvent: the argument types
    info: LineInfo

  TypeInfo = object
    name: string
    decl: NifCursor            # the input `(type ...)`
    base: NifCursor            # the base type in `ref object of Base`
    props: seq[Prop]
    overrides: seq[(string, NifCursor)]   # {.defaults: (name: value).}
    info: LineInfo


# ------------------------------------------------------------------ reading the block

proc pragmaName(p: NifCursor): string =
  # `prop` or `(kv refs ...)`: the pragma's name.
  if p.kind == Ident: result = p.identText
  elif p.kind == TagLit and p.tagText == "kv": result = firstChild(p).identText
  else: result = ""

proc pragmaValue(p: NifCursor): NifCursor =
  var c = firstChild(p)
  skip c
  result = c

proc readField(f: NifCursor; props: var seq[Prop]; err: var NifBuilder) =
  # (fld name export pragmas type default)
  let local = asLocal(f)
  if local.pragmas.kind != TagLit:
    return                     # a plain field
  let p = firstChild(local.pragmas)
  var prop = Prop(name: local.name.identText, exported: local.exported.kind != DotToken,
    kind: kPlain, typ: local.typ, default: local.val, info: f.info)
  case pragmaName(p)
  of "prop": prop.kind = kPlain
  of "bounds":
    let range = pragmaValue(p)
    if range.kind != TagLit or range.tagText != "infix":
      err = errorTree("bounds expects `low .. high`", p)
      return
    var r = firstChild(range)
    skip r                     # `..`
    prop.lo = r
    skip r
    prop.hi = r
    prop.kind = kBounds
  of "refs":
    let t = pragmaValue(p)
    for c in t.children:
      prop.refs.add c.identText
    prop.kind = kRefs
  of "event":
    if local.typ.kind != TagLit or local.typ.tagText != "proctype":
      err = errorTree("an event's type is `proc (arguments)`", local.typ)
      return
    var pt = firstChild(local.typ)
    for _ in 0 ..< 4: skip pt  # name, export, pattern, typevars
    for param in pt.children:
      prop.args.add asLocal(param).typ
    prop.kind = kEvent
  else:
    err = errorTree("unknown property pragma (prop, bounds, refs, event)", p)
    return
  props.add prop

proc readType(t: NifCursor; err: var NifBuilder): TypeInfo =
  let decl = asTypeDecl(t)
  result = TypeInfo(name: decl.name.identText, decl: t, info: t.info)
  if decl.pragmas.kind == TagLit:
    for p in decl.pragmas.children:
      if pragmaName(p) == "defaults":
        for kv in pragmaValue(p).children:
          var c = firstChild(kv)
          let name = c.identText
          skip c
          result.overrides.add (name, c)
  var body = decl.body
  if body.typeKind == RefT: body = firstChild(body)
  if body.typeKind != ObjectT:
    err = errorTree("properties expects `ref object of Base`", t)
    return
  var f = firstChild(body)
  result.base = f
  skip f
  while f.hasMore:
    readField(f, result.props, err)
    skip f

proc findProp(t: TypeInfo; name: string): int =
  result = -1
  for i in 0 ..< t.props.len:
    if t.props[i].name == name: return i

# ------------------------------------------------------------------ code templates

const
  plainFields = """
  propStore: PropT
  propObs: Observers[proc (v: PropT) {.closure.}]
"""
  refsFields = """
  propStore: PropT
  propObs: Observers[proc (v: PropT) {.closure.}]
  propLinked: bool
  propStop: bool
  propValid: bool
"""
  eventFields = """
  propObs: Observers[proc ($1): bool {.closure.}]
"""

  plainProcs = """
proc prop*(w: Owner): PropT {.inline.} =
  w.propStore
proc `prop=`*(w: Owner; v: PropT) =
  $1
  if w.propStore != v:
    w.propStore = v
    let value = w.propStore
    for cb in w.propObs.live: cb(value)
proc bindProp*(w: Owner; cb: proc (v: PropT) {.closure.}): Binding =
  w.propObs.add(cb)
proc unbindProp*(w: Owner; b: Binding) =
  w.propObs.remove(b)
proc initProp*(w: Owner; v: PropT) =
  w.propStore = v
"""
  boundsCheck = """if v < LowV or v > HighV:
    quit "Owner.prop: " & $v & " is out of its bounds"
"""

  # ReferenceListProperty: Kivy links it on first use, binding a trigger to
  # each reference, so its place among their observers is the same.
  refsProcs = """
proc triggerProp(w: Owner) =
  if not w.propStop:
    w.propStore = $1
    w.propValid = true
    let value = w.propStore
    for cb in w.propObs.live: cb(value)
proc linkProp(w: Owner) =
  if not w.propLinked:
    w.propLinked = true
$2
proc prop*(w: Owner): PropT =
  w.linkProp()
  w.propStore = $1
  w.propValid = true
  w.propStore
proc `prop=`*(w: Owner; v: PropT) =
  w.linkProp()
  if w.propValid and w.propStore == v: return
  w.propStop = true
$3
  w.propStop = false
  w.propStore = v
  w.propValid = true
  let value = w.propStore
  for cb in w.propObs.live: cb(value)
proc bindProp*(w: Owner; cb: proc (v: PropT) {.closure.}): Binding =
  w.linkProp()
  w.propObs.add(cb)
proc unbindProp*(w: Owner; b: Binding) =
  w.propObs.remove(b)
"""

  eventProcs = """
proc bindProp*(w: Owner; cb: proc ($4): bool {.closure.}): Binding =
  w.propObs.add(cb)
proc unbindProp*(w: Owner; b: Binding) =
  w.propObs.remove(b)
method onProp*(w: Owner$1): bool {.base.} =
  false
proc dispatchProp*(w: Owner$1): bool =
  result = false
  for cb in w.propObs.liveReversed:
    if not result: result = cb($3)
  if not result: result = w.onProp($3)
"""

proc fill(code: string; args: openArray[string]): string =
  ## `code` with `$1`, `$2`, ... replaced by `args`.
  result = code
  for i in 0 ..< args.len:
    result = result.replace("$" & $(i + 1), args[i])

proc exportAs(code: string; exported: bool): string =
  if exported: code else: code.replace("*(", "(")

# ------------------------------------------------------------------ generating

proc eventArgs(p: Prop): (string, string, string, string, seq[(string, NifCursor)]) =
  # The parameters after `w`, the arguments after `w`, the arguments alone,
  # the parameters alone, and the type placeholders.
  var params, args, alone, paramsAlone = ""
  var trees: seq[(string, NifCursor)] = @[]
  for i in 0 ..< p.args.len:
    params.add "; a" & $i & ": ArgT" & $i
    args.add ", a" & $i
    if i > 0:
      alone.add ", "
      paramsAlone.add "; "
    alone.add "a" & $i
    paramsAlone.add "a" & $i & ": ArgT" & $i
    trees.add ("ArgT" & $i, p.args[i])
  result = (params, args, alone, paramsAlone, trees)

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
          let i = t.findProp(local.name.identText)
          let p = t.props[i]
          var s = Subst(owner: t.name, prop: p.name, trees: @[("PropT", p.typ)])
          case p.kind
          of kPlain, kBounds: dest.emitFields(plainFields, s, p.info)
          of kRefs: dest.emitFields(refsFields, s, p.info)
          of kEvent:
            let (_, _, _, paramsAlone, trees) = eventArgs(p)
            for tr in trees: s.trees.add tr
            dest.emitFields(fill(eventFields, [paramsAlone]), s, p.info)
        skip f
    if isRef:
      dest.closeTree()

proc emitProcs(dest: var NifBuilder; t: TypeInfo; err: var NifBuilder) =
  for p in t.props:
    var s = Subst(owner: t.name, prop: p.name, trees: @[("PropT", p.typ)])
    case p.kind
    of kPlain:
      dest.emitStmts(exportAs(fill(plainProcs, [""]), p.exported), s, p.info)
    of kBounds:
      s.trees.add ("LowV", p.lo)
      s.trees.add ("HighV", p.hi)
      let check = boundsCheck.replace("Owner.prop", t.name & "." & p.name)
      dest.emitStmts(exportAs(fill(plainProcs, [check]), p.exported), s, p.info)
    of kRefs:
      var tup = "("
      var links, sets = ""
      for i in 0 ..< p.refs.len:
        let r = p.refs[i]
        let k = t.findProp(r)
        if k < 0:
          err = errorTree("refs: " & r & " is not a property of " & t.name, t.decl)
          return
        if i > 0: tup.add ", "
        tup.add "w." & r & "Store"
        links.add "    discard w." & r & "Obs.add(proc (v: RefT" & $i &
          ") {.closure.} = w.triggerProp())\n"
        sets.add "  w." & r & " = v[" & $i & "]\n"
        s.trees.add ("RefT" & $i, t.props[k].typ)
      tup.add ")"
      dest.emitStmts(exportAs(fill(refsProcs, [tup, links, sets]), p.exported), s, p.info)
    of kEvent:
      let (params, args, alone, paramsAlone, trees) = eventArgs(p)
      for tr in trees: s.trees.add tr
      dest.emitStmts(exportAs(fill(eventProcs, [params, args, alone, paramsAlone]),
        p.exported), s, p.info)

proc emitInit(dest: var NifBuilder; t: TypeInfo) =
  # initProps: the base's defaults, this type's, then the overrides; no
  # dispatch, as Kivy sets defaults before any observer exists.
  var code = "proc initProps*(w: Owner) =\n"
  var s = Subst(owner: t.name, prop: "", trees: @[])
  var isRoot = t.base.kind == Ident and t.base.identText == "RootObj"
  if not isRoot:
    code.add "  initProps(Base(w))\n"
    s.trees.add ("Base", t.base)
  else:
    code.add "  discard\n"
  for i in 0 ..< t.props.len:
    let p = t.props[i]
    if p.kind in {kPlain, kBounds}:
      if p.default.kind == DotToken:
        code.add "  w." & p.name & "Store = default(PropT" & $i & ")\n"
      else:
        code.add "  w." & p.name & "Store = DefaultV" & $i & "\n"
        s.trees.add ("DefaultV" & $i, p.default)
      s.trees.add ("PropT" & $i, p.typ)
  for i in 0 ..< t.overrides.len:
    let (name, value) = t.overrides[i]
    code.add "  w.init" & capital(name) & "(OverrideV" & $i & ")\n"
    s.trees.add ("OverrideV" & $i, value)
  dest.emitStmts(code, s, t.info)

proc transform(root: NifCursor): NifBuilder =
  var body = callArgs(root)
  if body.stmtKind != StmtsS:
    return errorTree("properties expects a block of type declarations", root)
  var err = createTree()
  var types: seq[TypeInfo] = @[]
  var rest: seq[NifCursor] = @[]
  for t in body.children:
    if t.stmtKind == TypeS:
      types.add readType(t, err)
      if not err.isEmpty: return err
    else:
      rest.add t               # methods and procs of these types, kept as is
  result = createTree()
  result.withTree StmtsS, root.info:
    for t in types:
      result.emitTypeDecl(t)
    for t in types:
      result.emitProcs(t, err)
      result.emitInit(t)
    for r in rest:
      result.addSubtree r
  if not err.isEmpty: return err

saveTree transform(loadPluginInput())
