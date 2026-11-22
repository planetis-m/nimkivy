## The `properties:` block read: its types with their properties, and the
## statements after them.

import plugins

type
  Kind* = enum
    kProp, kRefs, kAlias, kEvent

  Prop* = object
    owner*: string             # the type that declares it
    name*: string
    exported*: bool
    kind*: Kind
    typ*: NifCursor            # the field's type
    default*: NifCursor        # its default value; a DotToken when none
    bounded*: bool
    lo*, hi*: NifCursor        # bounds
    color*: bool
    varlist*: int              # 0, or the length 2 or 4
    always*, handler*, cache*, eager*: bool
    refs*: seq[string]         # kRefs: the referenced properties
    deps*: seq[string]         # kAlias: the properties it depends on
    getter*, setter*: NifCursor  # kAlias; setter is a DotToken when read-only
    hasSetter*: bool
    args*: seq[NifCursor]      # kEvent: the argument types
    info*: LineInfo

  TypeInfo* = object
    name*: string
    decl*: NifCursor           # the input `(type ...)`
    base*: NifCursor           # the base type in `ref object of Base`
    props*: seq[Prop]
    overrides*: seq[(string, NifCursor)]   # {.defaults: (name: value).}
    info*: LineInfo

  Block* = object
    types*: seq[TypeInfo]
    rest*: seq[NifCursor]      # the other statements, kept as they are
    userMethods*: seq[string]  # "Owner.name" of the methods among them

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

proc fail(err: var NifBuilder; at: NifCursor) =
  err = errorTree("properties: unsupported syntax", at)

proc readPragma(prop: var Prop; p: NifCursor; local: Local; err: var NifBuilder) =
  case pragmaName(p)
  of "prop": prop.kind = kProp
  of "bounds":
    let range = pragmaValue(p)
    if range.kind != TagLit or range.tagText != "infix":
      fail(err, p)
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
      fail(err, p)
    else:
      prop.varlist = int(n.intValue)
  of "event":
    if local.typ.kind != TagLit or local.typ.tagText != "proctype":
      fail(err, local.typ)
    else:
      var pt = firstChild(local.typ)
      for _ in 0 ..< 4: skip pt  # name, export, pattern, typevars
      for param in pt.children:
        prop.args.add asLocal(param).typ
      prop.kind = kEvent
  else:
    fail(err, p)

proc readField(f: NifCursor; owner: string; props: var seq[Prop]; err: var NifBuilder) =
  # (fld name export pragmas type default)
  let local = asLocal(f)
  if local.pragmas.kind != TagLit:
    return                     # a plain field
  var prop = Prop(owner: owner, name: local.name.identText,
    exported: local.exported.kind != DotToken, kind: kProp, typ: local.typ,
    default: local.val, info: f.info)
  for p in local.pragmas.children:
    readPragma(prop, p, local, err)
    if not err.isEmpty: return
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
    fail(err, t)
    return
  var f = firstChild(body)
  result.base = f
  skip f
  while f.hasMore:
    readField(f, result.name, result.props, err)
    if not err.isEmpty: return
    skip f

proc readBlock*(body: NifCursor; err: var NifBuilder): Block =
  ## The block's statements, `body`; `err` is set to an error tree at the
  ## first syntax the plugin does not support.
  result = Block()
  for t in body.children:
    if t.stmtKind == TypeS:
      result.types.add readType(t, err)
      if not err.isEmpty: return
    else:
      result.rest.add t        # procs and methods of these types
      if t.stmtKind == MethodS:
        let r = asRoutine(t)
        if r.name.kind == Ident and r.params.kind == TagLit:
          let first = asLocal(firstChild(r.params))
          if first.typ.kind == Ident:
            result.userMethods.add first.typ.identText & "." & r.name.identText

proc findProp*(t: TypeInfo; name: string): int =
  ## The index of the property `name` in `t.props`, or -1.
  result = -1
  for i in 0 ..< t.props.len:
    if t.props[i].name == name: return i
