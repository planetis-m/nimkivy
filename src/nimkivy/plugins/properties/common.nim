## What the property kinds generate alike: `w.field` expressions, the store
## and observer fields, the bind, unbind and dispatch procs, the links of a
## trigger into other properties, and the default handler `onPChanged`.
## Every node of a property's code is positioned at its field (`Prop.info`).

import plugins
import ../trees, reader, syntax

proc selfParam*(p: Prop): Param =
  ## `w: Owner`.
  Param(name: "w", typ: identTree(p.owner))

proc valueCallback*(p: Prop): NifCursor =
  ## `proc (v: T) {.closure.}`, an observer of `p`.
  closureType(@[Param(name: "v", typ: p.typ)], NifCursor(), p.info)

# ------------------------------------------------------------------ statements on `w`

proc addSelf*(dest: var NifBuilder; field: string; info: LineInfo) =
  ## `w.field`.
  dest.withTree DotX, info:
    dest.addIdent "w"
    dest.addIdent field

proc addSelfNot*(dest: var NifBuilder; field: string; info: LineInfo) =
  ## `not w.field`.
  dest.withPrefix "not", info:
    dest.addSelf field, info

proc addSelfCall*(dest: var NifBuilder; routine: string; info: LineInfo) =
  ## `w.routine()`.
  dest.withTree CallX, info:
    dest.addSelf routine, info

template withSelfAsgn*(dest: var NifBuilder; field: string; info: LineInfo;
    value: untyped) =
  ## `w.field = value`; `value` emits the value.
  dest.withTree AsgnS, info:
    dest.addSelf field, info
    value

proc addSelfAsgn*(dest: var NifBuilder; field, value: string; info: LineInfo) =
  ## `w.field = value`, `value` a name.
  dest.withSelfAsgn field, info:
    dest.addIdent value

proc addObsCall*(dest: var NifBuilder; p: Prop; routine, arg: string) =
  ## `w.pObs.routine(arg)`.
  dest.withTree CallX, p.info:
    dest.withTree DotX, p.info:
      dest.addSelf p.name & "Obs", p.info
      dest.addIdent routine
    dest.addIdent arg

template withObsLoop*(dest: var NifBuilder; p: Prop; iter: string; body: untyped) =
  ## `for cb in w.pObs.iter: body`.
  dest.withTree ForS, p.info:
    dest.withTree DotX, p.info:
      dest.addSelf p.name & "Obs", p.info
      dest.addIdent iter
    dest.withTree UnpackflatU, p.info:
      dest.withTree LetS, p.info:
        dest.addIdent "cb"
        dest.addEmptyNode4 p.info  # export, pragmas, type, value
    dest.withTree StmtsS, p.info:
      body

proc addNotify*(dest: var NifBuilder; p: Prop; value: string) =
  ## `let value = w.value` and each observer called with it: a dispatch
  ## passes a copy, as an observer may replace the stored value while the
  ## later observers still need it (planetis-m/nimony-bugs-llms#334).
  dest.withLet identTree("value"), p.info:
    dest.addSelf value, p.info
  dest.withObsLoop p, "live":
    dest.withCall "cb", p.info:
      dest.addIdent "value"

# ------------------------------------------------------------------ fields

proc addObserversField*(dest: var NifBuilder; p: Prop; callback: NifCursor) =
  ## `pObs: Observers[callback]`.
  var t = createTree()
  t.withTree AtX, p.info:
    t.addIdent "Observers"
    t.addSubtree callback
  dest.addField p.name & "Obs", snapshot(t), p.info

proc addStoreFields*(dest: var NifBuilder; p: Prop) =
  ## `pStore: T` and `pObs`, its observers.
  dest.addField p.name & "Store", p.typ, p.info
  dest.addObserversField p, valueCallback(p)

proc addFlagFields*(dest: var NifBuilder; p: Prop; flags: openArray[string]) =
  ## `pLinked: bool`, ... for each of `flags` ("Linked", ...).
  for f in flags:
    dest.addField p.name & f, identTree("bool"), p.info

# ------------------------------------------------------------------ routines alike

proc emitObservers*(dest: var NifBuilder; p: Prop; link: bool; value: string) =
  ## `bindP`, `unbindP` and `dispatchP`, which passes `w.value`; with `link`,
  ## binding and dispatching first link `p` (`w.linkP()`).
  let self = selfParam(p)
  let name = capital(p.name)
  dest.withRoutine Head(kind: ProcS, name: identTree("bind" & name), exported: p.exported,
      params: @[self, Param(name: "cb", typ: sinkOf(valueCallback(p), p.info))],
      ret: identTree("Binding")), p.info:
    if link: dest.addSelfCall "link" & name, p.info
    dest.addObsCall p, "add", "cb"
  dest.withRoutine Head(kind: ProcS, name: identTree("unbind" & name), exported: p.exported,
      params: @[self, Param(name: "b", typ: identTree("Binding"))]), p.info:
    dest.addObsCall p, "remove", "b"
  dest.withRoutine Head(kind: ProcS, name: identTree("dispatch" & name),
      exported: p.exported, params: @[self]), p.info:
    if link: dest.addSelfCall "link" & name, p.info
    dest.addNotify p, value

proc emitLink*(dest: var NifBuilder; p: Prop; deps: seq[string]) =
  ## `linkP`: on its first call, binds `triggerP` into each of `deps`.
  let name = capital(p.name)
  dest.withRoutine Head(kind: ProcS, name: identTree("link" & name),
      params: @[selfParam(p)]), p.info:
    dest.withIf(p.info, dest.addSelfNot(p.name & "Linked", p.info)):
      dest.addSelfAsgn p.name & "Linked", "true", p.info
      for dep in deps:
        # `discard w.bindDep(proc (v: typeof(w.dep)) {.closure.} = w.triggerP())`
        var typ = createTree()
        typ.withCall "typeof", p.info:
          typ.addSelf dep, p.info
        dest.withDiscardCall identTree("w"), "bind" & capital(dep), p.info:
          dest.withClosure @[Param(name: "v", typ: snapshot(typ))], p.info:
            dest.addSelfCall "trigger" & name, p.info
      if deps.len == 0:
        dest.addDiscard p.info

proc changedHandler*(p: Prop): string =
  ## The name of `p`'s default handler, `onPChanged`.
  "on" & capital(p.name) & "Changed"

proc emitChangedHandler*(dest: var NifBuilder; p: Prop) =
  ## `method onPChanged*(w: Owner; v: T) {.base.} = discard`.
  dest.withRoutine Head(kind: MethodS, name: identTree(changedHandler(p)),
      exported: p.exported, params: @[selfParam(p), Param(name: "v", typ: p.typ)],
      pragma: "base"), p.info:
    dest.addDiscard p.info
