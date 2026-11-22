## A property's Animation track (`props.Track`): the subtype `OwnerPTrack`,
## `pTo(Owner, v)`, which animates `p` to `v`, `pKey(Owner)`, and the
## methods `capture`, which reads the start value on a target, `advance`,
## which sets the value at a point of the way, and `$`.

import plugins
import ../trees, reader, syntax, common

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

proc animatable*(p: Prop): bool =
  ## Whether an Animation can move `p`: a settable property of a numeric type.
  let settable = p.kind in {kProp, kRefs} or (p.kind == kAlias and p.hasSetter)
  result = settable and (p.color or p.varlist > 0 or isNumericType(p.typ))

proc addNil(dest: var NifBuilder; info: LineInfo) =
  # `nil`
  dest.withTree NilX, info:
    discard

template withTrack(dest: var NifBuilder; track: string; p: Prop; body: untyped) =
  # `track(key: ..., target: ..., a: ..., b: ...)`; `body` emits the fields.
  dest.withTree OconstrX, p.info:
    dest.addIdent track
    body

template withField(dest: var NifBuilder; field: string; p: Prop; value: untyped) =
  # `field: value` in an object constructor.
  dest.withTree KvU, p.info:
    dest.addIdent field
    value

proc addNotNil(dest: var NifBuilder; p: Prop) =
  # `w != nil`
  dest.withInfix "!=", p.info:
    dest.addIdent "w"
    dest.addNil p.info

proc emitTrack*(dest: var NifBuilder; p: Prop) =
  let track = p.owner & capital(p.name) & "Track"
  let what = p.owner & "." & p.name
  var typedesc = createTree()
  typedesc.withTree AtX, p.info:
    typedesc.addIdent "typedesc"
    typedesc.addIdent p.owner
  let ofOwner = Param(name: "t", typ: snapshot(typedesc))
  let ofTrack = Param(name: "t", typ: identTree(track))
  let t = identTree("t")
  # type OwnerPTrack = ref object of Track
  #   target: nil Owner
  #   a, b: T
  dest.withTree TypeS, p.info:
    dest.addIdent track
    dest.addEmptyNode3 p.info  # export, type vars, pragmas
    dest.withTree RefT, p.info:
      dest.withTree ObjectT, p.info:
        dest.addIdent "Track"
        var target = createTree()
        target.withTree CmdX, p.info:
          target.addNil p.info
          target.addIdent p.owner
        dest.addField "target", snapshot(target), p.info
        dest.addField "a", p.typ, p.info
        dest.addField "b", p.typ, p.info
  dest.withRoutine Head(kind: ProcS, name: identTree(p.name & "Key"), exported: p.exported,
      params: @[ofOwner], ret: identTree("TrackKey"), pragma: "inline"), p.info:
    dest.withCall "trackKey", p.info:
      dest.addStrLit what
  dest.withRoutine Head(kind: ProcS, name: identTree(p.name & "To"), exported: p.exported,
      params: @[ofOwner, Param(name: "v", typ: sinkOf(p.typ, p.info))],
      ret: identTree("Track")), p.info:
    dest.withTrack track, p:
      dest.withField "key", p:
        dest.withCall "trackKey", p.info:
          dest.addStrLit what
      dest.withField "target", p:
        dest.addNil p.info
      dest.withField "a", p:
        dest.addIdent "v"
      dest.withField "b", p:
        dest.addIdent "v"
  dest.withRoutine Head(kind: MethodS, name: identTree("capture"),
      params: @[ofTrack, Param(name: "target", typ: sinkOf(identTree("RootRef"), p.info))],
      ret: identTree("Track")), p.info:
    dest.withTree IfS, p.info:
      dest.withTree ElifU, p.info:
        dest.withInfix "of", p.info:
          dest.addIdent "target"
          dest.addIdent p.owner
        dest.withTree StmtsS, p.info:
          dest.withLet identTree("w"), p.info:
            dest.withCall p.owner, p.info:
              dest.addIdent "target"
          dest.withTree AsgnS, p.info:
            dest.addIdent "result"
            dest.withTrack track, p:
              dest.withField "key", p:
                dest.addDot t, "key", p.info
              dest.withField "target", p:
                dest.addIdent "w"
              dest.withField "a", p:
                dest.addSelf p.name, p.info
              dest.withField "b", p:
                dest.addDot t, "b", p.info
      dest.withTree ElseU, p.info:
        dest.withTree StmtsS, p.info:
          dest.withTree AsgnS, p.info:
            dest.addIdent "result"
            dest.withCall "quitWrongTarget", p.info:
              dest.addStrLit what
  dest.withRoutine Head(kind: MethodS, name: identTree("advance"),
      params: @[ofTrack, Param(name: "progress", typ: identTree("float"))]), p.info:
    dest.withLet identTree("w"), p.info:
      dest.addDot t, "target", p.info
    dest.withIf(p.info, dest.addNotNil(p)):
      dest.withSelfAsgn p.name, p.info:
        dest.withCall "lerp", p.info:
          dest.addDot t, "a", p.info
          dest.addDot t, "b", p.info
          dest.addIdent "progress"
  dest.withRoutine Head(kind: MethodS, name: quotedName(["$"], p.info),
      params: @[ofTrack], ret: identTree("string")), p.info:
    dest.withInfix "&", p.info:
      dest.addStrLit what & " -> "
      dest.withPrefix "$", p.info:
        dest.addDot t, "b", p.info
