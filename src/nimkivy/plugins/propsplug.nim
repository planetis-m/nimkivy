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
## The generated code is written as Nim text below with placeholder names
## (`Owner`, `Base`, `PropT`, `prop...`, `...Prop...`), parsed once per use,
## and copied with the placeholders replaced (`codegen`).
##
## Observer order is phase 1's (`event.nim`, `properties.nim`), which is
## Kivy's: a ReferenceList or alias binds a trigger into each property it
## depends on when it is first used (read, set, bound or dispatched), or, for
## an `eager` alias with dependencies, when the instance is initialised; the
## `handler`s are bound after the eager links.

import std/[algorithm, strutils]
import plugins, nimparser
import codegen

type
  Kind = enum
    kProp, kRefs, kAlias, kEvent

  Prop = object
    name: string
    exported: bool
    kind: Kind
    typ: NifCursor             # the field's type
    default: NifCursor         # its default value; a DotToken when none
    bounded: bool
    lo, hi: NifCursor          # bounds
    color: bool
    varlist: int               # 0, or the length 2 or 4
    always, handler, cache, eager: bool
    refs: seq[string]          # kRefs: the referenced properties
    deps: seq[string]          # kAlias: the properties it depends on
    getter, setter: NifCursor  # kAlias; setter is a DotToken when read-only
    hasSetter: bool
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

proc names(v: NifCursor): seq[string] =
  # `x` or `(x, y)`: the identifiers.
  result = @[]
  if v.kind == Ident:
    result.add v.identText
  else:
    for c in v.children: result.add c.identText

proc readPragma(prop: var Prop; p: NifCursor; local: Local; err: var NifBuilder) =
  case pragmaName(p)
  of "prop": prop.kind = kProp
  of "bounds":
    let range = pragmaValue(p)
    if range.kind != TagLit or range.tagText != "infix":
      err = errorTree("bounds expects `low .. high`", p)
    else:
      var r = firstChild(range)
      skip r                   # `..`
      prop.lo = r
      skip r
      prop.hi = r
      prop.bounded = true
  of "refs":
    prop.refs = names(pragmaValue(p))
    prop.kind = kRefs
  of "alias":
    let v = pragmaValue(p)
    if v.kind == Ident:
      prop.getter = v
    else:
      var c = firstChild(v)
      prop.getter = c
      skip c
      if c.hasMore:
        prop.setter = c
        prop.hasSetter = true
    prop.kind = kAlias
  of "deps": prop.deps = names(pragmaValue(p))
  of "cache": prop.cache = true
  of "eager": prop.eager = true
  of "always": prop.always = true
  of "handler": prop.handler = true
  of "color": prop.color = true
  of "varlist":
    let n = pragmaValue(p)
    if n.kind != IntLit or (n.intValue != 2 and n.intValue != 4):
      err = errorTree("varlist expects 2 or 4", p)
    else:
      prop.varlist = int(n.intValue)
  of "event":
    if local.typ.kind != TagLit or local.typ.tagText != "proctype":
      err = errorTree("an event's type is `proc (arguments)`", local.typ)
    else:
      var pt = firstChild(local.typ)
      for _ in 0 ..< 4: skip pt  # name, export, pattern, typevars
      for param in pt.children:
        prop.args.add asLocal(param).typ
      prop.kind = kEvent
  else:
    err = errorTree("unknown property pragma (prop, bounds, refs, alias, deps, " &
      "cache, eager, always, handler, color, varlist, event)", p)

proc readField(f: NifCursor; props: var seq[Prop]; err: var NifBuilder) =
  # (fld name export pragmas type default)
  let local = asLocal(f)
  if local.pragmas.kind != TagLit:
    return                     # a plain field
  var prop = Prop(name: local.name.identText, exported: local.exported.kind != DotToken,
    kind: kProp, typ: local.typ, default: local.val, info: f.info)
  for p in local.pragmas.children:
    readPragma(prop, p, local, err)
    if not err.isEmpty: return
  if prop.kind != kAlias and (prop.deps.len > 0 or prop.cache or prop.eager):
    err = errorTree("deps, cache and eager go with alias", f)
  elif prop.kind == kEvent and (prop.always or prop.handler):
    err = errorTree("always and handler go with a property, not an event", f)
  elif prop.kind != kProp and (prop.bounded or prop.color or prop.varlist > 0):
    err = errorTree("bounds, color and varlist go with prop", f)
  else:
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
    if not err.isEmpty: return
    skip f

proc findProp(t: TypeInfo; name: string): int =
  result = -1
  for i in 0 ..< t.props.len:
    if t.props[i].name == name: return i

# ------------------------------------------------------------------ code templates

const
  propFields = """
  propStore: PropT
  propObs: Observers[proc (v: PropT) {.closure.}]
"""
  linkedFields = """
  propStore: PropT
  propObs: Observers[proc (v: PropT) {.closure.}]
  propLinked: bool
  propValid: bool
  propStop: bool
"""
  # An alias without `cache` stores nothing (so its type may be a `ref`
  # that has no default value).
  uncachedFields = """
  propObs: Observers[proc (v: PropT) {.closure.}]
  propLinked: bool
"""
  eventFields = """
  propObs: Observers[proc ($1): bool {.closure.}]
"""

  # Shared by every property kind. A dispatch passes a copy of the value: an
  # observer may replace the stored one while the later observers still need
  # it (phase 1, planetis-m/nimony-bugs-llms#334).
  bindProcs = """
proc bindProp*(w: Owner; cb: proc (v: PropT) {.closure.}): Binding =
  $1
  w.propObs.add(cb)
proc unbindProp*(w: Owner; b: Binding) =
  w.propObs.remove(b)
proc dispatchProp*(w: Owner) =
  $1
  let value = w.prop
  for cb in w.propObs.live: cb(value)
"""

  propProcs = """
proc prop*(w: Owner): PropT {.inline.} =
  w.propStore
proc `prop=`*(w: Owner; v: PropT) =
  $1
  if $2w.propStore != v:
    w.propStore = v
    w.dispatchProp()
proc initProp*(w: Owner; v: PropT) =
  w.propStore = v
"""
  boundsCheck = """if v < LowV or v > HighV:
    quitOutOfBounds("Owner.prop", $v)
"""
  colorProcs = """
proc `prop=`*(w: Owner; v: array[3, float]) =
  w.prop = [v[0], v[1], v[2], 1.0]
"""
  varlist4Procs = """
proc `prop=`*(w: Owner; v: float) =
  w.prop = [v, v, v, v]
proc `prop=`*(w: Owner; v: array[1, float]) =
  w.prop = [v[0], v[0], v[0], v[0]]
proc `prop=`*(w: Owner; v: array[2, float]) =
  w.prop = [v[0], v[1], v[0], v[1]]
"""
  varlist2Procs = """
proc `prop=`*(w: Owner; v: float) =
  w.prop = [v, v]
proc `prop=`*(w: Owner; v: array[1, float]) =
  w.prop = [v[0], v[0]]
"""

  # ReferenceListProperty (properties.pyx): linked on first use, when it
  # binds a trigger to each reference, so its place among their observers
  # is Kivy's. Its stored value is invalid until read, set or triggered, so
  # the first set always dispatches, as Kivy's default (the properties
  # themselves) never equals a value.
  refsProcs = """
proc triggerProp(w: Owner) =
  if not w.propStop:
    w.propStore = $1
    w.propValid = true
    w.dispatchProp()
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
  if $4w.propValid and w.propStore == v: return
  w.propStop = true
$3
  w.propStop = false
  w.propStore = v
  w.propValid = true
  let value = w.propStore
  for cb in w.propObs.live: cb(value)
"""
  refsDispatch = """
proc bindProp*(w: Owner; cb: proc (v: PropT) {.closure.}): Binding =
  w.linkProp()
  w.propObs.add(cb)
proc unbindProp*(w: Owner; b: Binding) =
  w.propObs.remove(b)
proc dispatchProp*(w: Owner) =
  w.linkProp()
  let value = w.propStore
  for cb in w.propObs.live: cb(value)
"""

  # AliasProperty (properties.pyx): `propValid` is Kivy's "not
  # alias_initial". Without `cache` nothing is stored, so a dependency's
  # change always dispatches (Kivy compares with its stored None).
  aliasProcs = """
proc linkProp(w: Owner) =
  if not w.propLinked:
    w.propLinked = true
$1
$2"""
  aliasCachedTrigger = """
proc triggerProp(w: Owner) =
  w.linkProp()
  let value = GetterF(w)
  if not w.propValid or w.propStore != value:
    w.propValid = true
    w.propStore = value
    w.dispatchProp()
"""
  # Kivy's trigger reads the value (`get`) before it dispatches.
  aliasTrigger = """
proc triggerProp(w: Owner) =
  w.linkProp()
  discard GetterF(w)
  w.dispatchProp()
"""
  aliasCachedGet = """
proc prop*(w: Owner): PropT =
  w.linkProp()
  if not w.propValid:
    w.propValid = true
    w.propStore = GetterF(w)
  w.propStore
"""
  aliasGet = """
proc prop*(w: Owner): PropT =
  w.linkProp()
  GetterF(w)
"""
  aliasSet = """
proc `prop=`*(w: Owner; v: PropT) =
  w.linkProp()
  if SetterF(w, v):
$1
    w.dispatchProp()
$2
"""
  aliasCacheUpdate = """
    w.propValid = true
    w.propStore = GetterF(w)
"""

  eventProcs = """
proc bindProp*(w: Owner; cb: proc ($4): bool {.closure.}): Binding =
  w.propObs.add(cb)
proc unbindProp*(w: Owner; b: Binding) =
  w.propObs.remove(b)
proc dispatchProp*(w: Owner$1): bool =
  result = false
  for cb in w.propObs.liveReversed:
    if not result: result = cb($3)
  if not result: result = w.onProp($3)
"""

  eventDefault = """
method onProp*(w: Owner$1): bool {.base.} =
  false
"""

  handlerProc = """
method onPropChanged*(w: Owner; v: PropT) {.base.} =
  discard
"""

  # An Animation's track (`props.Track`): `propTo(Owner, v)` animates the
  # property to `v`; `capture` reads its start value on a target, `advance`
  # sets the value at a point of the way. `$1` is the type's track name
  # (`OwnerPropTrack`), `$2` "Owner.prop", which `trackKey` makes the key.
  trackProcs = """
type $1 = ref object of Track
  target: nil Owner
  a, b: PropT
proc propKey*(t: typedesc[Owner]): TrackKey {.inline.} =
  trackKey("$2")
proc propTo*(t: typedesc[Owner]; v: PropT): Track =
  $1(key: trackKey("$2"), target: nil, a: v, b: v)
method capture(t: $1; target: RootRef): Track =
  if target of Owner:
    let w = Owner(target)
    result = $1(key: t.key, target: w, a: w.prop, b: t.b)
  else:
    result = quitWrongTarget("$2")
method advance(t: $1; progress: float) =
  let w = t.target
  if w != nil: w.prop = lerp(t.a, t.b, progress)
method `$`(t: $1): string =
  "$2 -> " & $t.b
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
          let p = t.props[t.findProp(local.name.identText)]
          var s = Subst(owner: t.name, prop: p.name, trees: @[("PropT", p.typ)])
          case p.kind
          of kProp: dest.emitFields(propFields, s, p.info)
          of kRefs: dest.emitFields(linkedFields, s, p.info)
          of kAlias:
            dest.emitFields(if p.cache: linkedFields else: uncachedFields, s, p.info)
          of kEvent:
            let (_, _, _, paramsAlone, trees) = eventArgs(p)
            for tr in trees: s.trees.add tr
            dest.emitFields(fill(eventFields, [paramsAlone]), s, p.info)
        skip f
    if isRef:
      dest.closeTree()

proc linkLine(dep: string): string =
  # Binds the trigger into `dep`'s observers (linking `dep` first).
  "    discard w.bind" & capital(dep) & "(proc (v: typeof(w." & dep &
    ")) {.closure.} = w.triggerProp())\n"

proc isFloat(n: NifCursor): bool =
  n.kind == Ident and n.identText == "float"

proc isNumericType(typ: NifCursor): bool =
  # `float`, `(float, float)`, `array[N, float]` or `seq[float]`, as written:
  # the plugin sees the syntax, not the type, so an alias of these is not
  # recognised (a `color` or `varlist` property is, by its pragma).
  if isFloat(typ):
    return true
  if typ.kind != TagLit:
    return false
  var kids: seq[NifCursor] = @[]
  for c in typ.children: kids.add c
  if typ.tagText == "at":
    result = kids.len >= 2 and kids[0].kind == Ident and
      kids[0].identText in ["array", "seq"] and isFloat(kids[^1])
  else:
    result = kids.len == 2 and isFloat(kids[0]) and isFloat(kids[1])

proc animatable(p: Prop): bool =
  # A property an Animation can move: a settable one of a numeric type.
  let settable = p.kind in {kProp, kRefs} or (p.kind == kAlias and p.hasSetter)
  result = settable and (p.color or p.varlist > 0 or isNumericType(p.typ))

proc emitProcs(dest: var NifBuilder; t: TypeInfo; userMethods: seq[string]) =
  # `userMethods`: "Owner.name" of the methods the block declares; a default
  # handler the block declares is not generated.
  for p in t.props:
    var s = Subst(owner: t.name, prop: p.name, trees: @[("PropT", p.typ)])
    var code = ""
    let always = if p.always: "true or " else: ""
    case p.kind
    of kProp:
      var check = ""
      if p.bounded:
        s.trees.add ("LowV", p.lo)
        s.trees.add ("HighV", p.hi)
        check = boundsCheck.replace("Owner.prop", t.name & "." & p.name)
      code = fill(propProcs, [check, always]) & fill(bindProcs, [""])
      if p.color: code.add colorProcs
      if p.varlist == 4: code.add varlist4Procs
      elif p.varlist == 2: code.add varlist2Procs
    of kRefs:
      var tup = "("
      var links, sets = ""
      for i in 0 ..< p.refs.len:
        let r = p.refs[i]
        if i > 0: tup.add ", "
        tup.add "w." & r
        links.add linkLine(r)
        sets.add "  w." & r & " = v[" & $i & "]\n"
      tup.add ")"
      let unchanged = if p.always: "false and " else: ""
      code = fill(refsProcs, [tup, links, sets, unchanged]) & refsDispatch
    of kAlias:
      s.trees.add ("GetterF", p.getter)
      var links = ""
      for d in p.deps: links.add linkLine(d)
      if links.len == 0: links = "    discard\n"
      code = fill(aliasProcs, [links, if p.cache: aliasCachedTrigger else: aliasTrigger])
      code.add(if p.cache: aliasCachedGet else: aliasGet)
      if p.hasSetter:
        s.trees.add ("SetterF", p.setter)
        let elseDispatch = if p.always: "  else:\n    w.dispatchProp()\n" else: ""
        code.add fill(aliasSet, [if p.cache: aliasCacheUpdate else: "", elseDispatch])
      code.add fill(bindProcs, ["w.linkProp()"])
    of kEvent:
      let (params, args, alone, paramsAlone, trees) = eventArgs(p)
      for tr in trees: s.trees.add tr
      code = fill(eventProcs, [params, args, alone, paramsAlone])
      if t.name & ".on" & capital(p.name) notin userMethods:
        code.add fill(eventDefault, [params])
    if p.handler and t.name & ".on" & capital(p.name) & "Changed" notin userMethods:
      code.add handlerProc
    if animatable(p):
      let what = t.name & "." & p.name
      code.add fill(trackProcs, [t.name & "PropTrack", what])
    dest.emitStmts(exportAs(code, p.exported), s, p.info)

proc emitInit(dest: var NifBuilder; t: TypeInfo) =
  # Phase 1's `initEventDispatcher` order: the defaults (no dispatch, as Kivy
  # sets them before any observer exists), base first, then this type's,
  # then the overrides; then the eager alias links, base first; then the
  # handlers, base first and in name order within a type.
  var s = Subst(owner: t.name, prop: "", trees: @[])
  let isRoot = t.base.kind == Ident and t.base.identText in ["RootObj", "RootRef"]
  let callBase = if isRoot: "  discard\n" else: "  $1(Base(w))\n"
  if not isRoot: s.trees.add ("Base", t.base)
  var values = "proc initPropValues*(w: Owner) =\n" & fill(callBase, ["initPropValues"])
  var eager = "proc linkEagerProps*(w: Owner) =\n" & fill(callBase, ["linkEagerProps"])
  var handlers = "proc bindPropHandlers*(w: Owner) =\n" & fill(callBase, ["bindPropHandlers"])
  var named: seq[string] = @[]
  for i in 0 ..< t.props.len:
    let p = t.props[i]
    if p.kind == kProp:
      if p.default.kind == DotToken:
        values.add "  w." & p.name & "Store = default(PropT" & $i & ")\n"
      else:
        values.add "  w." & p.name & "Store = DefaultV" & $i & "\n"
        s.trees.add ("DefaultV" & $i, p.default)
      s.trees.add ("PropT" & $i, p.typ)
    if p.kind == kAlias and p.eager and p.deps.len > 0:
      eager.add "  w.link" & capital(p.name) & "()\n"
    if p.handler: named.add p.name
  for i in 0 ..< t.overrides.len:
    let (name, value) = t.overrides[i]
    values.add "  w.init" & capital(name) & "(OverrideV" & $i & ")\n"
    s.trees.add ("OverrideV" & $i, value)
  named.sort()
  for name in named:
    let i = t.findProp(name)
    handlers.add "  discard w.bind" & capital(name) & "(proc (v: PropT" & $i &
      ") {.closure.} = w.on" & capital(name) & "Changed(v))\n"
    s.trees.add ("PropT" & $i, t.props[i].typ)
  let all = "proc initProps*(w: Owner) =\n  w.initPropValues()\n" &
    "  w.linkEagerProps()\n  w.bindPropHandlers()\n"
  dest.emitStmts(values & eager & handlers & all, s, t.info)

proc transform(root: NifCursor): NifBuilder =
  var body = callArgs(root)
  if body.stmtKind != StmtsS:
    return errorTree("properties expects a block of type declarations", root)
  var err = createTree()
  var types: seq[TypeInfo] = @[]
  var rest: seq[NifCursor] = @[]
  var userMethods: seq[string] = @[]
  for t in body.children:
    if t.stmtKind == TypeS:
      types.add readType(t, err)
      if not err.isEmpty: return err
    else:
      rest.add t               # procs and methods of these types, kept as is
      if t.stmtKind == MethodS:
        let r = asRoutine(t)
        if r.name.kind == Ident and r.params.kind == TagLit:
          let first = asLocal(firstChild(r.params))
          if first.typ.kind == Ident:
            userMethods.add first.typ.identText & "." & r.name.identText
  result = createTree()
  result.withTree StmtsS, root.info:
    for t in types:
      result.emitTypeDecl(t)
    for t in types:
      result.emitProcs(t, userMethods)
      result.emitInit(t)
    for r in rest:
      result.addSubtree r

saveTree transform(loadPluginInput())
