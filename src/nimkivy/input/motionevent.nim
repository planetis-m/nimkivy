## Motion events (touches): Kivy's `kivy/input/motionevent.py`, plus the
## provider base of `kivy/input/provider.py`.
##
## A `MotionEvent` is one touch from its start ("begin") through its moves
## ("update") to its end ("end"). The provider sets the normalized position
## (`sx`, `sy`, from 0 to 1, y up); the window turns it into window
## coordinates (`x`, `y`, `pos`) with `scaleForScreen`, and widgets that
## work in local coordinates move it with `push`, `applyTransform2d` and
## `pop`. A widget that `grab`s the touch gets its later moves and its end
## again, with `grabCurrent` set to it.
##
## Kivy keeps the grabbing widgets as weak references; here they are plain
## references (see the Gaps in PORTING.md). Out of scope (SCOPE.md): `copy_to`,
## `distance`, the double and triple tap attributes that the postproc modules
## set, `shape`, `z` values other than 0, and rotation.

import std/[monotimes, strutils, syncio]
import ../event

type
  TouchUserData* = object
    ## `ud`: a small table keyed by an object (compared by identity) or a
    ## string, as Kivy's `touch.ud` dict is used.
    keys: seq[Value]
    values: seq[Value]

  PushedAttrs = object
    # The default `push_attrs` of motionevent.py, saved by `push`.
    x, y, z, dx, dy, dz, ox, oy, oz, px, py, pz: float
    pos: (float, float)
    typeId: string

  MotionEvent* = ref object of RootObj
    ## A touch or another motion event. Subtypes set `sx` and `sy` in
    ## `depack` (Kivy's MouseMotionEvent, SDL2MotionEvent, UnitTestTouch).
    device*: string               ## the provider that made it
    id*: string                   ## its id within the provider
    uid*: int                     ## unique in the program
    isTouch*: bool                ## a touch (dispatched to on_touch_*)
    typeId*: string               ## "touch" or "hover"
    profile*: seq[string]         ## what it carries: "pos", "button", ...
    button*: string               ## "left", "right", "middle", "scrollup", ...; "" for none
    sx*, sy*, sz*: float          ## the position, normalized (0 to 1)
    osx*, osy*, osz*: float       ## the first position, normalized
    psx*, psy*, psz*: float       ## the previous position, normalized
    dsx*, dsy*, dsz*: float       ## the last move, normalized
    x*, y*, z*: float             ## the position in window (or local) coordinates
    ox*, oy*, oz*: float          ## the first position
    px*, py*, pz*: float          ## the previous position
    dx*, dy*, dz*: float          ## the last move
    pos*: (float, float)          ## `(x, y)`
    timeStart*: float             ## when it began, in seconds
    timeUpdate*: float            ## when it last moved
    timeEnd*: float               ## when it ended; -1 before
    ud*: TouchUserData            ## data widgets attach to it
    grabList*: seq[EventDispatcher]   ## the widgets that grabbed it
    grabExclusiveClass*: nil EventDispatcher
    grabState*: bool              ## true while dispatched to grabbing widgets
    grabCurrent*: nil EventDispatcher ## the grabbing widget being dispatched to
    syncWithDispatch*: bool
    pushAttrsStack: seq[PushedAttrs]
    hasOrigin: bool               # Kivy's `osx is not None`
    keepPrevPos: bool
    firstDispatchDone: bool

  InputEvent* = (string, MotionEvent)
    ## A provider's event: "begin", "update" or "end", and the motion event.

  MotionEventProvider* = ref object of RootObj
    ## A source of motion events (kivy/input/provider.py). The event loop
    ## calls `update` every frame.
    device*: string

  Counter = ref object
    # MotionEvent.__uniq_id
    value: int

let uniqId = Counter(value: 0)

proc time(): float =
  # Python's time.time() as Kivy uses it here: only differences matter.
  float(getMonoTime().ticks) / 1e9

# ------------------------------------------------------------------ ud

proc find(ud: TouchUserData; key: Value): int =
  result = -1
  for i in 0 ..< ud.keys.len:
    if ud.keys[i] == key: return i

proc contains*(ud: TouchUserData; key: Value): bool =
  ## Whether `key` is in `ud` (Python's `key in touch.ud`).
  ud.find(key) >= 0

proc contains*(ud: TouchUserData; key: string): bool =
  ## Whether the string `key` is in `ud`.
  ud.contains(toValue(key))

proc `[]=`*(ud: var TouchUserData; key, value: Value) =
  ## Sets `ud[key]`.
  let i = ud.find(key)
  if i >= 0:
    ud.values[i] = value
  else:
    ud.keys.add key
    ud.values.add value

proc `[]=`*(ud: var TouchUserData; key: string; value: Value) =
  ## Sets `ud[key]` for a string key.
  ud[toValue(key)] = value

proc getOrDefault*(ud: TouchUserData; key: Value; default = noneValue()): Value =
  ## `ud.get(key, default)`.
  let i = ud.find(key)
  result = if i >= 0: ud.values[i] else: default

proc getOrDefault*(ud: TouchUserData; key: string; default = noneValue()): Value =
  ## `ud.get(key, default)` for a string key.
  ud.getOrDefault(toValue(key), default)

proc del*(ud: var TouchUserData; key: Value) =
  ## Removes `key`, if present.
  let i = ud.find(key)
  if i >= 0:
    ud.keys.delete(i)
    ud.values.delete(i)

proc len*(ud: TouchUserData): int {.inline.} =
  ## The number of entries.
  ud.keys.len

# ------------------------------------------------------------------ MotionEvent

method depack*(me: MotionEvent; args: seq[Value]) {.base.} =
  ## Takes the provider's arguments. Subtypes set `sx` and `sy` (and the
  ## other normalized values), then call this base, which keeps the first
  ## and previous positions and computes the last move.
  ## motionevent.py MotionEvent.depack
  if not me.hasOrigin or me.syncWithDispatch and not me.firstDispatchDone:
    me.hasOrigin = true
    me.osx = me.sx
    me.psx = me.sx
    me.osy = me.sy
    me.psy = me.sy
    me.osz = me.sz
    me.psz = me.sz
  me.dsx = me.sx - me.psx
  me.dsy = me.sy - me.psy
  me.dsz = me.sz - me.psz

proc initMotionEvent*(me: MotionEvent; device, id: string; args: seq[Value];
    isTouch = false; typeId = "") =
  ## Sets up a new motion event of a subtype, built with `T()` first, and
  ## depacks `args`. motionevent.py MotionEvent.__init__
  inc uniqId.value
  let now = time()
  me.isTouch = isTouch
  me.typeId = typeId
  me.pushAttrsStack = @[]
  me.uid = uniqId.value
  me.device = device
  me.grabList = @[]
  me.grabExclusiveClass = nil
  me.grabState = false
  me.grabCurrent = nil
  me.button = ""
  me.profile = @[]
  me.id = id
  me.sx = 0.0
  me.sy = 0.0
  me.sz = 0.0
  me.hasOrigin = false
  me.x = 0.0
  me.y = 0.0
  me.z = 0.0
  me.pos = (0.0, 0.0)
  me.timeStart = now
  me.timeUpdate = now
  me.timeEnd = -1
  me.ud = TouchUserData(keys: @[], values: @[])
  me.syncWithDispatch = true
  me.keepPrevPos = true
  me.firstDispatchDone = false
  me.depack(args)

proc grab*(me: MotionEvent; widget: EventDispatcher; exclusive = false) =
  ## Grabs the event: `widget` gets its later moves and its end, with
  ## `grabCurrent` set to it. An exclusive grab cannot be joined; a second
  ## grab then stops the program, as Kivy raises.
  # GAP: the grab list holds the widget strongly, where Kivy holds a weak
  # reference and drops a widget that is gone, because Nimony has no weak
  # references
  if me.grabExclusiveClass != nil:
    quit "Exception: Event is exclusive and cannot be grabbed"
  if exclusive:
    me.grabExclusiveClass = widget
  me.grabList.add widget

proc ungrab*(me: MotionEvent; widget: EventDispatcher) =
  ## Removes `widget` from the grab list.
  if me.grabExclusiveClass == widget:
    me.grabExclusiveClass = nil
  let i = me.grabList.find(widget)
  if i >= 0:
    me.grabList.delete(i)

proc dispatchDone*(me: MotionEvent) =
  ## Called by the event loop after the event was dispatched.
  me.keepPrevPos = true
  me.firstDispatchDone = true

proc move*(me: MotionEvent; args: seq[Value]) =
  ## Moves to a new position from the provider's arguments.
  if me.syncWithDispatch:
    if me.keepPrevPos:
      me.psx = me.sx
      me.psy = me.sy
      me.psz = me.sz
      me.keepPrevPos = false
  else:
    me.psx = me.sx
    me.psy = me.sy
    me.psz = me.sz
  me.timeUpdate = time()
  me.depack(args)

proc scaleForScreen*(me: MotionEvent; w, h: float; smode = ""; kheight = 0.0) =
  ## Turns the normalized positions into window coordinates, x from 0 to
  ## `w` - 1 and y from 0 to `h` - 1. Rotation is out of scope (0).
  ## motionevent.py MotionEvent.scale_for_screen
  let xMax = max(0.0, w - 1)
  let yMax = max(0.0, h - 1)
  me.x = me.sx * xMax
  me.y = me.sy * yMax
  me.ox = me.osx * xMax
  me.oy = me.osy * yMax
  me.px = me.psx * xMax
  me.py = me.psy * yMax
  # p is None: z_max is 0.
  me.z = 0.0
  me.oz = 0.0
  me.pz = 0.0
  if smode.len > 0:
    if smode == "pan" or smode == "below_target":
      me.y -= kheight
      me.oy -= kheight
      me.py -= kheight
    elif smode == "scale":
      let offset = kheight * (me.y - h) / (h - kheight)
      me.y += offset
      me.oy += offset
      me.py += offset
  me.dx = me.x - me.px
  me.dy = me.y - me.py
  me.dz = me.z - me.pz
  me.pos = (me.x, me.y)

proc push*(me: MotionEvent) =
  ## Saves the position attributes (Kivy's default `push_attrs`).
  me.pushAttrsStack.add PushedAttrs(x: me.x, y: me.y, z: me.z, dx: me.dx, dy: me.dy,
    dz: me.dz, ox: me.ox, oy: me.oy, oz: me.oz, px: me.px, py: me.py, pz: me.pz,
    pos: me.pos, typeId: me.typeId)

proc pop*(me: MotionEvent) =
  ## Restores the attributes saved by the last `push`.
  let a = me.pushAttrsStack.pop()
  me.x = a.x
  me.y = a.y
  me.z = a.z
  me.dx = a.dx
  me.dy = a.dy
  me.dz = a.dz
  me.ox = a.ox
  me.oy = a.oy
  me.oz = a.oz
  me.px = a.px
  me.py = a.py
  me.pz = a.pz
  me.pos = a.pos
  me.typeId = a.typeId

proc applyTransform2d*(me: MotionEvent;
    transform: proc (x, y: float): (float, float) {.closure.}) =
  ## Moves x, y, px, py, ox and oy through `transform` (a widget's
  ## `toWidget`, for example) and recomputes dx and dy.
  (me.x, me.y) = transform(me.x, me.y)
  me.pos = (me.x, me.y)
  (me.px, me.py) = transform(me.px, me.py)
  (me.ox, me.oy) = transform(me.ox, me.oy)
  me.dx = me.x - me.px
  me.dy = me.y - me.py

proc updateTimeEnd*(me: MotionEvent) =
  ## Records the end time.
  me.timeEnd = time()

proc dpos*(me: MotionEvent): (float, float) {.inline.} =
  ## The last move, `(dx, dy)`.
  (me.dx, me.dy)

proc opos*(me: MotionEvent): (float, float) {.inline.} =
  ## The first position, `(ox, oy)`.
  (me.ox, me.oy)

proc ppos*(me: MotionEvent): (float, float) {.inline.} =
  ## The previous position, `(px, py)`.
  (me.px, me.py)

proc spos*(me: MotionEvent): (float, float) {.inline.} =
  ## The normalized position, `(sx, sy)`.
  (me.sx, me.sy)

proc isMouseScrolling*(me: MotionEvent): bool =
  ## Whether the event is a mouse wheel step.
  "button" in me.profile and "scroll" in me.button

proc `$`*(me: MotionEvent): string =
  ## `<MotionEvent spos=(sx, sy) pos=(x, y)>`.
  "<MotionEvent spos=(" & $me.sx & ", " & $me.sy & ") pos=(" & $me.pos[0] & ", " &
    $me.pos[1] & ")>"

proc toValue*(me: MotionEvent): Value {.inline.} =
  ## The event as an event argument.
  toValue(RootRef(me))

proc toMotionEvent*(v: Value): MotionEvent =
  ## The motion event in an event argument; stops the program on another
  ## value, which would be a bug.
  if v.kind != vkObject:
    quit "TypeError: not a MotionEvent"
  let o = v.obj
  if o == nil or not (o of MotionEvent):
    quit "TypeError: not a MotionEvent"
  result = MotionEvent(o)

# ------------------------------------------------------------------ providers

method start*(p: MotionEventProvider) {.base.} =
  ## Starts the provider.
  discard

method stop*(p: MotionEventProvider) {.base.} =
  ## Stops the provider.
  discard

method update*(p: MotionEventProvider): seq[InputEvent] {.base.} =
  ## The events that arrived since the last call, oldest first. Kivy's
  ## `update(dispatch_fn)` calls `dispatch_fn` with each; a method with a
  ## closure parameter does not compile (planetis-m/nimony-bugs-llms#333,
  ## bug-reports/06), so they are returned in the same order instead.
  @[]
