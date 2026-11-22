## The event dispatcher: Kivy's `kivy/_event.pyx` and `kivy/event.py`.
##
## An `EventDispatcher` owns named events and named properties. Events are
## dispatched to their observers newest first, then to the class's default
## `on_<event>` handler; a property change is dispatched to its observers in
## bind order, starting with the class's `on_<prop>` handler.
##
## The base `Property` lives here, not in `properties`, because the dispatcher
## links, binds and dispatches properties by name and Nim modules cannot import
## each other. Its kinds (Numeric, Alias, ...) are in `properties`.
##
## Values are dynamically typed (`Value`), as in Kivy: every property is stored
## the same way, so Animation and the layouts can read and write them by name.
## Typed accessors sit on top of this in the modules that declare properties.

import std/[assertions, tables, algorithm, strutils, syncio]

type
  ValueKind* = enum
    ## What a `Value` holds.
    vkNone      ## Python's None
    vkNumber    ## int or float
    vkString
    vkBool
    vkObject    ## any other object, compared by identity
    vkList      ## a list or tuple

  Value* = object
    ## A property value or an event argument.
    case kind*: ValueKind
    of vkNone: discard
    of vkNumber: num*: float
    of vkString: str*: string
    of vkBool: flag*: bool
    of vkObject: obj*: nil RootRef
    of vkList: items*: seq[Value]

  PropertyCallback* = proc (d: EventDispatcher; value: Value) {.closure.}
    ## A property observer: called with the dispatcher and the new value.
  EventCallback* = proc (d: EventDispatcher; args: seq[Value]): bool {.closure.}
    ## An event observer: returning true stops the dispatch.
  EventHandler* = proc (d: EventDispatcher; args: seq[Value]): bool {.nimcall.}
    ## A class's default `on_<event>` handler.
  PropertyHandler* = proc (d: EventDispatcher; value: Value) {.nimcall.}
    ## A class's default `on_<prop>` handler.
  Comparator* = proc (a, b: Value): bool {.nimcall.}
    ## Whether two property values count as the same (no dispatch).

  BoundCallback = ref object
    # One observer. `deleted` is set when it is unbound, so that a dispatch
    # already running skips it (Kivy's `lock == deleted`).
    # GAP: observers are held strongly, where Kivy's `bind` holds a
    # WeakMethod, so a dropped widget that is still bound is not collected
    # and its callbacks still run, because Nimony has no weak references
    uid: int
    onValue: nil PropertyCallback
    onEvent: nil EventCallback
    deleted: bool

  EventObservers* = ref object
    ## The observers of one event or one property of one dispatcher, in bind
    ## order (Kivy's doubly linked list).
    callbacks: seq[BoundCallback]
    uid: int                       # the next uid that fbind hands out

  PropertyStorage* = ref object
    ## The per-instance state of one property (Kivy's PropertyStorage and its
    ## ReferenceList and Alias subclasses in one object).
    value*: Value
    observers*: EventObservers
    prop*: Property                ## the property that created this storage
    stopEvent*: bool               ## ReferenceList: a set is in progress
    aliasInitial*: bool            ## Alias: the cache has not been filled yet

  Property* = ref object of RootObj
    ## The base of every property kind: a class attribute, shared by all
    ## instances; the values live in each instance's `PropertyStorage`.
    name*: string
    index*: int                    ## slot in the instance's storage
    defaultValue*: Value
    allowNone*: bool
    forceDispatch*: bool           ## dispatch even when the value is unchanged
    comparator*: nil Comparator

  DispatcherClass* = ref object
    ## What Kivy keeps per Python class: its properties in declaration order
    ## (base classes first), its events, and its default handlers.
    name*: string
    properties*: seq[Property]
    propertyIndex: Table[string, int]
    events*: seq[string]
    eventHandlers: Table[string, nil EventHandler]
    propertyHandlers: Table[string, nil PropertyHandler]

  EventDispatcher* = ref object of RootObj
    ## The base of every object with events and properties. Build it with
    ## `T(cls: TClass)` and then call `initEventDispatcher`.
    cls*: DispatcherClass
    storage: seq[nil PropertyStorage]
    eventStack: Table[string, nil EventObservers]

# ------------------------------------------------------------------ values

func noneValue*(): Value {.inline.} =
  ## Python's None.
  Value(kind: vkNone)

func toValue*(x: float): Value {.inline.} =
  ## A number.
  Value(kind: vkNumber, num: x)

func toValue*(x: int): Value {.inline.} =
  ## A number (stored as a float).
  Value(kind: vkNumber, num: float(x))

func toValue*(s: string): Value {.inline.} =
  ## A string.
  Value(kind: vkString, str: s)

func toValue*(b: bool): Value {.inline.} =
  ## A boolean.
  Value(kind: vkBool, flag: b)

func toValue*(o: RootRef): Value {.inline.} =
  ## An object, compared by identity.
  Value(kind: vkObject, obj: o)

func toValue*(items: seq[Value]): Value {.inline.} =
  ## A list.
  Value(kind: vkList, items: items)

func toValue*(xs: openArray[float]): Value =
  ## A list of numbers.
  var items: seq[Value] = @[]
  for x in xs: items.add toValue(x)
  result = Value(kind: vkList, items: items)

func isNone*(v: Value): bool {.inline.} =
  ## Whether `v` is None.
  v.kind == vkNone

func `==`*(a, b: Value): bool =
  ## Python's `==`: lists element by element, objects by identity, and a
  ## number never equals a string or None.
  if a.kind != b.kind:
    result = false
  else:
    case a.kind
    of vkNone: result = true
    of vkNumber: result = a.num == b.num
    of vkString: result = a.str == b.str
    of vkBool: result = a.flag == b.flag
    of vkObject: result = a.obj == b.obj
    of vkList: result = a.items == b.items

func toFloats*(v: Value): seq[float] =
  ## The numbers of a list value.
  result = @[]
  for x in v.items: result.add x.num

func `$`*(v: Value): string =
  ## A short text form, numbers with 3 decimals (for logs and traces).
  case v.kind
  of vkNone: result = "none"
  of vkNumber: result = formatFloat(v.num, ffDecimal, 3)
  of vkString: result = v.str
  of vkBool: result = $v.flag
  of vkObject: result = "<object>"
  of vkList:
    result = "("
    for i in 0 ..< v.items.len:
      if i > 0: result.add ", "
      result.add $v.items[i]
    result.add ")"

# ------------------------------------------------------------------ observers

proc newEventObservers*(): EventObservers =
  ## An empty observer list; uids start at 1 so that 0 means "not bound".
  EventObservers(callbacks: @[], uid: 1)

proc addCallback(obs: EventObservers; cb: BoundCallback) =
  obs.callbacks.add cb

proc removeCallback(obs: EventObservers; cb: BoundCallback) =
  # A running dispatch holds its own snapshot and skips `deleted` callbacks,
  # which is what Kivy's locks achieve.
  cb.deleted = true
  let i = obs.callbacks.find(cb)
  if i >= 0: obs.callbacks.delete(i)

proc bindValue(obs: EventObservers; cb: PropertyCallback) =
  # _event.pyx EventObservers.bind: no second copy of the same callback.
  # GAP: the same method bound through two closures counts as two callbacks,
  # where Python's bound methods compare equal, because Nim has no bound
  # methods and a closure compares by its environment
  for i in 0 ..< obs.callbacks.len:
    let c = obs.callbacks[i]
    if c.uid == 0 and c.onValue != nil and c.onValue == cb: return
  obs.addCallback BoundCallback(uid: 0, onValue: cb, onEvent: nil)

proc bindEvent(obs: EventObservers; cb: EventCallback) =
  for i in 0 ..< obs.callbacks.len:
    let c = obs.callbacks[i]
    if c.uid == 0 and c.onEvent != nil and c.onEvent == cb: return
  obs.addCallback BoundCallback(uid: 0, onValue: nil, onEvent: cb)

proc fbindValue(obs: EventObservers; cb: PropertyCallback): int =
  # _event.pyx EventObservers.fbind
  result = obs.uid
  inc obs.uid
  obs.addCallback BoundCallback(uid: result, onValue: cb, onEvent: nil)

proc fbindEvent(obs: EventObservers; cb: EventCallback): int =
  result = obs.uid
  inc obs.uid
  obs.addCallback BoundCallback(uid: result, onValue: nil, onEvent: cb)

proc unbindUid*(obs: EventObservers; uid: int) =
  ## Removes the observer that `fbind` returned `uid` for.
  ## _event.pyx EventObservers.unbind_uid
  assert uid != 0, "uid, 0, that evaluates to False is not valid"
  for i in 0 ..< obs.callbacks.len:
    if obs.callbacks[i].uid == uid:
      obs.removeCallback(obs.callbacks[i])
      return

proc len*(obs: EventObservers): int {.inline.} =
  ## The number of bound observers.
  obs.callbacks.len

proc dispatchValue*(obs: EventObservers; d: EventDispatcher; value: Value) =
  ## Calls every property observer, first bound first. Observers bound
  ## during the dispatch are not called; observers unbound during it are not
  ## called any more. _event.pyx EventObservers.dispatch
  # GAP: an observer cannot raise, so no exception reaches the dispatcher's
  # caller and the event loop's ExceptionManager as in Kivy, because of
  # Nimony's error model (no unwinding through closures)
  let snapshot = obs.callbacks
  for i in 0 ..< snapshot.len:
    let cb = snapshot[i]
    if not cb.deleted:
      let f = cb.onValue
      if f != nil: f(d, value)

proc dispatchEvent(obs: EventObservers; d: EventDispatcher; args: seq[Value]): bool =
  # Events run last bound first (dispatch_reverse) and stop at the first true.
  result = false
  let snapshot = obs.callbacks
  var i = snapshot.len - 1
  while i >= 0 and not result:
    let cb = snapshot[i]
    if not cb.deleted:
      let f = cb.onEvent
      if f != nil: result = f(d, args)
    dec i

# ------------------------------------------------------------------ classes

proc newDispatcherClass*(name: string): DispatcherClass =
  ## The class of `EventDispatcher` itself: no properties, no events.
  DispatcherClass(name: name, properties: @[],
    propertyIndex: initTable[string, int](), events: @[],
    eventHandlers: initTable[string, nil EventHandler](),
    propertyHandlers: initTable[string, nil PropertyHandler]())

proc newDispatcherClass*(name: string; base: DispatcherClass): DispatcherClass =
  ## A subclass of `base`: it starts with the base's properties, events and
  ## handlers, and adds or overrides its own.
  result = DispatcherClass(name: name, properties: base.properties,
    propertyIndex: base.propertyIndex, events: base.events,
    eventHandlers: base.eventHandlers, propertyHandlers: base.propertyHandlers)

proc addProperty*(cls: DispatcherClass; name: string; p: Property) =
  ## Declares property `name` on the class, as a class attribute does in
  ## Kivy (`Property.__set_name__`). A name the base class already has keeps
  ## its place, so instances of the base and the subclass share the layout.
  if name in ["touch_down", "touch_move", "touch_up"]:
    quit "The property <" & name & "> has a forbidden name"
  p.name = name
  if cls.propertyIndex.hasKey(name):
    p.index = cls.propertyIndex.getOrDefault(name, 0)
    cls.properties[p.index] = p
  else:
    p.index = cls.properties.len
    cls.propertyIndex[name] = p.index
    cls.properties.add p

proc addEvent*(cls: DispatcherClass; name: string; handler: EventHandler) =
  ## Declares event `name` (`__events__`) with its default handler, which
  ## runs after the observers unless one of them returned true.
  if name.len < 3 or name[0 .. 2] != "on_":
    quit name & " is not an event name in " & cls.name
  if name notin cls.events: cls.events.add name
  cls.eventHandlers[name] = handler

proc setEventHandler*(cls: DispatcherClass; name: string; handler: EventHandler) =
  ## Overrides the default handler of an event, as a subclass method does;
  ## also makes it available to `registerEventType`.
  cls.eventHandlers[name] = handler

proc addPropertyHandler*(cls: DispatcherClass; name: string; handler: PropertyHandler) =
  ## Declares the class's default `on_<name>` handler for property `name`. It
  ## is bound first on every new instance, so it runs before other observers.
  cls.propertyHandlers[name] = handler

proc findProperty*(cls: DispatcherClass; name: string): nil Property =
  ## The property called `name`, or nil.
  let i = cls.propertyIndex.getOrDefault(name, -1)
  # Statements, not an if expression: planetis-m/nimony-bugs-llms#328
  if i >= 0: result = cls.properties[i]
  else: result = nil

# ------------------------------------------------------------------ Property base
# kivy/properties.pyx Property. The kinds in `properties` override these.

method convert*(p: Property; d: EventDispatcher; x: Value): Value {.base.} =
  ## Turns a value given to `set` into the stored form.
  x

method check*(p: Property; d: EventDispatcher; x: Value): string {.base.} =
  ## Why `x` is not a valid value, or "" when it is.
  if x.kind == vkNone and not p.allowNone:
    result = "None is not allowed for " & d.cls.name & "." & p.name
  else:
    result = ""

proc newStorage(p: Property; d: EventDispatcher): PropertyStorage =
  result = PropertyStorage(value: noneValue(), observers: newEventObservers(),
    prop: p, stopEvent: false, aliasInitial: false)

method initStorage*(p: Property; d: EventDispatcher; s: PropertyStorage) {.base.} =
  ## Fills a new storage with the default value.
  s.value = p.convert(d, p.defaultValue)

method link*(p: Property; d: EventDispatcher): PropertyStorage {.base.} =
  ## Creates this property's storage on `d`, unless it exists.
  let existing = d.storage[p.index]
  if existing != nil:
    result = existing
  else:
    let s = p.newStorage(d)
    d.storage[p.index] = s
    p.initStorage(d, s)
    result = s

method linkDeps*(p: Property; d: EventDispatcher) {.base.} =
  ## Binds to the properties this one depends on (ReferenceList, Alias).
  discard

method linkEagerly*(p: Property; d: EventDispatcher) {.base.} =
  ## Called for every property when an instance is created.
  discard

proc getPropertyStorage*(p: Property; d: EventDispatcher): PropertyStorage =
  ## The storage of `p` on `d`, created (and its dependencies bound) on first
  ## use. Which property is used first decides the order of observers.
  let s = d.storage[p.index]
  if s != nil:
    result = s
  else:
    discard p.link(d)
    p.linkDeps(d)
    let made = d.storage[p.index]
    if made == nil: quit "property " & p.name & " has no storage"
    result = made

method compareValue*(p: Property; a, b: Value): bool {.base.} =
  ## Whether `a` and `b` are the same value (no dispatch).
  let c = p.comparator
  result = if c != nil: c(a, b) else: a == b

method doDispatch*(p: Property; d: EventDispatcher; s: PropertyStorage) {.base.} =
  ## Calls the observers with the stored value (Kivy's `_dispatch`).
  # A copy: an observer can replace `s.value` while the others still need
  # it (reading a ReferenceList refreshes its storage), as Python's
  # dispatch keeps the old object alive. Passed as it is, the field goes by
  # reference and the later observers read freed memory
  # (planetis-m/nimony-bugs-llms#334).
  var value = s.value
  s.observers.dispatchValue(d, value)

proc checkOrQuit*(p: Property; d: EventDispatcher; x: Value) =
  ## Stops the program with Kivy's ValueError text when `x` is invalid.
  let err = p.check(d, x)
  if err.len > 0: quit "ValueError: " & err

method set*(p: Property; d: EventDispatcher; x: Value): bool {.base.} =
  ## Stores `x` and dispatches it, unless it equals the stored value.
  ## Returns whether it dispatched.
  let s = p.getPropertyStorage(d)
  let value = p.convert(d, x)
  if not p.forceDispatch and p.compareValue(s.value, value):
    result = false
  else:
    p.checkOrQuit(d, value)
    s.value = value
    p.doDispatch(d, s)
    result = true

method get*(p: Property; d: EventDispatcher): Value {.base.} =
  ## The value of `p` on `d`.
  result = p.getPropertyStorage(d).value

method triggerChange*(p: Property; d: EventDispatcher; value: Value) {.base.} =
  ## Called when a property this one depends on changed.
  discard

proc dispatch*(p: Property; d: EventDispatcher) =
  ## Dispatches the current value to the observers, even if unchanged.
  p.doDispatch(d, p.getPropertyStorage(d))

proc `bind`*(p: Property; d: EventDispatcher; cb: PropertyCallback) =
  ## Adds an observer, unless the same callback is already bound.
  p.getPropertyStorage(d).observers.bindValue(cb)

proc fbind*(p: Property; d: EventDispatcher; cb: PropertyCallback): int =
  ## Adds an observer and returns its uid for `unbindUid`.
  result = p.getPropertyStorage(d).observers.fbindValue(cb)

proc unbindUid*(p: Property; d: EventDispatcher; uid: int) =
  ## Removes the observer that `fbind` returned `uid` for.
  p.getPropertyStorage(d).observers.unbindUid(uid)

# ------------------------------------------------------------------ dispatcher

proc fbind*(d: EventDispatcher; name: string; cb: PropertyCallback): int

proc handlerCallback(h: PropertyHandler): PropertyCallback =
  result = proc (d: EventDispatcher; value: Value) {.closure.} = h(d, value)

proc initEventDispatcher*(d: EventDispatcher) =
  ## Sets up a new instance of `d.cls`: links the properties that link
  ## eagerly, creates the event observers, then binds the class's `on_<prop>`
  ## handlers in name order (Kivy binds them in `dir()` order).
  ## _event.pyx EventDispatcher.__cinit__ and __init__
  let cls = d.cls
  d.storage = newSeq[nil PropertyStorage](cls.properties.len)
  d.eventStack = initTable[string, nil EventObservers]()
  for i in 0 ..< cls.properties.len:
    cls.properties[i].linkEagerly(d)
  for i in 0 ..< cls.events.len:
    d.eventStack[cls.events[i]] = newEventObservers()
  var names: seq[string] = @[]
  let handlers = cls.propertyHandlers
  for name in handlers.keys:
    if cls.propertyIndex.hasKey(name): names.add name
  names.sort()
  for name in names:
    let h = cls.propertyHandlers.getOrDefault(name, nil)
    if h != nil: discard d.fbind(name, handlerCallback(h))

proc newEventDispatcher*(cls: DispatcherClass): EventDispatcher =
  ## A plain dispatcher of class `cls`.
  result = EventDispatcher(cls: cls)
  result.initEventDispatcher()

proc property*(d: EventDispatcher; name: string): nil Property =
  ## The property called `name` (Kivy's `property(name, quiet=True)`).
  result = d.cls.findProperty(name)

proc propertyOrQuit(d: EventDispatcher; name: string): Property =
  let p = d.cls.findProperty(name)
  if p == nil: quit "KeyError: " & name & " is not a property of " & d.cls.name
  result = p

proc getProperty*(d: EventDispatcher; name: string): Value =
  ## The value of property `name` (Python's `getattr`).
  result = d.propertyOrQuit(name).get(d)

proc setProperty*(d: EventDispatcher; name: string; value: Value) =
  ## Sets property `name` (Python's `setattr`).
  discard d.propertyOrQuit(name).set(d, value)

proc registerEventType*(d: EventDispatcher; name: string) =
  ## Adds event `name` to this instance. The class must have its default
  ## handler (`setEventHandler`).
  if name.len < 3 or name[0 .. 2] != "on_":
    quit "A new event must start with \"on_\""
  if not d.cls.eventHandlers.hasKey(name):
    quit "Missing default handler <" & name & "> in <" & d.cls.name & ">"
  if not d.eventStack.hasKey(name):
    d.eventStack[name] = newEventObservers()

proc unregisterEventType*(d: EventDispatcher; name: string) =
  ## Removes event `name` and its observers.
  d.eventStack.del(name)

proc isEventType*(d: EventDispatcher; name: string): bool =
  ## Whether `name` is a registered event.
  d.eventStack.hasKey(name)

proc `bind`*(d: EventDispatcher; name: string; cb: PropertyCallback) =
  ## Observes property `name`; the same callback is bound only once.
  d.propertyOrQuit(name).bind(d, cb)

proc `bind`*(d: EventDispatcher; name: string; cb: EventCallback) =
  ## Observes event `name`. An unknown event is ignored, as in Kivy.
  let obs = d.eventStack.getOrDefault(name, nil)
  if obs != nil: obs.bindEvent(cb)

proc fbind*(d: EventDispatcher; name: string; cb: PropertyCallback): int =
  ## Observes property `name`; returns the uid for `unbindUid`, or 0 when
  ## there is no such property.
  let p = d.cls.findProperty(name)
  result = if p != nil: p.fbind(d, cb) else: 0

proc fbind*(d: EventDispatcher; name: string; cb: EventCallback): int =
  ## Observes event `name`; returns the uid for `unbindUid`, or 0 when there
  ## is no such event.
  let obs = d.eventStack.getOrDefault(name, nil)
  result = if obs != nil: obs.fbindEvent(cb) else: 0

proc unbindUid*(d: EventDispatcher; name: string; uid: int) =
  ## Removes the observer of event or property `name` that `fbind` returned
  ## `uid` for.
  if name.len >= 3 and name[0 .. 2] == "on_":
    let obs = d.eventStack.getOrDefault(name, nil)
    if obs != nil: obs.unbindUid(uid)
  else:
    let p = d.cls.findProperty(name)
    if p != nil: p.unbindUid(d, uid)

proc dispatch*(d: EventDispatcher; name: string; args: varargs[Value]): bool =
  ## Calls the observers of event `name`, last bound first, until one returns
  ## true; then, if none did, the class's default handler. Returns true if an
  ## observer stopped the event, else what the default handler returned.
  ## _event.pyx EventDispatcher.dispatch
  var a: seq[Value] = @[]
  for x in args: a.add x
  let obs = d.eventStack.getOrDefault(name, nil)
  if obs == nil: quit "KeyError: " & name & " is not an event of " & d.cls.name
  if obs.dispatchEvent(d, a):
    result = true
  else:
    let h = d.cls.eventHandlers.getOrDefault(name, nil)
    result = if h != nil: h(d, a) else: false
