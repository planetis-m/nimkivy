## An event (`event`): its observers, `dispatchE`, which calls them newest
## first until one returns true and then the default handler, and that
## handler, the base method `onE`, unless the block declares its own.

import plugins
import ../trees, reader, syntax, common

proc eventParams(p: Prop; first: seq[Param]): seq[Param] =
  # `first`, then `a0: T0, a1: T1, ...`
  result = first
  for i in 0 ..< p.args.len:
    result.add Param(name: "a" & $i, typ: p.args[i])

proc eventCallback(p: Prop): NifCursor =
  # `proc (a0: T0, ...): bool {.closure.}`
  closureType(eventParams(p, @[]), identTree("bool"), p.info)

proc emitEventFields*(dest: var NifBuilder; p: Prop) =
  dest.addObserversField p, eventCallback(p)

template withHandled(dest: var NifBuilder; p: Prop; body: untyped) =
  # `if not result: result = body`
  dest.withIf(p.info, dest.withPrefix("not", p.info, dest.addIdent("result"))):
    dest.withTree AsgnS, p.info:
      dest.addIdent "result"
      body

proc addArgs(dest: var NifBuilder; p: Prop) =
  for i in 0 ..< p.args.len: dest.addIdent "a" & $i

proc emitEvent*(dest: var NifBuilder; p: Prop; withDefault: bool) =
  ## The event `p`; `withDefault`: also its default handler.
  let self = selfParam(p)
  let name = capital(p.name)
  let params = eventParams(p, @[self])
  dest.withRoutine Head(kind: ProcS, name: identTree("bind" & name), exported: p.exported,
      params: @[self, Param(name: "cb", typ: sinkOf(eventCallback(p), p.info))],
      ret: identTree("Binding")), p.info:
    dest.addObsCall p, "add", "cb"
  dest.withRoutine Head(kind: ProcS, name: identTree("unbind" & name), exported: p.exported,
      params: @[self, Param(name: "b", typ: identTree("Binding"))]), p.info:
    dest.addObsCall p, "remove", "b"
  dest.withRoutine Head(kind: ProcS, name: identTree("dispatch" & name),
      exported: p.exported, params: params, ret: identTree("bool")), p.info:
    dest.withTree AsgnS, p.info:
      dest.addIdent "result"
      dest.addIdent "false"
    dest.withObsLoop p, "liveReversed":
      dest.withHandled p:
        dest.withCall "cb", p.info:
          dest.addArgs p
    dest.withHandled p:
      dest.withTree CallX, p.info:
        dest.addSelf "on" & name, p.info
        dest.addArgs p
  if withDefault:
    dest.withRoutine Head(kind: MethodS, name: identTree("on" & name), exported: p.exported,
        params: params, ret: identTree("bool"), pragma: "base"), p.info:
      dest.addIdent "false"
