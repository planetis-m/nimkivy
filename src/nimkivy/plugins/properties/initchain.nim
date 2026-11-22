## A type's `initProps` and the chains it runs, in Kivy's order
## (_event.pyx `__init__`): `initPropValues`, the defaults (no dispatch, as
## Kivy sets them before any observer exists), base first, then this type's,
## then the overrides; `linkEagerProps`, the eager alias links, base first;
## `bindPropHandlers`, the handlers, base first and in name order within a
## type.

import std/algorithm
import plugins
import ../trees, reader, syntax, common

proc selfParam(t: TypeInfo): Param =
  Param(name: "w", typ: identTree(t.name))

proc addBaseCall(dest: var NifBuilder; t: TypeInfo; chain: string) =
  # `chain(Base(w))`, or `discard` when the base is RootObj or RootRef.
  if t.base.kind == Ident and t.base.identText in ["RootObj", "RootRef"]:
    dest.addDiscard t.info
  else:
    dest.withCall chain, t.info:
      dest.withTree CallX, t.info:
        dest.addSubtree t.base
        dest.addIdent "w"

template withChain(dest: var NifBuilder; t: TypeInfo; chain: string; body: untyped) =
  # `proc chain*(w: Owner) =`, the base's chain, then `body`.
  dest.withRoutine Head(kind: ProcS, name: identTree(chain), exported: true,
      params: @[selfParam(t)]), t.info:
    dest.addBaseCall t, chain
    body

proc emitInit*(dest: var NifBuilder; t: TypeInfo) =
  dest.withChain t, "initPropValues":
    for p in t.props:
      if p.kind == kProp:
        dest.withSelfAsgn p.name & "Store", t.info:
          if p.default.kind == DotToken:
            dest.withCall "default", t.info:
              dest.addSubtree p.typ
          else:
            dest.addSubtree p.default
    for (name, value) in t.overrides:
      dest.withTree CallX, t.info:
        dest.addSelf "init" & capital(name), t.info
        dest.addSubtree value
  dest.withChain t, "linkEagerProps":
    for p in t.props:
      if p.kind == kAlias and p.eager and p.deps.len > 0:
        dest.addSelfCall "link" & capital(p.name), t.info
  var named: seq[string] = @[]
  for p in t.props:
    if p.handler: named.add p.name
  named.sort()
  dest.withChain t, "bindPropHandlers":
    for name in named:
      # `discard w.bindP(proc (v: T) {.closure.} = w.onPChanged(v))`
      let p = t.props[t.findProp(name)]
      dest.withDiscardCall identTree("w"), "bind" & capital(name), t.info:
        dest.withClosure @[Param(name: "v", typ: p.typ)], t.info:
          dest.withTree CallX, t.info:
            dest.addSelf changedHandler(p), t.info
            dest.addIdent "v"
  dest.withRoutine Head(kind: ProcS, name: identTree("initProps"), exported: true,
      params: @[selfParam(t)]), t.info:
    dest.addSelfCall "initPropValues", t.info
    dest.addSelfCall "linkEagerProps", t.info
    dest.addSelfCall "bindPropHandlers", t.info
