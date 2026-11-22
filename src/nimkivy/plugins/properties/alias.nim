## An AliasProperty (`alias`, with `deps`, `cache`, `eager`), as
## properties.pyx: `pValid` is Kivy's "not alias_initial". Without `cache`
## nothing is stored (so its type may be a `ref` that has no default
## value), and a dependency's change always dispatches (Kivy compares with
## its stored None).

import plugins
import ../trees, reader, syntax, common

proc emitAliasFields*(dest: var NifBuilder; p: Prop) =
  if p.cache:
    dest.addStoreFields p
    dest.addFlagFields p, ["Linked", "Valid", "Stop"]
  else:
    dest.addObserversField p, valueCallback(p)
    dest.addFlagFields p, ["Linked"]

proc addGet(dest: var NifBuilder; p: Prop) =
  # `getter(w)`
  dest.withTree CallX, p.info:
    dest.addSubtree p.getter
    dest.addIdent "w"

proc addCacheUpdate(dest: var NifBuilder; p: Prop) =
  # `w.pValid = true; w.pStore = getter(w)`
  dest.addSelfAsgn p.name & "Valid", "true", p.info
  dest.withSelfAsgn p.name & "Store", p.info:
    dest.addGet p

proc addStale(dest: var NifBuilder; p: Prop) =
  # `not w.pValid or w.pStore != value`
  dest.withInfix "or", p.info:
    dest.addSelfNot p.name & "Valid", p.info
    dest.withInfix "!=", p.info:
      dest.addSelf p.name & "Store", p.info
      dest.addIdent "value"

proc emitAlias*(dest: var NifBuilder; p: Prop) =
  let self = selfParam(p)
  let name = capital(p.name)
  dest.emitLink p, p.deps
  # Kivy's trigger reads the value (`get`) before it dispatches.
  dest.withRoutine Head(kind: ProcS, name: identTree("trigger" & name),
      params: @[self]), p.info:
    dest.addSelfCall "link" & name, p.info
    if p.cache:
      dest.withLet identTree("value"), p.info:
        dest.addGet p
      dest.withIf(p.info, dest.addStale(p)):
        dest.addSelfAsgn p.name & "Valid", "true", p.info
        dest.addSelfAsgn p.name & "Store", "value", p.info
        dest.addSelfCall "dispatch" & name, p.info
    else:
      dest.withTree DiscardS, p.info:
        dest.addGet p
      dest.addSelfCall "dispatch" & name, p.info
  dest.withRoutine Head(kind: ProcS, name: identTree(p.name), exported: p.exported,
      params: @[self], ret: p.typ), p.info:
    dest.addSelfCall "link" & name, p.info
    if p.cache:
      dest.withIf(p.info, dest.addSelfNot(p.name & "Valid", p.info)):
        dest.addCacheUpdate p
      dest.addSelf p.name & "Store", p.info
    else:
      dest.addGet p
  if p.hasSetter:
    dest.withRoutine Head(kind: ProcS, name: quotedName([p.name, "="], p.info),
        exported: p.exported, params: @[self, Param(name: "v", typ: p.typ)]), p.info:
      dest.addSelfCall "link" & name, p.info
      dest.withTree IfS, p.info:
        dest.withTree ElifU, p.info:
          dest.withTree CallX, p.info:   # `setter(w, v)`
            dest.addSubtree p.setter
            dest.addIdent "w"
            dest.addIdent "v"
          dest.withTree StmtsS, p.info:
            if p.cache: dest.addCacheUpdate p
            dest.addSelfCall "dispatch" & name, p.info
        if p.always:
          dest.withTree ElseU, p.info:
            dest.withTree StmtsS, p.info:
              dest.addSelfCall "dispatch" & name, p.info
  dest.emitObservers p, true, p.name
