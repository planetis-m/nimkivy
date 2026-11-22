## The window base: Kivy's `kivy/core/window/__init__.py` (WindowBase), and
## the `WidgetBase` that widgets and the window share.
##
## `WindowBase` holds the window's properties (`size`, `width`, `height`,
## `center`, `clearcolor`, `title`, `dpi`), its root widgets, its canvas,
## and the default handlers of its events: touches go to the children,
## newest first, until one returns true; key 27 closes the app when
## `Config.kivy.exitOnEscape` is set; a resize updates the children's size
## and position from their hints. The SDL3 window in `window/window_sdl3`
## adds the system window, its events and drawing.
##
## Kivy's `WidgetBase` (in `uix/widget.py`) is here, because the window and
## the event loop need what Widget and Window have in common: the `parent`
## and `children` properties, a canvas, the touch events and the coordinate
## methods. Widget (layer 6) is a `HintedWidget`, a `WidgetBase` with the
## box (`x`, `y`, `width`, `height`, `pos`, `size`, `right`, `top`,
## `center`) and the size and position hints, which the window reads and
## binds typed; the window is a `WidgetBase`,
## since a widget's parent can be the window (Python needs no common base
## for that).
##
## Kivy calls `stopTouchApp` and `App.get_running_app` from inside this
## module; here those are below it (`base`, `app`), so `base` and `app` fill
## in `stopTouchApp`, `quitEventLoop`, `runningApp`, `pauseApp` and
## `resumeApp` on the window.
##
## Out of scope (SCOPE.md): rotation, the soft keyboard and the keyboard
## request API, text input, the cursor, hover, drag and drop, joysticks,
## event managers, window position and opacity, shaped windows and icons.

import std/[os, sequtils, strutils, syncio]
import ../[properties, props, clock, config, metrics]
import ../graphics/instructions
import ../input/motionevent

export properties, props, motionevent

type
  CanvasLayer* = enum
    ## Where `addWidget` puts a child's canvas (Kivy's `canvas=None`,
    ## `'before'`, `'after'`).
    layerCanvas, layerBefore, layerAfter

  Modifier* = enum
    ## A modifier key held during a key or mouse event.
    modShift = "shift", modAlt = "alt", modCtrl = "ctrl", modMeta = "meta",
    modNumlock = "numlock", modCapslock = "capslock"

  PosKey* = enum
    ## A key of `posHint` (Kivy's `pos_hint` keys).
    phX = "x", phRight = "right", phCenterX = "center_x",
    phY = "y", phTop = "top", phCenterY = "center_y",
    phPos = "pos", phCenter = "center"

  PosHintEntry* = object
    ## One position hint: a share of the parent's size.
    key*: PosKey
    value*: float              ## the hint, for every key but `phPos` and `phCenter`
    pair*: (float, float)      ## the hint for `phPos` and `phCenter`

  PosHint* = object
    ## A widget's position hints in the order they were given, as Python's
    ## dict keeps them. Two are equal with the same keys and values in any
    ## order, as dicts compare.
    entries*: seq[PosHintEntry]

  TouchCallback* = proc (touch: MotionEvent): bool {.closure.}
    ## An observer of a touch event; true stops the touch.

  # GAP: `WidgetBase` is written by hand, not in a `properties:` block, and
  # the hints are on its subtype `HintedWidget`, because a type declared by
  # a module-level template cannot refer to itself through `seq`
  # (`children`) (planetis-m/nimony-bugs-llms#337)
  WidgetBase* = ref object of EventDispatcher
    ## What every widget and the window have: `parent` and `children`
    ## properties, a canvas, the touch events `touchDown`, `touchMove` and
    ## `touchUp`, and coordinate methods. Build it with `T(cls: ...,
    ## canvas: newCanvas())`, then call `initWidgetBase`. It stays an
    ## EventDispatcher (`cls` names the class) while widgets below it
    ## still declare phase-1 properties on their classes (ScreenManager
    ## and ModalView until step 5); step 6 makes it a `ref object of
    ## RootObj`.
    canvas*: Canvas
    parentStore: nil WidgetBase
    parentObs: Observers[proc (v: nil WidgetBase) {.closure.}]
    childrenStore: seq[WidgetBase]
    childrenObs: Observers[proc (v: seq[WidgetBase]) {.closure.}]
    touchDownObs, touchMoveObs, touchUpObs: Observers[TouchCallback]

  WindowHook* = proc () {.closure.}
    ## A call into a module below this one (`base`, `app`).

  AppPauseHook* = proc (): bool {.closure.}
    ## The running app's `pause` event (`app`); false stops the app.

  RootBindings = object
    # What the window bound on a root widget, to unbind it on removal.
    child: WidgetBase
    bindings: array[6, Binding]  # posHint, sizeHint, sizeHintMax, sizeHintMin, size, pos

let WidgetBaseClass* = newDispatcherClass("WidgetBase")
  ## The class of `WidgetBase`: its subclasses' classes derive from it.

# ------------------------------------------------------------------ PosHint

func `==`*(a, b: PosHint): bool =
  ## Python's dict equality: the same keys with equal values, in any order.
  if a.entries.len != b.entries.len:
    return false
  result = true
  for ea in a.entries:
    var found = false
    for eb in b.entries:
      if eb.key == ea.key:
        found = eb.value == ea.value and eb.pair == ea.pair
    if not found:
      return false

func len*(h: PosHint): int {.inline.} =
  ## The number of hints.
  h.entries.len

func add*(h: var PosHint; key: PosKey; value: float) =
  ## Sets the hint for `key` (not `phPos` or `phCenter`); a key already
  ## given keeps its place, as in a Python dict.
  for e in h.entries.mitems:
    if e.key == key:
      e.value = value
      return
  h.entries.add PosHintEntry(key: key, value: value, pair: (0.0, 0.0))

func add*(h: var PosHint; key: PosKey; pair: (float, float)) =
  ## Sets the hint for `phPos` or `phCenter`.
  for e in h.entries.mitems:
    if e.key == key:
      e.pair = pair
      return
  h.entries.add PosHintEntry(key: key, value: 0.0, pair: pair)

func toPosHint*(hints: openArray[(PosKey, float)]): PosHint =
  ## Numeric hints, for example `toPosHint({phTop: 0.9})`. A key given twice
  ## keeps its first place and its last value, as in a Python dict literal.
  result = PosHint(entries: @[])
  for (key, value) in hints:
    result.add(key, value)

# ------------------------------------------------------------------ WidgetBase

proc initWidgetBase*(w: WidgetBase) =
  ## Sets up a new widget or window: no parent, no children.
  w.initEventDispatcher()
  w.parentStore = nil
  w.childrenStore = @[]

proc parent*(w: WidgetBase): nil WidgetBase {.inline.} =
  ## The parent widget or window, or nil.
  w.parentStore

proc `parent=`*(w: WidgetBase; p: nil WidgetBase) =
  ## Sets the parent (nil: none); its observers run if it changed.
  if w.parentStore != p:
    w.parentStore = p
    let value = w.parentStore
    for cb in w.parentObs.live: cb(value)

proc bindParent*(w: WidgetBase; cb: proc (v: nil WidgetBase) {.closure.}): Binding =
  ## Calls `cb` with the new parent whenever it changes.
  w.parentObs.add(cb)

proc unbindParent*(w: WidgetBase; b: Binding) =
  ## Removes an observer of `parent`.
  w.parentObs.remove(b)

proc children*(w: WidgetBase): seq[WidgetBase] {.inline.} =
  ## The children, newest first.
  w.childrenStore

proc `children=`*(w: WidgetBase; children: seq[WidgetBase]) =
  ## Sets the children; their observers run if they changed.
  if w.childrenStore != children:
    w.childrenStore = children
    let value = w.childrenStore
    for cb in w.childrenObs.live: cb(value)

proc bindChildren*(w: WidgetBase; cb: proc (v: seq[WidgetBase]) {.closure.}): Binding =
  ## Calls `cb` with the new children whenever they change.
  w.childrenObs.add(cb)

proc unbindChildren*(w: WidgetBase; b: Binding) =
  ## Removes an observer of `children`.
  w.childrenObs.remove(b)

method onTouchDown*(w: WidgetBase; touch: MotionEvent): bool {.base.} =
  ## The default `touchDown` handler (Kivy's `on_touch_down`). Returns true
  ## to stop the touch.
  false

method onTouchMove*(w: WidgetBase; touch: MotionEvent): bool {.base.} =
  ## The default `touchMove` handler.
  false

method onTouchUp*(w: WidgetBase; touch: MotionEvent): bool {.base.} =
  ## The default `touchUp` handler.
  false

proc bindTouchDown*(w: WidgetBase; cb: TouchCallback): Binding =
  ## Observes `touchDown`; observers run last bound first, before the
  ## default handler, and one that returns true stops the touch.
  w.touchDownObs.add(cb)

proc unbindTouchDown*(w: WidgetBase; b: Binding) =
  ## Removes an observer of `touchDown`.
  w.touchDownObs.remove(b)

proc dispatchTouchDown*(w: WidgetBase; touch: MotionEvent): bool =
  ## Dispatches `touchDown`: the observers, then `onTouchDown`, until one
  ## returns true. _event.pyx EventDispatcher.dispatch
  result = false
  for cb in w.touchDownObs.liveReversed:
    if not result: result = cb(touch)
  if not result: result = w.onTouchDown(touch)

proc bindTouchMove*(w: WidgetBase; cb: TouchCallback): Binding =
  ## Observes `touchMove`.
  w.touchMoveObs.add(cb)

proc unbindTouchMove*(w: WidgetBase; b: Binding) =
  ## Removes an observer of `touchMove`.
  w.touchMoveObs.remove(b)

proc dispatchTouchMove*(w: WidgetBase; touch: MotionEvent): bool =
  ## Dispatches `touchMove`, as `dispatchTouchDown`.
  result = false
  for cb in w.touchMoveObs.liveReversed:
    if not result: result = cb(touch)
  if not result: result = w.onTouchMove(touch)

proc bindTouchUp*(w: WidgetBase; cb: TouchCallback): Binding =
  ## Observes `touchUp`.
  w.touchUpObs.add(cb)

proc unbindTouchUp*(w: WidgetBase; b: Binding) =
  ## Removes an observer of `touchUp`.
  w.touchUpObs.remove(b)

proc dispatchTouchUp*(w: WidgetBase; touch: MotionEvent): bool =
  ## Dispatches `touchUp`, as `dispatchTouchDown`.
  result = false
  for cb in w.touchUpObs.liveReversed:
    if not result: result = cb(touch)
  if not result: result = w.onTouchUp(touch)

method getRootWindow*(w: WidgetBase): nil WidgetBase {.base.} =
  ## The window the widget is in, or nil. Widget.get_root_window
  let p = w.parent
  result = if p == nil: nil else: p.getRootWindow()

method toWidget*(w: WidgetBase; x, y: float; relative = false): (float, float) {.base.} =
  ## Window coordinates to this widget's coordinates. Widget (layer 6)
  ## overrides it; here coordinates are unchanged.
  (x, y)

method toParent*(w: WidgetBase; x, y: float; relative = false): (float, float) {.base.} =
  ## This widget's coordinates to its parent's; unchanged here.
  (x, y)

method toWindow*(w: WidgetBase; x, y: float; initial = true;
    relative = false): (float, float) {.base.} =
  ## This widget's coordinates to window coordinates; unchanged here.
  (x, y)

method addWidget*(w: WidgetBase; widget: WidgetBase; index = 0;
    canvas = layerCanvas) {.base.} =
  ## Adds a child. Widget (layer 6) and the window override it.
  discard

method removeWidget*(w: WidgetBase; widget: WidgetBase) {.base.} =
  ## Removes a child.
  discard

proc toWidgetFn(w: WidgetBase): proc (x, y: float): (float, float) {.closure.} =
  # `w.to_widget` as a callable.
  result = proc (x, y: float): (float, float) {.closure.} = w.toWidget(x, y)

proc toParentFn(w: WidgetBase): proc (x, y: float): (float, float) {.closure.} =
  # `w.to_parent` as a callable.
  result = proc (x, y: float): (float, float) {.closure.} = w.toParent(x, y)

# ------------------------------------------------------------------ HintedWidget, WindowBase

properties:
  type
    HintedWidget* = ref object of WidgetBase
      ## A widget's box and its size and position hints: what the window
      ## and the layouts size and place. Widget (layer 6) is one.
      ## uix/widget.py Widget (its geometry and hint properties)
      x* {.prop.}: float = 0.0         ## the left edge
      y* {.prop.}: float = 0.0         ## the bottom edge (y goes up)
      width* {.prop.}: float = 100.0
      height* {.prop.}: float = 100.0
      pos* {.refs: (x, y).}: (float, float)
      size* {.refs: (width, height).}: (float, float)
      right* {.alias: (getRight, setRight), deps: (x, width), cache.}: float
      top* {.alias: (getTop, setTop), deps: (y, height), cache.}: float
      centerX* {.alias: (getCenterX, setCenterX), deps: (x, width), cache.}: float
      centerY* {.alias: (getCenterY, setCenterY), deps: (y, height), cache.}: float
      center* {.refs: (centerX, centerY).}: (float, float)
      sizeHintX* {.prop.}: Opt[float] = some(1.0)
      sizeHintY* {.prop.}: Opt[float] = some(1.0)
      sizeHint* {.refs: (sizeHintX, sizeHintY).}: (Opt[float], Opt[float])
      posHint* {.prop.}: PosHint
      sizeHintMinX* {.prop.}: Opt[float] = none[float]()
      sizeHintMinY* {.prop.}: Opt[float] = none[float]()
      sizeHintMin* {.refs: (sizeHintMinX, sizeHintMinY).}: (Opt[float], Opt[float])
      sizeHintMaxX* {.prop.}: Opt[float] = none[float]()
      sizeHintMaxY* {.prop.}: Opt[float] = none[float]()
      sizeHintMax* {.refs: (sizeHintMaxX, sizeHintMaxY).}: (Opt[float], Opt[float])

    WindowBase* = ref object of WidgetBase
      ## The window. Its system part is `WindowSDL` (window/window_sdl3).
      initialized*: bool            ## the system window exists
      triggerCreateWindow*: nil ClockEvent  ## recreates (resizes) the window before the next frame
      modifiers*: set[Modifier]     ## the modifier keys held
      lastResize: (float, float)
      hasLastResize: bool
      rootBindings: seq[RootBindings]
      stopTouchApp*: nil WindowHook ## base.stopTouchApp; set by `base`
      quitEventLoop*: nil WindowHook ## sets EventLoop.quit; set by `base`
      runningApp*: nil RootRef      ## App.get_running_app(); set by `app`
      pauseApp*: nil AppPauseHook   ## dispatches the running app's `pause`; set by `app`
      resumeApp*: nil WindowHook    ## dispatches the running app's `resume`; set by `app`
      createWindowBindings: array[2, Binding]
      density* {.prop.}: float = 1.0  ## Kivy's `_density`: pixels per window coordinate
      rawSize* {.prop.}: (float, float) = (0.0, 0.0)  ## Kivy's `_size`, in window coordinates
      size* {.alias: (getSize, setSize), deps: rawSize, eager.}: (float, float)
      clearcolor* {.color.}: Rgba = [0.0, 0, 0, 1]
      width* {.alias: getWidth, deps: (rawSize, density), eager.}: float
      height* {.alias: getHeight, deps: (rawSize, density), eager.}: float
      center* {.alias: getCenter, deps: (width, height), eager.}: (float, float)
      systemSize* {.alias: (getSystemSize, setSystemSize), deps: rawSize, eager.}: (float, float)
      title* {.prop.}: string = "Kivy"
      dpi* {.prop.}: float = 96.0
      mouseDown* {.event.}: proc (x: float; y: float; button: MouseButton;
        modifiers: set[Modifier])
      mouseMove* {.event.}: proc (x: float; y: float; modifiers: set[Modifier])
      mouseUp* {.event.}: proc (x: float; y: float; button: MouseButton;
        modifiers: set[Modifier])
      keyDown* {.event.}: proc (key: int; scancode: int; codepoint: string;
        modifiers: set[Modifier])
      keyUp* {.event.}: proc (key: int; scancode: int)
      keyboard* {.event.}: proc (key: int; scancode: int; codepoint: string;
        modifiers: set[Modifier])
      requestClose* {.event.}: proc (keyboard: bool)
      draw* {.event.}: proc ()
      flip* {.event.}: proc ()
      resize* {.event.}: proc (width: float; height: float)
      preResize* {.event.}: proc (width: float; height: float)
      close* {.event.}: proc ()
      motion* {.event.}: proc (action: MotionAction; me: MotionEvent)

  # The aliases of the box: Widget's right, top, center_x and center_y.

  proc getRight(w: HintedWidget): float = w.x + w.width

  proc setRight(w: HintedWidget; v: float): bool =
    w.x = v - w.width
    result = false

  proc getTop(w: HintedWidget): float = w.y + w.height

  proc setTop(w: HintedWidget; v: float): bool =
    w.y = v - w.height
    result = false

  proc getCenterX(w: HintedWidget): float = w.x + w.width / 2.0

  proc setCenterX(w: HintedWidget; v: float): bool =
    w.x = v - w.width / 2.0
    result = false

  proc getCenterY(w: HintedWidget): float = w.y + w.height / 2.0

  proc setCenterY(w: HintedWidget; v: float): bool =
    w.y = v - w.height / 2.0
    result = false

  # The hints' setters from plain numbers (none: no hint).

  proc `sizeHintX=`*(w: HintedWidget; v: float) =
    ## Sets the width hint.
    w.sizeHintX = some(v)

  proc `sizeHintY=`*(w: HintedWidget; v: float) =
    ## Sets the height hint.
    w.sizeHintY = some(v)

  proc `sizeHint=`*(w: HintedWidget; h: (float, float)) =
    ## Sets both hints.
    w.sizeHint = (some(h[0]), some(h[1]))

  proc `sizeHintMinX=`*(w: HintedWidget; v: float) =
    ## Sets the smallest width the hint may give.
    w.sizeHintMinX = some(v)

  proc `sizeHintMinY=`*(w: HintedWidget; v: float) =
    ## Sets the smallest height the hint may give.
    w.sizeHintMinY = some(v)

  proc `sizeHintMin=`*(w: HintedWidget; h: (float, float)) =
    ## Sets both minimums.
    w.sizeHintMin = (some(h[0]), some(h[1]))

  proc `sizeHintMaxX=`*(w: HintedWidget; v: float) =
    ## Sets the largest width the hint may give.
    w.sizeHintMaxX = some(v)

  proc `sizeHintMaxY=`*(w: HintedWidget; v: float) =
    ## Sets the largest height the hint may give.
    w.sizeHintMaxY = some(v)

  proc `sizeHintMax=`*(w: HintedWidget; h: (float, float)) =
    ## Sets both maximums.
    w.sizeHintMax = (some(h[0]), some(h[1]))

  proc `posHint=`*(w: HintedWidget; hints: openArray[(PosKey, float)]) =
    ## Sets numeric position hints, for example `w.posHint = {phTop: 0.9}`.
    w.posHint = toPosHint(hints)

  # ---------------------------------------------------------------- WindowBase

  method glSize*(w: WindowBase): (float, float) {.base.} =
    ## The drawable size in pixels (Kivy's `_win._get_gl_size()`). The
    ## system window overrides it; here it is `rawSize`.
    w.rawSize

  proc sizeValue(w: WindowBase): (float, float) =
    # WindowBase._get_size, without rotation and the soft keyboard (out of
    # scope).
    result = w.rawSize
    when defined(windows):
      result = w.glSize()
    else:
      if w.density != 1:
        result = w.glSize()

  proc getSize(w: WindowBase): (float, float) = w.sizeValue()

  proc setSize(w: WindowBase; v: (float, float)): bool =
    # WindowBase._set_size
    if w.rawSize != v:
      w.rawSize = v
      discard w.dispatchPreResize(v[0], v[1])
    result = false

  proc getWidth(w: WindowBase): float = w.sizeValue()[0]

  proc getHeight(w: WindowBase): float = w.sizeValue()[1]

  proc getCenter(w: WindowBase): (float, float) = (w.width / 2, w.height / 2)

  proc getSystemSize(w: WindowBase): (float, float) = w.rawSize

  proc setSystemSize(w: WindowBase; v: (float, float)): bool =
    w.rawSize = v
    result = false

  method clear*(w: WindowBase) {.base.} =
    ## Fills the window with `clearcolor`. The system window draws it.
    discard

  method drawCanvas*(w: WindowBase) {.base.} =
    ## Draws the canvas (Kivy's `render_context.draw()`).
    discard

  method flip*(w: WindowBase) {.base.} =
    ## Shows the frame drawn.
    discard

  method close*(w: WindowBase) {.base.} =
    ## Closes the window. WindowBase.close
    discard w.dispatchClose()

  method onDraw*(w: WindowBase): bool {.base.} =
    ## The default `draw` handler: clears and draws. WindowBase.on_draw
    w.clear()
    w.drawCanvas()
    result = false

  method onFlip*(w: WindowBase): bool {.base.} =
    ## The default `flip` handler: shows the frame. WindowBase.on_flip
    w.flip()
    result = false

  proc updateChildsize*(w: WindowBase; childs: seq[WidgetBase]) =
    ## Sizes and places root widgets from their `sizeHint`, `sizeHintMin`,
    ## `sizeHintMax` and `posHint` and the window size. A widget without
    ## hints (not a `HintedWidget`) is left alone.
    ## WindowBase.update_childsize
    let width = w.width
    let height = w.height
    for c in childs:
      if c of HintedWidget:
        let h = HintedWidget(c)
        let (shw, shh) = h.sizeHint
        let (shwMin, shhMin) = h.sizeHintMin
        let (shwMax, shhMax) = h.sizeHintMax
        if shw.isSome and shh.isSome:
          var cw = shw.get(0) * width
          var ch = shh.get(0) * height
          if shwMin.isSome and cw < shwMin.get(0):
            cw = shwMin.get(0)
          elif shwMax.isSome and cw > shwMax.get(0):
            cw = shwMax.get(0)
          if shhMin.isSome and ch < shhMin.get(0):
            ch = shhMin.get(0)
          elif shhMax.isSome and ch > shhMax.get(0):
            ch = shhMax.get(0)
          h.size = (cw, ch)
        elif shw.isSome:
          var cw = shw.get(0) * width
          if shwMin.isSome and cw < shwMin.get(0):
            cw = shwMin.get(0)
          elif shwMax.isSome and cw > shwMax.get(0):
            cw = shwMax.get(0)
          h.width = cw
        elif shh.isSome:
          var ch = shh.get(0) * height
          if shhMin.isSome and ch < shhMin.get(0):
            ch = shhMin.get(0)
          elif shhMax.isSome and ch > shhMax.get(0):
            ch = shhMax.get(0)
          h.height = ch
        # `phPos` and `phCenter` are ignored, as Kivy's window does.
        for e in h.posHint.entries:
          case e.key
          of phX: h.x = e.value * width
          of phRight: h.right = e.value * width
          of phY: h.y = e.value * height
          of phTop: h.top = e.value * height
          of phCenterX: h.centerX = e.value * width
          of phCenterY: h.centerY = e.value * height
          of phPos, phCenter: discard

  proc updateChildsize*(w: WindowBase) =
    ## Sizes and places every root widget.
    w.updateChildsize(w.children)

  proc updateViewport*(w: WindowBase) =
    ## WindowBase.update_viewport: the SDL renderer follows the window size,
    ## so only the redraw and the children's sizes remain.
    w.canvas.askUpdate()
    w.updateChildsize()

  method onPreResize*(w: WindowBase; width, height: float): bool {.base.} =
    ## The default `preResize` handler: `resize` only when the size changed.
    ## WindowBase.on_pre_resize
    let key = (width, height)
    if not (w.hasLastResize and w.lastResize == key):
      w.hasLastResize = true
      w.lastResize = key
      discard w.dispatchResize(width, height)
    result = false

  method onResize*(w: WindowBase; width, height: float): bool {.base.} =
    ## The default `resize` handler: redraws and sizes the root widgets.
    ## WindowBase.on_resize
    w.updateViewport()
    result = false

  proc effectiveSize*(w: WindowBase): (float, float) =
    ## The system size, or the drawable size when the density is not 1.
    ## WindowBase._get_effective_size
    result = w.systemSize
    when defined(ios) or defined(windows):
      result = w.sizeValue()
    else:
      if w.density != 1:
        result = w.sizeValue()

  proc transformMotionEvent2d*(w: WindowBase; me: MotionEvent;
      widget: nil WidgetBase = nil) =
    ## Puts `me` in window coordinates, then, with `widget`, in that widget's
    ## coordinates (through its parent's `toWidget`).
    ## WindowBase.transform_motion_event_2d
    let (width, height) = w.effectiveSize()
    me.scaleForScreen(width, height)
    if widget != nil:
      let parent = widget.parent
      if parent != nil:
        me.applyTransform2d(toWidgetFn(parent))
      else:
        me.applyTransform2d(toWidgetFn(widget))
        me.applyTransform2d(toParentFn(widget))

  method onMotion*(w: WindowBase; action: MotionAction; me: MotionEvent): bool {.base.} =
    ## The default `motion` handler: touches go out as `touchDown`,
    ## `touchMove` and `touchUp` in window coordinates. Event managers are
    ## out of scope. WindowBase.on_motion
    result = false
    if me.isTouch:
      w.transformMotionEvent2d(me)
      case action
      of maBegin: discard w.dispatchTouchDown(me)
      of maUpdate: discard w.dispatchTouchMove(me)
      of maEnd: discard w.dispatchTouchUp(me)

  method onTouchDown*(w: WindowBase; touch: MotionEvent): bool =
    ## Dispatches the touch to the children, newest first, until one returns
    ## true. WindowBase.on_touch_down
    result = false
    for c in w.children:
      if c.dispatchTouchDown(touch):
        return true

  method onTouchMove*(w: WindowBase; touch: MotionEvent): bool =
    ## WindowBase.on_touch_move
    result = false
    for c in w.children:
      if c.dispatchTouchMove(touch):
        return true

  method onTouchUp*(w: WindowBase; touch: MotionEvent): bool =
    ## WindowBase.on_touch_up
    result = false
    for c in w.children:
      if c.dispatchTouchUp(touch):
        return true

  method onKeyboard*(w: WindowBase; key, scancode: int; codepoint: string;
      modifiers: set[Modifier]): bool {.base.} =
    ## The default `keyboard` handler: Escape (and Android's Back, mapped to
    ## 27) asks to close (`requestClose` from the keyboard), then stops the
    ## app, unless a `requestClose` observer returned true.
    ## WindowBase.on_keyboard
    result = false
    when defined(android):
      if key == 27:
        # GAP: the key is consumed but the task is not moved to the back as
        # Kivy's mActivity.moveTaskToBack(True) does, because SDL3 has no
        # call for it and JNI is out of scope
        return true
    if Config.kivy.exitOnEscape:
      if key == 27:
        if not w.dispatchRequestClose(true):
          let stop = w.stopTouchApp
          if stop != nil: stop()
          w.close()
          result = true

  method screenshot*(w: WindowBase; name = "screenshot.png"): string {.base.} =
    ## The path the screenshot goes to: `name` with the first number from 1
    ## that names no file yet before its extension (`screenshot0001.png`),
    ## in the current directory unless `name` is absolute. The system window
    ## saves the picture. WindowBase.screenshot
    let dot = name.rfind('.')
    let ext = if dot >= 0: name.substr(dot + 1) else: name
    let stem = name.substr(0, name.len - ext.len - 2)
    var cwd = ""
    try:
      cwd = getCurrentDir()
    except:
      cwd = "."
    var i = 0
    result = ""
    while true:
      inc i
      let file = stem & align($i, 4, '0') & "." & ext
      result = if isAbsolute(file): file else: cwd / file
      if not fileExists(result):
        break

  method createWindow*(w: WindowBase) {.base.}

  proc bindCreateWindow(w: WindowBase) =
    # WindowBase._bind_create_window, for the in-scope properties: a change
    # of size recreates (resizes) the window before the next frame.
    proc triggerIt(w: WindowBase) =
      let t = w.triggerCreateWindow
      if t != nil: t.trigger()
    w.createWindowBindings = [
      w.bindRawSize(proc (v: (float, float)) {.closure.} = w.triggerIt()),
      w.bindSystemSize(proc (v: (float, float)) {.closure.} = w.triggerIt())]

  proc unbindCreateWindow(w: WindowBase) =
    w.unbindRawSize(w.createWindowBindings[0])
    w.unbindSystemSize(w.createWindowBindings[1])

  proc initWindowBase*(w: WindowBase) =
    ## Sets up a new window object, before its system window exists: the
    ## properties, the size from Config, the canvas, and the trigger that
    ## resizes the system window when `rawSize` changes.
    ## WindowBase.__init__ (create_window and register are called when the
    ## event loop opens the window)
    w.initWidgetBase()
    w.initialized = false
    w.modifiers = {}
    w.lastResize = (0.0, 0.0)
    w.hasLastResize = false
    w.rootBindings = @[]
    w.stopTouchApp = nil
    w.quitEventLoop = nil
    w.runningApp = nil
    w.pauseApp = nil
    w.resumeApp = nil
    w.initProps()
    w.rawSize = (float(Config.graphics.width), float(Config.graphics.height))
    w.triggerCreateWindow = Clock.createTrigger(proc (dt: float) {.closure.} =
      w.createWindow(), -1)
    w.bindCreateWindow()
    w.parent = w

  method createWindow*(w: WindowBase) {.base.} =
    ## Creates the system window the first time, resizes it later. The
    ## system window overrides it and calls this base last.
    ## WindowBase.create_window
    let t = w.triggerCreateWindow
    if t != nil: t.cancel()
    when defined(android):
      # Kivy: ensure the window creation will not be called twice.
      w.unbindCreateWindow()
    if w.initialized:
      let s = w.size
      discard w.dispatchPreResize(s[0], s[1])
    w.updateViewport()

  method addWidget*(w: WindowBase; widget: WidgetBase; index = 0;
      canvas = layerCanvas) =
    ## Adds a root widget: newest first in `children`, its canvas in the
    ## window's canvas (or `before`/`after`), sized from its hints now and
    ## whenever its hints, size or position change. A widget that already
    ## has a parent stops the program, as Kivy raises WidgetException.
    ## WindowBase.add_widget
    let old = widget.parent
    if old != nil:
      quit "cannot add " & widget.cls.name & " to the window: it already has a parent, " &
        old.cls.name
    widget.parent = w
    var cs = w.children
    cs.insert([widget], 0)
    w.children = cs
    case canvas
    of layerBefore: w.canvas.before.add widget.canvas
    of layerAfter: w.canvas.after.add widget.canvas
    of layerCanvas: w.canvas.add widget.canvas
    w.updateChildsize(@[widget])
    if widget of HintedWidget:
      let h = HintedWidget(widget)
      let update = proc () {.closure.} = w.updateChildsize(@[widget])
      var b = RootBindings(child: widget)
      b.bindings = [
        h.bindPosHint(proc (v: PosHint) {.closure.} = update()),
        h.bindSizeHint(proc (v: (Opt[float], Opt[float])) {.closure.} = update()),
        h.bindSizeHintMax(proc (v: (Opt[float], Opt[float])) {.closure.} = update()),
        h.bindSizeHintMin(proc (v: (Opt[float], Opt[float])) {.closure.} = update()),
        h.bindSize(proc (v: (float, float)) {.closure.} = update()),
        h.bindPos(proc (v: (float, float)) {.closure.} = update())]
      w.rootBindings.add b

  method removeWidget*(w: WindowBase; widget: WidgetBase) =
    ## Removes a root widget and its canvas. WindowBase.remove_widget
    var cs = w.children
    let i = cs.find(widget)
    if i < 0: return
    cs.delete(i)
    w.children = cs
    let c = widget.canvas
    if w.canvas.indexof(c) >= 0:
      w.canvas.remove(c)
    elif w.canvas.after.indexof(c) >= 0:
      w.canvas.after.remove(c)
    elif w.canvas.before.indexof(c) >= 0:
      w.canvas.before.remove(c)
    widget.parent = nil
    var k = 0
    while k < w.rootBindings.len:
      let b = w.rootBindings[k]
      if b.child == widget:
        let h = HintedWidget(widget)
        h.unbindPosHint(b.bindings[0])
        h.unbindSizeHint(b.bindings[1])
        h.unbindSizeHintMax(b.bindings[2])
        h.unbindSizeHintMin(b.bindings[3])
        h.unbindSize(b.bindings[4])
        h.unbindPos(b.bindings[5])
        w.rootBindings.delete(k)
      else:
        inc k

  method getRootWindow*(w: WindowBase): nil WidgetBase =
    ## The window itself.
    w

  method setTitle*(w: WindowBase; title: string) {.base.} =
    ## Sets the `title` property. The system window overrides it to show the
    ## title instead. WindowBase.set_title
    w.title = title

  proc resetMetricsDpi*(w: WindowBase) =
    ## Hands the window's dpi to Metrics and resets its dpi.
    ## WindowBase._reset_metrics_dpi
    Metrics.platformDpi = w.dpi
    Metrics.resetDpi()

let WindowBaseClass* = newDispatcherClass("WindowBase", WidgetBaseClass)
  ## The class of `WindowBase` (a name only: its properties are typed).
