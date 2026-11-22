## A plain property (`prop`, `bounds`, `color`, `varlist`): its fields, the
## accessor, the setter, which dispatches on a change (always with
## `always`), `initP`, which sets without a dispatch, the observers, and
## for `color` and `varlist` the setters from fewer numbers.

import plugins
import ../trees, reader, syntax, common

proc emitPlainFields*(dest: var NifBuilder; p: Prop) =
  dest.addStoreFields p

proc addOutside(dest: var NifBuilder; p: Prop) =
  # `v < lo or v > hi`
  dest.withInfix "or", p.info:
    dest.withInfix "<", p.info:
      dest.addIdent "v"
      dest.addSubtree p.lo
    dest.withInfix ">", p.info:
      dest.addIdent "v"
      dest.addSubtree p.hi

proc addChanged(dest: var NifBuilder; p: Prop) =
  # `w.pStore != v`
  dest.withInfix "!=", p.info:
    dest.addSelf p.name & "Store", p.info
    dest.addIdent "v"

proc addDispatches(dest: var NifBuilder; p: Prop) =
  # Whether the setter dispatches: `w.pStore != v`, `true or ...` with `always`.
  if p.always:
    dest.withInfix "or", p.info:
      dest.addIdent "true"
      dest.addChanged p
  else:
    dest.addChanged p

proc floatArray(len: int; info: LineInfo): NifCursor =
  # `array[len, float]`
  var t = createTree()
  t.withTree AtX, info:
    t.addIdent "array"
    t.addIntLit len
    t.addIdent "float"
  result = snapshot(t)

proc emitArraySetter(dest: var NifBuilder; p: Prop; given: int; items: openArray[int];
    alpha: bool) =
  # `` `p=`(w; v) `` from a `float` (`given` 0) or an `array[given, float]`:
  # `w.p = [...]` of `v` (an item -1) or `v[item]`, then 1.0 with `alpha`.
  let typ = if given == 0: identTree("float") else: floatArray(given, p.info)
  dest.withRoutine Head(kind: ProcS, name: quotedName([p.name, "="], p.info),
      exported: p.exported, params: @[selfParam(p), Param(name: "v", typ: typ)]), p.info:
    dest.withSelfAsgn p.name, p.info:
      dest.withTree BracketX, p.info:
        for i in items:
          if i < 0:
            dest.addIdent "v"
          else:
            dest.withTree AtX, p.info:
              dest.addIdent "v"
              dest.addIntLit i
        if alpha: dest.addFloatLit 1.0

proc emitPlain*(dest: var NifBuilder; p: Prop) =
  let self = selfParam(p)
  let value = Param(name: "v", typ: sinkOf(p.typ, p.info))
  let store = p.name & "Store"
  dest.withRoutine Head(kind: ProcS, name: identTree(p.name), exported: p.exported,
      params: @[self], ret: p.typ, pragma: "inline"), p.info:
    dest.addSelf store, p.info
  dest.withRoutine Head(kind: ProcS, name: quotedName([p.name, "="], p.info),
      exported: p.exported, params: @[self, value]), p.info:
    if p.bounded:
      dest.withIf(p.info, dest.addOutside(p)):
        dest.withCall "quitOutOfBounds", p.info:
          dest.addStrLit p.owner & "." & p.name
          dest.withPrefix "$", p.info:
            dest.addIdent "v"
    dest.withIf(p.info, dest.addDispatches(p)):
      dest.addSelfAsgn store, "v", p.info
      dest.addSelfCall "dispatch" & capital(p.name), p.info
  dest.withRoutine Head(kind: ProcS, name: identTree("init" & capital(p.name)),
      exported: p.exported, params: @[self, value]), p.info:
    dest.addSelfAsgn store, "v", p.info
  dest.emitObservers p, false, p.name
  if p.color:
    dest.emitArraySetter p, 3, [0, 1, 2], true
  if p.varlist == 4:
    dest.emitArraySetter p, 0, [-1, -1, -1, -1], false
    dest.emitArraySetter p, 1, [0, 0, 0, 0], false
    dest.emitArraySetter p, 2, [0, 1, 0, 1], false
  elif p.varlist == 2:
    dest.emitArraySetter p, 0, [-1, -1], false
    dest.emitArraySetter p, 1, [0, 0], false
