## A ReferenceList (`refs`), as properties.pyx: linked on first use, when it
## binds a trigger to each reference, so its place among their observers is
## Kivy's. Its stored value is invalid until read, set or triggered, so the
## first set always dispatches, as Kivy's default (the properties
## themselves) never equals a value.

import plugins
import ../trees, reader, syntax, common

proc emitRefsFields*(dest: var NifBuilder; p: Prop) =
  dest.addStoreFields p
  dest.addFlagFields p, ["Linked", "Valid", "Stop"]

proc addRefsValue(dest: var NifBuilder; p: Prop) =
  # `(w.a, w.b)`
  dest.withTree TupX, p.info:
    for r in p.refs: dest.addSelf r, p.info

proc addUnchanged(dest: var NifBuilder; p: Prop) =
  # `w.pValid and w.pStore == v`, after `false and` with `always`.
  dest.withInfix "and", p.info:
    if p.always:
      dest.withInfix "and", p.info:
        dest.addIdent "false"
        dest.addSelf p.name & "Valid", p.info
    else:
      dest.addSelf p.name & "Valid", p.info
    dest.withInfix "==", p.info:
      dest.addSelf p.name & "Store", p.info
      dest.addIdent "v"

proc emitRefs*(dest: var NifBuilder; p: Prop) =
  let self = selfParam(p)
  let name = capital(p.name)
  let store = p.name & "Store"
  let valid = p.name & "Valid"
  let stop = p.name & "Stop"
  dest.withRoutine Head(kind: ProcS, name: identTree("trigger" & name),
      params: @[self]), p.info:
    dest.withIf(p.info, dest.addSelfNot(stop, p.info)):
      dest.withSelfAsgn store, p.info:
        dest.addRefsValue p
      dest.addSelfAsgn valid, "true", p.info
      dest.addSelfCall "dispatch" & name, p.info
  dest.emitLink p, p.refs
  dest.withRoutine Head(kind: ProcS, name: identTree(p.name), exported: p.exported,
      params: @[self], ret: p.typ), p.info:
    dest.addSelfCall "link" & name, p.info
    dest.withSelfAsgn store, p.info:
      dest.addRefsValue p
    dest.addSelfAsgn valid, "true", p.info
    dest.addSelf store, p.info
  dest.withRoutine Head(kind: ProcS, name: quotedName([p.name, "="], p.info),
      exported: p.exported,
      params: @[self, Param(name: "v", typ: sinkOf(p.typ, p.info))]), p.info:
    dest.addSelfCall "link" & name, p.info
    dest.withIf(p.info, dest.addUnchanged(p)):
      dest.withTree RetS, p.info:
        dest.addEmptyNode p.info
    dest.addSelfAsgn stop, "true", p.info
    for i in 0 ..< p.refs.len:
      dest.withSelfAsgn p.refs[i], p.info:
        dest.withTree AtX, p.info:
          dest.addIdent "v"
          dest.addIntLit i
    dest.addSelfAsgn stop, "false", p.info
    dest.addSelfAsgn store, "v", p.info
    dest.addSelfAsgn valid, "true", p.info
    dest.addNotify p, store
  dest.emitObservers p, true, store
