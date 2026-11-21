## The window base: Kivy's `kivy/core/window/__init__.py` (WindowBase), and
## the `WidgetBase` that widgets and the window share.
##
## `WindowBase` holds the window's properties (`size`, `width`, `height`,
## `center`, `clearcolor`, `children`, `title`, `dpi`), its root widgets, its
## canvas, and the default handlers of its events: touches go to the
## children, newest first, until one returns true; key 27 closes the app when
## `kivy.exit_on_escape` is set; a resize updates the children's size and
## position hints. The SDL3 window in `window/window_sdl3` adds the system
## window, its events and drawing.
##
## Kivy's `WidgetBase` (in `uix/widget.py`) is here, because the window and
## the event loop need what Widget and Window have in common: the `parent`
## and `children` properties, a canvas, the touch events and the coordinate
## methods. Widget (layer 6) is a `WidgetBase`; so is the window, since a
## widget's parent can be the window (Python needs no common base for that).
##
## Kivy calls `stopTouchApp` and `App.get_running_app` from inside this
## module; here those are below it (`base`, `app`), so `base` and `app` fill
## in `stopTouchApp`, `quitEventLoop` and `runningApp` on the window.
##
## Out of scope (SCOPE.md): rotation, the soft keyboard and the keyboard
## request API, text input, the cursor, hover, drag and drop, joysticks,
## event managers, window position and opacity, shaped windows and icons.

import std/[os, sequtils, strutils, syncio]
import ../[properties, clock, config, metrics]
import ../graphics/instructions
import ../input/motionevent

export properties, motionevent

type
  WidgetBase* = ref object of EventDispatcher
    ## What every widget and the window have: `parent` and `children`
    ## properties, a canvas, the events `on_touch_down`, `on_touch_move` and
    ## `on_touch_up`, and coordinate methods. Build it with `T(cls: ...)`,
    ## then call `initWidgetBase`.
    canvas*: Canvas

  WindowHook* = proc () {.closure.}
    ## A call into a module below this one (`base`).

  WindowBase* = ref object of WidgetBase
    ## The window. Its system part is `WindowSDL` (window/window_sdl3).
    initialized*: bool            ## the system window exists
    triggerCreateWindow*: nil ClockEvent  ## recreates (resizes) the window before the next frame
    modifiers*: seq[string]       ## the modifier keys held: "shift", "ctrl", "alt", ...
    lastResize: (float, float)
    hasLastResize: bool
    childBindings: seq[(WidgetBase, seq[(string, int)])]
    stopTouchApp*: nil WindowHook ## base.stopTouchApp; set by `base`
    quitEventLoop*: nil WindowHook ## sets EventLoop.quit; set by `base`
    runningApp*: nil EventDispatcher ## App.get_running_app(); set by `app`
    createWindowUids: seq[(string, int)]

# ------------------------------------------------------------------ WidgetBase

method onTouchDown*(w: WidgetBase; touch: MotionEvent): bool {.base.} =
  ## The default `on_touch_down` handler. Returns true to stop the touch.
  false

method onTouchMove*(w: WidgetBase; touch: MotionEvent): bool {.base.} =
  ## The default `on_touch_move` handler.
  false

method onTouchUp*(w: WidgetBase; touch: MotionEvent): bool {.base.} =
  ## The default `on_touch_up` handler.
  false

proc touchDownHandler(d: EventDispatcher; args: seq[Value]): bool =
  WidgetBase(d).onTouchDown(toMotionEvent(args[0]))

proc touchMoveHandler(d: EventDispatcher; args: seq[Value]): bool =
  WidgetBase(d).onTouchMove(toMotionEvent(args[0]))

proc touchUpHandler(d: EventDispatcher; args: seq[Value]): bool =
  WidgetBase(d).onTouchUp(toMotionEvent(args[0]))

proc newWidgetBaseClass(): DispatcherClass =
  result = newDispatcherClass("WidgetBase", EventDispatcherClass)
  discard result.addObject("parent", allowNone = true)
  discard result.addList("children")
  result.addEvent("on_touch_down", touchDownHandler)
  result.addEvent("on_touch_move", touchMoveHandler)
  result.addEvent("on_touch_up", touchUpHandler)

let WidgetBaseClass* = newWidgetBaseClass()
  ## The class of `WidgetBase`: subclass it with `newDispatcherClass`.

proc toWidgetBase(v: Value): nil WidgetBase =
  # The widget in a property value, or nil.
  if v.kind != vkObject: return nil
  let o = v.obj
  if o == nil or not (o of WidgetBase): return nil
  result = WidgetBase(o)

proc toValue*(w: WidgetBase): Value {.inline.} =
  ## The widget as a property value or event argument.
  toValue(RootRef(w))

proc initWidgetBase*(w: WidgetBase) =
  ## Sets up a new widget or window (its properties).
  w.initEventDispatcher()

proc parent*(w: WidgetBase): nil WidgetBase =
  ## The parent widget or window, or nil.
  toWidgetBase(w.getProperty("parent"))

proc `parent=`*(w: WidgetBase; p: nil WidgetBase) =
  ## Sets the parent (nil: none).
  if p == nil: w.setProperty("parent", noneValue())
  else: w.setProperty("parent", toValue(p))

proc children*(w: WidgetBase): seq[WidgetBase] =
  ## The children, newest first.
  result = @[]
  let v = w.getProperty("children")
  for item in v.items:
    let c = toWidgetBase(item)
    if c != nil: result.add c

proc `children=`*(w: WidgetBase; children: seq[WidgetBase]) =
  ## Sets the children.
  var items: seq[Value] = @[]
  for c in children: items.add toValue(c)
  w.setProperty("children", toValue(items))

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

method addWidget*(w: WidgetBase; widget: WidgetBase; index = 0; canvas = "") {.base.} =
  ## Adds a child. `canvas` is "", "before" or "after". Widget (layer 6)
  ## and the window override it.
  discard

method removeWidget*(w: WidgetBase; widget: WidgetBase) {.base.} =
  ## Removes a child.
  discard

# ------------------------------------------------------------------ WindowBase

proc window(d: EventDispatcher): WindowBase {.inline.} =
  WindowBase(d)

method glSize*(w: WindowBase): (float, float) {.base.} =
  ## The drawable size in pixels (Kivy's `_win._get_gl_size()`). The
  ## system window overrides it; here it is `_size`.
  let s = w.getProperty("_size").toFloats
  result = (s[0], s[1])

proc sizeValue(w: WindowBase): (float, float) =
  # WindowBase._get_size, without rotation and the soft keyboard (out of
  # scope).
  let s = w.getProperty("_size").toFloats
  result = (s[0], s[1])
  when defined(windows):
    result = w.glSize()
  else:
    if w.getProperty("_density").num != 1:
      result = w.glSize()

proc getSize(d: EventDispatcher): Value =
  let (w, h) = d.window.sizeValue()
  result = toValue([w, h])

proc setSize(d: EventDispatcher; v: Value): bool =
  # WindowBase._set_size
  let w = d.window
  if w.getProperty("_size") != v:
    w.setProperty("_size", v)
    let s = v.toFloats
    discard w.dispatch("on_pre_resize", toValue(s[0]), toValue(s[1]))
  result = false

proc getWidth(d: EventDispatcher): Value =
  toValue(d.window.sizeValue()[0])

proc getHeight(d: EventDispatcher): Value =
  toValue(d.window.sizeValue()[1])

proc getCenter(d: EventDispatcher): Value =
  let w = d.window
  result = toValue([w.getProperty("width").num / 2, w.getProperty("height").num / 2])

proc getSystemSize(d: EventDispatcher): Value =
  d.window.getProperty("_size")

proc setSystemSize(d: EventDispatcher; v: Value): bool =
  d.window.setProperty("_size", v)
  result = false

# Default handlers of the window's events.

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
  discard w.dispatch("on_close")

proc onDraw(d: EventDispatcher; args: seq[Value]): bool =
  # WindowBase.on_draw
  d.window.clear()
  d.window.drawCanvas()
  result = false

proc onFlip(d: EventDispatcher; args: seq[Value]): bool =
  d.window.flip()
  result = false

proc noHandler(d: EventDispatcher; args: seq[Value]): bool =
  # The default handler of an event Kivy's window does nothing for.
  false

proc updateChildsize*(w: WindowBase; childs: seq[WidgetBase]) =
  ## Sizes and places root widgets from their `size_hint`, `size_hint_min`,
  ## `size_hint_max` and `pos_hint` and the window size. A widget without
  ## these properties is left alone. `pos_hint` is a list of
  ## `(key, value)` pairs. WindowBase.update_childsize
  let width = w.getProperty("width").num
  let height = w.getProperty("height").num
  for c in childs:
    if c.property("size_hint") != nil:
      let sh = c.getProperty("size_hint")
      let shMin = c.getProperty("size_hint_min")
      let shMax = c.getProperty("size_hint_max")
      let (shw, shh) = (sh.items[0], sh.items[1])
      let (shwMin, shhMin) = (shMin.items[0], shMin.items[1])
      let (shwMax, shhMax) = (shMax.items[0], shMax.items[1])
      if not shw.isNone and not shh.isNone:
        var cw = shw.num * width
        var ch = shh.num * height
        if not shwMin.isNone and cw < shwMin.num:
          cw = shwMin.num
        elif not shwMax.isNone and cw > shwMax.num:
          cw = shwMax.num
        if not shhMin.isNone and ch < shhMin.num:
          ch = shhMin.num
        elif not shhMax.isNone and ch > shhMax.num:
          ch = shhMax.num
        c.setProperty("size", toValue([cw, ch]))
      elif not shw.isNone:
        var cw = shw.num * width
        if not shwMin.isNone and cw < shwMin.num:
          cw = shwMin.num
        elif not shwMax.isNone and cw > shwMax.num:
          cw = shwMax.num
        c.setProperty("width", toValue(cw))
      elif not shh.isNone:
        var ch = shh.num * height
        if not shhMin.isNone and ch < shhMin.num:
          ch = shhMin.num
        elif not shhMax.isNone and ch > shhMax.num:
          ch = shhMax.num
        c.setProperty("height", toValue(ch))
      # The values of `pos` and `center` are pairs; the window ignores
      # those keys, as Kivy's does.
      for pair in c.getProperty("pos_hint").items:
        let key = pair.items[0].str
        let value = pair.items[1]
        case key
        of "x": c.setProperty("x", toValue(value.num * width))
        of "right": c.setProperty("right", toValue(value.num * width))
        of "y": c.setProperty("y", toValue(value.num * height))
        of "top": c.setProperty("top", toValue(value.num * height))
        of "center_x": c.setProperty("center_x", toValue(value.num * width))
        of "center_y": c.setProperty("center_y", toValue(value.num * height))
        else: discard

proc updateChildsize*(w: WindowBase) =
  ## Sizes and places every root widget.
  w.updateChildsize(w.children)

proc updateViewport*(w: WindowBase) =
  ## WindowBase.update_viewport: the SDL renderer follows the window size,
  ## so only the redraw and the children's sizes remain.
  w.canvas.askUpdate()
  w.updateChildsize()

proc onPreResize(d: EventDispatcher; args: seq[Value]): bool =
  # WindowBase.on_pre_resize: on_resize only when the size changed.
  let w = d.window
  let key = (args[0].num, args[1].num)
  if not (w.hasLastResize and w.lastResize == key):
    w.hasLastResize = true
    w.lastResize = key
    discard w.dispatch("on_resize", args[0], args[1])
  result = false

proc onResize(d: EventDispatcher; args: seq[Value]): bool =
  d.window.updateViewport()
  result = false

proc effectiveSize*(w: WindowBase): (float, float) =
  ## The system size, or the drawable size when the density is not 1.
  ## WindowBase._get_effective_size
  let s = w.getProperty("system_size").toFloats
  result = (s[0], s[1])
  when defined(ios) or defined(windows):
    result = w.sizeValue()
  else:
    if w.getProperty("_density").num != 1:
      result = w.sizeValue()

proc toWidgetFn(w: WidgetBase): proc (x, y: float): (float, float) {.closure.} =
  # `w.to_widget` as a callable.
  result = proc (x, y: float): (float, float) {.closure.} = w.toWidget(x, y)

proc toParentFn(w: WidgetBase): proc (x, y: float): (float, float) {.closure.} =
  # `w.to_parent` as a callable.
  result = proc (x, y: float): (float, float) {.closure.} = w.toParent(x, y)

proc transformMotionEvent2d*(w: WindowBase; me: MotionEvent; widget: nil WidgetBase = nil) =
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

proc onMotion(d: EventDispatcher; args: seq[Value]): bool =
  # WindowBase.on_motion: touches go out as on_touch_* in window
  # coordinates. Event managers are out of scope.
  let w = d.window
  let etype = args[0].str
  let me = toMotionEvent(args[1])
  result = false
  if me.isTouch:
    w.transformMotionEvent2d(me)
    if etype == "begin":
      discard w.dispatch("on_touch_down", toValue(me))
    elif etype == "update":
      discard w.dispatch("on_touch_move", toValue(me))
    elif etype == "end":
      discard w.dispatch("on_touch_up", toValue(me))

method onTouchDown*(w: WindowBase; touch: MotionEvent): bool =
  ## Dispatches the touch to the children, newest first, until one returns
  ## true. WindowBase.on_touch_down
  result = false
  for c in w.children:
    if c.dispatch("on_touch_down", toValue(touch)):
      return true

method onTouchMove*(w: WindowBase; touch: MotionEvent): bool =
  ## WindowBase.on_touch_move
  result = false
  for c in w.children:
    if c.dispatch("on_touch_move", toValue(touch)):
      return true

method onTouchUp*(w: WindowBase; touch: MotionEvent): bool =
  ## WindowBase.on_touch_up
  result = false
  for c in w.children:
    if c.dispatch("on_touch_up", toValue(touch)):
      return true

proc onKeyboard(d: EventDispatcher; args: seq[Value]): bool =
  # WindowBase.on_keyboard: Escape (and Android's Back, mapped to 27) asks to
  # close, then stops the app, unless an on_request_close observer returned
  # true. `source = "keyboard"` is passed as the event's argument.
  let w = d.window
  let key = int(args[0].num)
  result = false
  when defined(android):
    if key == 27:
      # GAP: the key is consumed but the task is not moved to the back as
      # Kivy's mActivity.moveTaskToBack(True) does, because SDL3 has no call
      # for it and JNI is out of scope
      return true
  if Config.getboolean("kivy", "exit_on_escape"):
    if key == 27:
      if not w.dispatch("on_request_close", toValue("keyboard")):
        let stop = w.stopTouchApp
        if stop != nil: stop()
        w.close()
        result = true

proc onClose(d: EventDispatcher; args: seq[Value]): bool =
  # WindowBase.on_close: `base` removes the window from the event listeners
  # with an observer of this event (it is below this module).
  false

method screenshot*(w: WindowBase; name = "screenshot{:04d}.png"): string {.base.} =
  ## The path the screenshot goes to: `name` with the first number from 1
  ## that names no file yet, in the current directory unless `name` is
  ## absolute. The system window saves the picture. WindowBase.screenshot
  var stem = name
  var ext = ""
  if name != "screenshot{:04d}.png":
    let dot = name.rfind('.')
    ext = if dot >= 0: name.substr(dot + 1) else: name
    stem = name.substr(0, name.len - ext.len - 2)
  else:
    stem = "screenshot"
    ext = "png"
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

proc newWindowBaseClass(): DispatcherClass =
  result = newDispatcherClass("WindowBase", WidgetBaseClass)
  discard result.addNumeric("_density", 1)
  discard result.addList("_size", @[toValue(0), toValue(0)])
  discard result.addAlias("size", getSize, setSize, @["_size"])
  discard result.addColor("clearcolor", @[0.0, 0.0, 0.0, 1.0])
  discard result.addAlias("width", getWidth, nil, @["_size", "_density"])
  discard result.addAlias("height", getHeight, nil, @["_size", "_density"])
  discard result.addAlias("center", getCenter, nil, @["width", "height"])
  discard result.addAlias("system_size", getSystemSize, setSystemSize, @["_size"])
  discard result.addString("title", "Kivy")
  discard result.addNumeric("dpi", 96)
  for name in ["on_mouse_down", "on_mouse_move", "on_mouse_up", "on_key_down",
      "on_key_up", "on_request_close"]:
    result.addEvent(name, noHandler)
  result.addEvent("on_draw", onDraw)
  result.addEvent("on_flip", onFlip)
  result.addEvent("on_resize", onResize)
  result.addEvent("on_pre_resize", onPreResize)
  result.addEvent("on_close", onClose)
  result.addEvent("on_motion", onMotion)
  result.addEvent("on_keyboard", onKeyboard)

let WindowBaseClass* = newWindowBaseClass()
  ## The class of `WindowBase`.

method createWindow*(w: WindowBase) {.base.}

proc bindCreateWindow(w: WindowBase) =
  # WindowBase._bind_create_window, for the in-scope properties: a change
  # of size recreates (resizes) the window before the next frame.
  w.createWindowUids = @[]
  for name in ["_size", "system_size"]:
    w.createWindowUids.add (name, w.fbind(name, proc (d: EventDispatcher; v: Value) {.closure.} =
      let t = d.window.triggerCreateWindow
      if t != nil: t.trigger()))

proc unbindCreateWindow(w: WindowBase) =
  for i in 0 ..< w.createWindowUids.len:
    let (name, uid) = w.createWindowUids[i]
    w.unbindUid(name, uid)
  w.createWindowUids = @[]

proc initWindowBase*(w: WindowBase) =
  ## Sets up a new window object, before its system window exists: the
  ## properties, the size from Config, the canvas, and the trigger that
  ## resizes the system window when `_size` changes.
  ## WindowBase.__init__ (create_window and register are called when the
  ## event loop opens the window)
  w.initWidgetBase()
  w.initialized = false
  w.modifiers = @[]
  w.lastResize = (0.0, 0.0)
  w.hasLastResize = false
  w.childBindings = @[]
  w.stopTouchApp = nil
  w.quitEventLoop = nil
  w.runningApp = nil
  w.setProperty("_size", toValue([float(Config.getint("graphics", "width")),
    float(Config.getint("graphics", "height"))]))
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
    let s = w.getProperty("size").toFloats
    discard w.dispatch("on_pre_resize", toValue(s[0]), toValue(s[1]))
  w.updateViewport()

method addWidget*(w: WindowBase; widget: WidgetBase; index = 0; canvas = "") =
  ## Adds a root widget: newest first in `children`, its canvas in the
  ## window's canvas (or `before`/`after`), sized from its hints now and
  ## whenever its hints, size or position change. A widget that already has
  ## a parent stops the program, as Kivy raises WidgetException.
  ## WindowBase.add_widget
  let old = widget.parent
  if old != nil:
    quit "WidgetException: Cannot add " & widget.cls.name &
      " to window, it already has a parent " & old.cls.name
  widget.parent = w
  var cs = w.children
  cs.insert([widget], 0)
  w.children = cs
  if canvas == "before": w.canvas.before.add widget.canvas
  elif canvas == "after": w.canvas.after.add widget.canvas
  else: w.canvas.add widget.canvas
  w.updateChildsize(@[widget])
  var uids: seq[(string, int)] = @[]
  for name in ["pos_hint", "size_hint", "size_hint_max", "size_hint_min", "size", "pos"]:
    let uid = widget.fbind(name, proc (d: EventDispatcher; v: Value) {.closure.} =
      w.updateChildsize(@[WidgetBase(d)]))
    if uid != 0: uids.add (name, uid)
  w.childBindings.add (widget, uids)

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
  while k < w.childBindings.len:
    if w.childBindings[k][0] == widget:
      let uids = w.childBindings[k][1]
      for (name, uid) in uids:
        widget.unbindUid(name, uid)
      w.childBindings.delete(k)
    else:
      inc k

method getRootWindow*(w: WindowBase): nil WidgetBase =
  ## The window itself.
  w

method setTitle*(w: WindowBase; title: string) {.base.} =
  ## Sets the `title` property. The system window overrides it to show the
  ## title instead. WindowBase.set_title
  w.setProperty("title", toValue(title))

proc size*(w: WindowBase): (float, float) =
  ## The window size in pixels.
  let s = w.getProperty("size").toFloats
  result = (s[0], s[1])

proc `size=`*(w: WindowBase; size: (float, float)) =
  ## Requests a new window size.
  w.setProperty("size", toValue([size[0], size[1]]))

proc width*(w: WindowBase): float =
  ## The width in pixels.
  w.getProperty("width").num

proc height*(w: WindowBase): float =
  ## The height in pixels.
  w.getProperty("height").num

proc center*(w: WindowBase): (float, float) =
  ## The centre of the window.
  let c = w.getProperty("center").toFloats
  result = (c[0], c[1])

proc systemSize*(w: WindowBase): (float, float) =
  ## The size in window (screen) coordinates, before the density.
  let s = w.getProperty("system_size").toFloats
  result = (s[0], s[1])

proc clearcolor*(w: WindowBase): array[4, float] =
  ## The colour the window is cleared with.
  let c = w.getProperty("clearcolor").toFloats
  result = [c[0], c[1], c[2], c[3]]

proc `clearcolor=`*(w: WindowBase; rgba: openArray[float]) =
  ## Sets the clear colour (3 or 4 values).
  w.setProperty("clearcolor", toValue(rgba))

proc dpi*(w: WindowBase): float =
  ## The window's dots per inch.
  w.getProperty("dpi").num

proc density*(w: WindowBase): float =
  ## Pixels per window coordinate (Kivy's `_density`).
  w.getProperty("_density").num

proc resetMetricsDpi*(w: WindowBase) =
  ## Hands the window's dpi to Metrics and resets its dpi.
  ## WindowBase._reset_metrics_dpi
  Metrics.platformDpi = w.dpi
  Metrics.resetDpi()
