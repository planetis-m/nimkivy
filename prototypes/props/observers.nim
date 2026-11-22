## Typed observer lists: the run-time half of the property prototype.
##
## `Observers[F]` keeps the callbacks of one property or event of one object,
## in bind order. `F` is the callback's proc type, so every callback is typed:
## no `Value` boxing, no lookup by name. The `properties` plugin declares one
## per property and event and generates the code that calls them.
##
## Dispatch keeps Kivy's rules (`_event.pyx` EventObservers): a callback bound
## during a dispatch is not called by it; a callback unbound during it is not
## called any more. Unbinding marks the entry dead; dead entries are removed
## once no dispatch of this list is running, so a dispatch allocates nothing.

type
  Binding* = distinct int
    ## What `bind<Prop>` returns and `unbind<Prop>` takes (Kivy's `fbind`
    ## uid). 0 is never a binding.

  Observer[F] = object
    uid: int                 # 0 once unbound
    cb: F

  Observers*[F] = object
    ## The callbacks of one property or event, in bind order.
    entries: seq[Observer[F]]
    lastUid: int
    running: int             # dispatches of this list in progress
    dead: int                # unbound entries not removed yet

proc `==`*(a, b: Binding): bool {.borrow.}

func add*[F](obs: var Observers[F]; cb: F): Binding =
  ## Binds `cb` last; returns its binding.
  inc obs.lastUid
  obs.entries.add Observer[F](uid: obs.lastUid, cb: cb)
  result = Binding(obs.lastUid)

func compact[F](obs: var Observers[F]) =
  var kept: seq[Observer[F]] = @[]
  for e in obs.entries:
    if e.uid != 0: kept.add e
  obs.entries = kept
  obs.dead = 0

func remove*[F](obs: var Observers[F]; b: Binding) =
  ## Unbinds the callback that `add` returned `b` for; an unknown binding is
  ## ignored, as Kivy's `unbind_uid` does.
  for i in 0 ..< obs.entries.len:
    if obs.entries[i].uid == int(b):
      obs.entries[i].uid = 0
      inc obs.dead
      break
  if obs.running == 0 and obs.dead > 0: obs.compact()

func len*[F](obs: Observers[F]): int =
  ## The number of bound callbacks.
  obs.entries.len - obs.dead

iterator live*[F](obs: var Observers[F]): F =
  ## The callbacks bound when the loop starts and still bound, first bound
  ## first (a property's order). Do not leave the loop early.
  let n = obs.entries.len
  inc obs.running
  for i in 0 ..< n:
    if obs.entries[i].uid != 0:
      yield obs.entries[i].cb
  dec obs.running
  if obs.running == 0 and obs.dead > 0: obs.compact()

iterator liveReversed*[F](obs: var Observers[F]): F =
  ## The same, last bound first (an event's order, `dispatch_reverse`).
  let n = obs.entries.len
  inc obs.running
  var i = n - 1
  while i >= 0:
    if obs.entries[i].uid != 0:
      yield obs.entries[i].cb
    dec i
  dec obs.running
  if obs.running == 0 and obs.dead > 0: obs.compact()
