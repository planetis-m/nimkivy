## Motion events (touches): Kivy's `kivy/input/motionevent.py`, plus the
## provider base of `kivy/input/provider.py`.
##
## A `MotionEvent` is one touch from its start (`maBegin`) through its moves
## (`maUpdate`) to its end (`maEnd`). The provider sets the normalized
## position (`sx`, `sy`, from 0 to 1, y up); the window turns it into window
## coordinates (`x`, `y`, `pos`) with `scaleForScreen`, and widgets that
## work in local coordinates move it with `push`, `applyTransform2d` and
## `pop`. A widget that `grab`s the touch gets its later moves and its end
## again, with `grabCurrent` set to it.
##
## Kivy keeps the grabbing widgets as weak references; here they are plain
## references (see the Gaps in PORTING.md). Out of scope (SCOPE.md): `copy_to`,
## `distance`, the double and triple tap attributes that the postproc modules
## set, `shape`, `z` values other than 0, and rotation.

import std/[monotimes, syncio]

type
  MotionAction* = enum
    ## What a provider reports of a motion event (Kivy's `etype`).
    maBegin = "begin", maUpdate = "update", maEnd = "end"

  MotionProfile* = enum
    ## What a motion event carries (Kivy's `profile` entries).
    mpPos = "pos", mpButton = "button", mpPressure = "pressure",
    mpMultitouchSim = "multitouch_sim"

  MouseButton* = enum
    ## The mouse button of a mouse touch (Kivy's `button` strings).
    mbNone = "", mbLeft = "left", mbRight = "right", mbMiddle = "middle",
    mbMouse4 = "mouse4", mbMouse5 = "mouse5", mbScrollUp = "scrollup",
    mbScrollDown = "scrolldown", mbScrollLeft = "scrollleft", mbScrollRight = "scrollright"

  PushedAttrs = object
    # The default `push_attrs` of motionevent.py, saved by `push`.
    x, y, z, dx, dy, dz, ox, oy, oz, px, py, pz: float
    pos: (float, float)
    typeId: string

  MotionEvent* = ref object of RootObj
    ## A touch or another motion event. Subtypes may override `depack`
    ## (Kivy's MouseMotionEvent, SDL2MotionEvent, UnitTestTouch).
    device*: string               ## the provider that made it
    id*: string                   ## its id within the provider
    uid*: int                     ## unique in the program
    isTouch*: bool                ## a touch (dispatched to on_touch_*)
    typeId*: string               ## "touch" or "hover"
    profile*: set[MotionProfile]  ## what it carries
    button*: MouseButton          ## the mouse button; `mbNone` for none
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
    claimedBy*: seq[RootRef]
      ## The objects that took the touch as theirs (Kivy's `touch.ud`, which
      ## in scope only ButtonBehavior uses, with itself as the key).
    grabList*: seq[RootRef]       ## the widgets that grabbed it
    grabExclusiveClass*: nil RootRef
    grabState*: bool              ## true while dispatched to grabbing widgets
    grabCurrent*: nil RootRef     ## the grabbing widget being dispatched to
    syncWithDispatch*: bool
    pushAttrsStack: seq[PushedAttrs]
    hasOrigin: bool               # Kivy's `osx is not None`
    keepPrevPos: bool
    firstDispatchDone: bool

  InputEvent* = (MotionAction, MotionEvent)
    ## A provider's event: what happened, and the motion event.

  MotionEventProvider* = ref object of RootObj
    ## A source of motion events (kivy/input/provider.py). The event loop
    ## calls `update` every frame.
    device*: string

  Counter = ref object
    # MotionEvent.__uniq_id
    value: int

let uniqId = Counter(value: 0)

proc time(): float =
  # Kivy's time.time(): only differences matter.
  float(getMonoTime().ticks) / 1e9

# ------------------------------------------------------------------ MotionEvent

method depack*(me: MotionEvent; sx, sy: float) {.base.} =
  ## Takes the provider's new normalized position, keeps the first and
  ## previous positions and computes the last move. A subtype that carries
  ## more (a mouse button) overrides it and calls this base.
  ## motionevent.py MotionEvent.depack (the subtypes' depack set `sx` and
  ## `sy` from their `args`)
  me.sx = sx
  me.sy = sy
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

proc initMotionEvent*(me: MotionEvent; device, id: sink string; sx, sy: float;
    isTouch = false; typeId: sink string = "") =
  ## Sets up a new motion event of a subtype, built with `T()` first, at the
  ## normalized position (`sx`, `sy`). motionevent.py MotionEvent.__init__
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
  me.profile = {}
  me.id = id
  me.sz = 0.0
  me.hasOrigin = false
  me.x = 0.0
  me.y = 0.0
  me.z = 0.0
  me.pos = (0.0, 0.0)
  me.timeStart = now
  me.timeUpdate = now
  me.timeEnd = -1
  me.claimedBy = @[]
  me.syncWithDispatch = true
  me.keepPrevPos = true
  me.firstDispatchDone = false
  me.depack(sx, sy)

proc grab*(me: MotionEvent; widget: sink RootRef; exclusive = false) =
  ## Grabs the event: `widget` gets its later moves and its end, with
  ## `grabCurrent` set to it. An exclusive grab cannot be joined; a second
  ## grab then stops the program, as Kivy raises.
  # GAP: the grab list holds the widget strongly, where Kivy holds a weak
  # reference and drops a widget that is gone, because Nimony has no weak
  # references
  if me.grabExclusiveClass != nil:
    quit "the touch is grabbed exclusively and cannot be grabbed again"
  if exclusive:
    me.grabExclusiveClass = widget
  me.grabList.add widget

proc ungrab*(me: MotionEvent; widget: RootRef) =
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

proc move*(me: MotionEvent; sx, sy: float) =
  ## Moves to a new normalized position.
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
  me.depack(sx, sy)

proc scaleForScreen*(me: MotionEvent; w, h: float) =
  ## Turns the normalized positions into window coordinates, x from 0 to
  ## `w` - 1 and y from 0 to `h` - 1. Rotation and the soft keyboard modes
  ## (`smode`, `kheight`) are out of scope.
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
  mpButton in me.profile and
    me.button in {mbScrollUp, mbScrollDown, mbScrollLeft, mbScrollRight}

proc `$`*(me: MotionEvent): string =
  ## `<MotionEvent spos=(sx, sy) pos=(x, y)>`.
  "<MotionEvent spos=(" & $me.sx & ", " & $me.sy & ") pos=(" & $me.pos[0] & ", " &
    $me.pos[1] & ")>"

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
