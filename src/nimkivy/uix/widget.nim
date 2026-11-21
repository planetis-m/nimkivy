## The widget: Kivy's `kivy/uix/widget.py` (Widget).
##
## A widget is a box (`x`, `y`, `width`, `height` and the properties made of
## them), size and position hints for the layouts, a canvas, children, and
## the touch events. Touches go to the children, newest first, until one
## returns true; a disabled widget swallows a touch down on it and ignores
## moves and ends. `disabled` is a count shared down the tree, as in Kivy's
## `inc_disabled` and `dec_disabled`.
##
## Build a widget with `newWidget()`, or a subclass with
## `T(cls: TClass, canvas: newCanvas())` followed by `initWidget`. As in Kivy,
## creating a widget opens the window (`EventLoop.ensureWindow`).
##
## `pos_hint` is stored as a list of `(key, value)` pairs in the order the
## keys were given, as Python's dict keeps them; the value is a number, or a
## pair of numbers for `pos` and `center`.
##
## Out of scope (SCOPE.md): `ids`, `cls`, `motion_filter` and `on_motion`,
## `on_kv_post`, `export_to_png` and `export_as_image`, `walk_reverse`,
## `proxy_ref`, `get_parent_window` and `get_window_matrix`.

import std/[opt, sequtils, syncio]
import ../[properties, base]
import ../graphics/instructions

export opt, base, instructions

type
  Widget* = ref object of WidgetBase
    ## The base of every widget. uix/widget.py Widget
    disabledCount: int            # _disabled_count: own and inherited
    disabledValue: bool           # _disabled_value: the value last set

# ------------------------------------------------------------------ class

proc widgetOf(d: EventDispatcher): Widget {.inline.} =
  Widget(d)

proc optNum(v: Value): Opt[float] =
  # A NumericProperty with `allownone` as an Opt.
  if v.kind == vkNumber: some(v.num) else: none[float]()

proc toValue*(o: Opt[float]): Value =
  ## A number, or None.
  if o.isSome: toValue(o.get(0)) else: noneValue()

proc posHintEqual(a, b: Value): bool =
  # Python's dict equality: the same keys with equal values, in any order.
  if a.kind != vkList or b.kind != vkList:
    return a == b
  if a.items.len != b.items.len:
    return false
  result = true
  for pa in a.items:
    var found = false
    for pb in b.items:
      if pb.items[0] == pa.items[0]:
        found = pb.items[1] == pa.items[1]
    if not found:
      return false

let WidgetClass* = newDispatcherClass("Widget", WidgetBaseClass)
  ## The class of `Widget`: subclass it with `newDispatcherClass`.
let pX = WidgetClass.addNumeric("x", 0)
let pY = WidgetClass.addNumeric("y", 0)
let pWidth = WidgetClass.addNumeric("width", 100)
let pHeight = WidgetClass.addNumeric("height", 100)
let pPos = WidgetClass.addReferenceList("pos", @[Property(pX), pY])
let pSize = WidgetClass.addReferenceList("size", @[Property(pWidth), pHeight])

proc getRight(d: EventDispatcher): Value = toValue(pX.getNumber(d) + pWidth.getNumber(d))
proc setRight(d: EventDispatcher; v: Value): bool =
  pX.setNumber(d, v.num - pWidth.getNumber(d))
  result = false
proc getTop(d: EventDispatcher): Value = toValue(pY.getNumber(d) + pHeight.getNumber(d))
proc setTop(d: EventDispatcher; v: Value): bool =
  pY.setNumber(d, v.num - pHeight.getNumber(d))
  result = false
proc getCenterX(d: EventDispatcher): Value =
  toValue(pX.getNumber(d) + pWidth.getNumber(d) / 2.0)
proc setCenterX(d: EventDispatcher; v: Value): bool =
  pX.setNumber(d, v.num - pWidth.getNumber(d) / 2.0)
  result = false
proc getCenterY(d: EventDispatcher): Value =
  toValue(pY.getNumber(d) + pHeight.getNumber(d) / 2.0)
proc setCenterY(d: EventDispatcher; v: Value): bool =
  pY.setNumber(d, v.num - pHeight.getNumber(d) / 2.0)
  result = false

let pRight = WidgetClass.addAlias("right", getRight, setRight, @["x", "width"],
  cache = true, watchBeforeUse = false)
let pTop = WidgetClass.addAlias("top", getTop, setTop, @["y", "height"],
  cache = true, watchBeforeUse = false)
let pCenterX = WidgetClass.addAlias("center_x", getCenterX, setCenterX,
  @["x", "width"], cache = true, watchBeforeUse = false)
let pCenterY = WidgetClass.addAlias("center_y", getCenterY, setCenterY,
  @["y", "height"], cache = true, watchBeforeUse = false)
let pCenter = WidgetClass.addReferenceList("center", @[Property(pCenterX), pCenterY])
let pSizeHintX = WidgetClass.addNumeric("size_hint_x", 1, allowNone = true)
let pSizeHintY = WidgetClass.addNumeric("size_hint_y", 1, allowNone = true)
let pSizeHint = WidgetClass.addReferenceList("size_hint",
  @[Property(pSizeHintX), pSizeHintY])
let pPosHint = WidgetClass.addObject("pos_hint", toValue(newSeq[Value]()),
  comparator = posHintEqual)
let pSizeHintMinX = WidgetClass.addNumericNone("size_hint_min_x")
let pSizeHintMinY = WidgetClass.addNumericNone("size_hint_min_y")
let pSizeHintMin = WidgetClass.addReferenceList("size_hint_min",
  @[Property(pSizeHintMinX), pSizeHintMinY])
let pSizeHintMaxX = WidgetClass.addNumericNone("size_hint_max_x")
let pSizeHintMaxY = WidgetClass.addNumericNone("size_hint_max_y")
let pSizeHintMax = WidgetClass.addReferenceList("size_hint_max",
  @[Property(pSizeHintMaxX), pSizeHintMaxY])
let pOpacity = WidgetClass.addNumeric("opacity", 1.0)

proc getDisabled(d: EventDispatcher): Value =
  # Widget.get_disabled
  toValue(d.widgetOf.disabledCount > 0)

proc incDisabled*(w: Widget; count = 1)
proc decDisabled*(w: Widget; count = 1)

proc setDisabled(d: EventDispatcher; v: Value): bool =
  # Widget.set_disabled: Python's bool(value).
  let w = d.widgetOf
  let value = case v.kind
    of vkBool: v.flag
    of vkNumber: v.num != 0
    of vkNone: false
    of vkString: v.str.len > 0
    of vkList: v.items.len > 0
    of vkObject: v.obj != nil
  result = false
  if value != w.disabledValue:
    w.disabledValue = value
    if value:
      w.incDisabled()
    else:
      w.decDisabled()
    result = true

let pDisabled = WidgetClass.addAlias("disabled", getDisabled, setDisabled,
  watchBeforeUse = false)

proc onOpacity(d: EventDispatcher; v: Value) =
  # Widget.on_opacity
  d.widgetOf.canvas.opacity = v.num

WidgetClass.addPropertyHandler("opacity", onOpacity)

# ------------------------------------------------------------------ construction

proc initWidget*(w: Widget) =
  ## Sets up a new widget (its properties); opens the window first, as
  ## Kivy's Widget.__init__ does. The caller passes `canvas: newCanvas()`
  ## to the object constructor.
  EventLoop.ensureWindow()
  w.disabledValue = false
  w.disabledCount = 0
  w.initWidgetBase()

proc newWidget*(): Widget =
  ## A plain widget at (0, 0), 100 x 100.
  result = Widget(cls: WidgetClass, canvas: newCanvas(), disabledCount: 0,
    disabledValue: false)
  result.initWidget()

# ------------------------------------------------------------------ accessors

proc x*(w: Widget): float {.inline.} =
  ## The left edge.
  pX.getNumber(w)
proc `x=`*(w: Widget; v: float) {.inline.} =
  ## Moves the left edge.
  pX.setNumber(w, v)
proc y*(w: Widget): float {.inline.} =
  ## The bottom edge (y goes up).
  pY.getNumber(w)
proc `y=`*(w: Widget; v: float) {.inline.} =
  ## Moves the bottom edge.
  pY.setNumber(w, v)
proc width*(w: Widget): float {.inline.} =
  ## The width (default 100).
  pWidth.getNumber(w)
proc `width=`*(w: Widget; v: float) {.inline.} =
  ## Sets the width.
  pWidth.setNumber(w, v)
proc height*(w: Widget): float {.inline.} =
  ## The height (default 100).
  pHeight.getNumber(w)
proc `height=`*(w: Widget; v: float) {.inline.} =
  ## Sets the height.
  pHeight.setNumber(w, v)

proc pair(v: Value): (float, float) {.inline.} =
  (v.items[0].num, v.items[1].num)

proc pos*(w: Widget): (float, float) =
  ## `(x, y)`.
  pair(pPos.get(w))
proc `pos=`*(w: Widget; p: (float, float)) =
  ## Sets `x`, then `y`, then dispatches `pos` once.
  discard pPos.set(w, toValue([p[0], p[1]]))
proc size*(w: Widget): (float, float) =
  ## `(width, height)`.
  pair(pSize.get(w))
proc `size=`*(w: Widget; s: (float, float)) =
  ## Sets `width`, then `height`, then dispatches `size` once.
  discard pSize.set(w, toValue([s[0], s[1]]))
proc right*(w: Widget): float =
  ## `x + width`.
  pRight.getNumber(w)
proc `right=`*(w: Widget; v: float) =
  ## Moves the widget so that its right edge is `v`.
  discard pRight.set(w, toValue(v))
proc top*(w: Widget): float =
  ## `y + height`.
  pTop.getNumber(w)
proc `top=`*(w: Widget; v: float) =
  ## Moves the widget so that its top edge is `v`.
  discard pTop.set(w, toValue(v))
proc centerX*(w: Widget): float =
  ## `x + width / 2`.
  pCenterX.getNumber(w)
proc `centerX=`*(w: Widget; v: float) =
  ## Moves the widget horizontally so that its centre is at `v`.
  discard pCenterX.set(w, toValue(v))
proc centerY*(w: Widget): float =
  ## `y + height / 2`.
  pCenterY.getNumber(w)
proc `centerY=`*(w: Widget; v: float) =
  ## Moves the widget vertically so that its centre is at `v`.
  discard pCenterY.set(w, toValue(v))
proc center*(w: Widget): (float, float) =
  ## `(centerX, centerY)`.
  pair(pCenter.get(w))
proc `center=`*(w: Widget; c: (float, float)) =
  ## Moves the widget so that its centre is at `c`.
  discard pCenter.set(w, toValue([c[0], c[1]]))

proc sizeHintX*(w: Widget): Opt[float] =
  ## The width as a share of the parent's (default 1; none: `width` is kept).
  optNum(pSizeHintX.get(w))
proc `sizeHintX=`*(w: Widget; v: Opt[float]) =
  ## Sets the width hint (none: no hint).
  discard pSizeHintX.set(w, toValue(v))
proc `sizeHintX=`*(w: Widget; v: float) =
  ## Sets the width hint.
  discard pSizeHintX.set(w, toValue(v))
proc sizeHintY*(w: Widget): Opt[float] =
  ## The height as a share of the parent's (default 1).
  optNum(pSizeHintY.get(w))
proc `sizeHintY=`*(w: Widget; v: Opt[float]) =
  ## Sets the height hint (none: no hint).
  discard pSizeHintY.set(w, toValue(v))
proc `sizeHintY=`*(w: Widget; v: float) =
  ## Sets the height hint.
  discard pSizeHintY.set(w, toValue(v))
proc sizeHint*(w: Widget): (Opt[float], Opt[float]) =
  ## `(sizeHintX, sizeHintY)`.
  let v = pSizeHint.get(w)
  result = (optNum(v.items[0]), optNum(v.items[1]))
proc `sizeHint=`*(w: Widget; h: (Opt[float], Opt[float])) =
  ## Sets both hints (none: no hint).
  discard pSizeHint.set(w, toValue(@[toValue(h[0]), toValue(h[1])]))
proc `sizeHint=`*(w: Widget; h: (float, float)) =
  ## Sets both hints.
  discard pSizeHint.set(w, toValue([h[0], h[1]]))

proc sizeHintMinX*(w: Widget): Opt[float] =
  ## The smallest width the hint may give (default none).
  optNum(pSizeHintMinX.get(w))
proc `sizeHintMinX=`*(w: Widget; v: Opt[float]) =
  ## Sets the smallest width the hint may give.
  discard pSizeHintMinX.set(w, toValue(v))
proc `sizeHintMinX=`*(w: Widget; v: float) =
  ## Sets the smallest width the hint may give.
  discard pSizeHintMinX.set(w, toValue(v))
proc sizeHintMinY*(w: Widget): Opt[float] =
  ## The smallest height the hint may give (default none).
  optNum(pSizeHintMinY.get(w))
proc `sizeHintMinY=`*(w: Widget; v: Opt[float]) =
  ## Sets the smallest height the hint may give.
  discard pSizeHintMinY.set(w, toValue(v))
proc `sizeHintMinY=`*(w: Widget; v: float) =
  ## Sets the smallest height the hint may give.
  discard pSizeHintMinY.set(w, toValue(v))
proc sizeHintMin*(w: Widget): (Opt[float], Opt[float]) =
  ## `(sizeHintMinX, sizeHintMinY)`.
  let v = pSizeHintMin.get(w)
  result = (optNum(v.items[0]), optNum(v.items[1]))
proc `sizeHintMin=`*(w: Widget; h: (float, float)) =
  ## Sets both minimums.
  discard pSizeHintMin.set(w, toValue([h[0], h[1]]))
proc sizeHintMaxX*(w: Widget): Opt[float] =
  ## The largest width the hint may give (default none).
  optNum(pSizeHintMaxX.get(w))
proc `sizeHintMaxX=`*(w: Widget; v: Opt[float]) =
  ## Sets the largest width the hint may give.
  discard pSizeHintMaxX.set(w, toValue(v))
proc `sizeHintMaxX=`*(w: Widget; v: float) =
  ## Sets the largest width the hint may give.
  discard pSizeHintMaxX.set(w, toValue(v))
proc sizeHintMaxY*(w: Widget): Opt[float] =
  ## The largest height the hint may give (default none).
  optNum(pSizeHintMaxY.get(w))
proc `sizeHintMaxY=`*(w: Widget; v: Opt[float]) =
  ## Sets the largest height the hint may give.
  discard pSizeHintMaxY.set(w, toValue(v))
proc `sizeHintMaxY=`*(w: Widget; v: float) =
  ## Sets the largest height the hint may give.
  discard pSizeHintMaxY.set(w, toValue(v))
proc sizeHintMax*(w: Widget): (Opt[float], Opt[float]) =
  ## `(sizeHintMaxX, sizeHintMaxY)`.
  let v = pSizeHintMax.get(w)
  result = (optNum(v.items[0]), optNum(v.items[1]))
proc `sizeHintMax=`*(w: Widget; h: (float, float)) =
  ## Sets both maximums.
  discard pSizeHintMax.set(w, toValue([h[0], h[1]]))

proc posHint*(w: Widget): seq[(string, Value)] =
  ## The position hints in the order they were given: a number for `x`,
  ## `right`, `center_x`, `y`, `top` and `center_y`, a list of two numbers
  ## for `pos` and `center`.
  result = @[]
  for p in pPosHint.get(w).items:
    result.add (p.items[0].str, p.items[1])

proc setPosHint*(w: Widget; hints: openArray[(string, Value)]) =
  ## Sets the position hints. A key given twice keeps its first place and
  ## its last value, as in a Python dict literal.
  var items: seq[Value] = @[]
  for (key, value) in hints:
    var i = 0
    while i < items.len and items[i].items[0].str != key:
      inc i
    if i < items.len:
      items[i] = toValue(@[toValue(key), value])
    else:
      items.add toValue(@[toValue(key), value])
  discard pPosHint.set(w, toValue(items))

proc `posHint=`*(w: Widget; hints: openArray[(string, float)]) =
  ## Sets numeric position hints (`x`, `right`, `center_x`, `y`, `top`,
  ## `center_y`), for example `w.posHint = {"top": 0.9}`.
  var pairs: seq[(string, Value)] = @[]
  for (key, value) in hints:
    pairs.add (key, toValue(value))
  w.setPosHint(pairs)

proc opacity*(w: Widget): float {.inline.} =
  ## The opacity of the widget and its children (it multiplies down).
  pOpacity.getNumber(w)
proc `opacity=`*(w: Widget; v: float) {.inline.} =
  ## Sets the opacity (and the canvas's).
  pOpacity.setNumber(w, v)

proc disabled*(w: Widget): bool =
  ## Whether the widget, or a parent of it, is disabled.
  pDisabled.get(w).flag
proc `disabled=`*(w: Widget; v: bool) =
  ## Disables or enables the widget and its children.
  discard pDisabled.set(w, toValue(v))

proc widgetChildren*(w: WidgetBase): seq[Widget] =
  ## The children that are widgets, newest first.
  result = @[]
  for c in w.children:
    if c of Widget: result.add Widget(c)

# ------------------------------------------------------------------ disabled

proc incDisabled*(w: Widget; count = 1) =
  ## Adds `count` to the disabled count of the widget and its children.
  ## Widget.inc_disabled
  w.disabledCount += count
  if w.disabledCount - count < 1 and 1 <= w.disabledCount:
    pDisabled.dispatch(w)
  for c in w.widgetChildren:
    c.incDisabled(count)

proc decDisabled*(w: Widget; count = 1) =
  ## Takes `count` from the disabled count of the widget and its children.
  ## Widget.dec_disabled
  w.disabledCount -= count
  if w.disabledCount <= 0 and 0 < w.disabledCount + count:
    pDisabled.dispatch(w)
  for c in w.widgetChildren:
    c.decDisabled(count)

# ------------------------------------------------------------------ collision

method collidePoint*(w: Widget; x, y: float): bool {.base.} =
  ## Whether (x, y) is inside the widget, edges included.
  ## Widget.collide_point
  w.x <= x and x <= w.right and w.y <= y and y <= w.top

proc collideWidget*(w, other: Widget): bool =
  ## Whether the two boxes overlap. Widget.collide_widget
  if w.right < other.x: return false
  if w.x > other.right: return false
  if w.top < other.y: return false
  if w.y > other.top: return false
  result = true

# ------------------------------------------------------------------ touches

method onTouchDown*(w: Widget; touch: MotionEvent): bool =
  ## A disabled widget swallows a touch down on it; otherwise the children
  ## get it, newest first, until one returns true. Widget.on_touch_down
  result = false
  if w.disabled and w.collidePoint(touch.pos[0], touch.pos[1]):
    return true
  for c in w.children:
    if c.dispatch("on_touch_down", toValue(touch)):
      return true

method onTouchMove*(w: Widget; touch: MotionEvent): bool =
  ## The children get the move, newest first; nothing while disabled.
  ## Widget.on_touch_move
  result = false
  if w.disabled:
    return false
  for c in w.children:
    if c.dispatch("on_touch_move", toValue(touch)):
      return true

method onTouchUp*(w: Widget; touch: MotionEvent): bool =
  ## The children get the end, newest first; nothing while disabled.
  ## Widget.on_touch_up
  result = false
  if w.disabled:
    return false
  for c in w.children:
    if c.dispatch("on_touch_up", toValue(touch)):
      return true

# ------------------------------------------------------------------ tree

proc addChildCanvas(group: InstructionGroup; c: Canvas) =
  group.add(c)

method addWidget*(w: Widget; widget: WidgetBase; index = 0; canvas = "") =
  ## Adds a child at `index` in `children` (0: on top). Its canvas goes
  ## after the canvas of the child it is placed above, into `canvas.before`
  ## or `canvas.after` when `canvas` says so and `index` is 0. Adding a
  ## non-widget, the widget itself or a widget that has a parent stops the
  ## program with Kivy's WidgetException. Widget.add_widget
  if not (widget of Widget):
    quit "WidgetException: add_widget() can be used only with instances of the Widget class."
  let child = Widget(widget)
  if child == w:
    quit "WidgetException: Widget instances cannot be added to themselves."
  let parent = child.parent
  if parent != nil:
    quit "WidgetException: Cannot add <" & child.cls.name & ">, it already has a parent <" &
      parent.cls.name & ">"
  child.parent = w
  child.incDisabled(w.disabledCount)
  var children = w.children
  if index == 0 or children.len == 0:
    children.insert([WidgetBase(child)], 0)
    w.children = children
    if canvas == "before":
      w.canvas.before.addChildCanvas(child.canvas)
    elif canvas == "after":
      w.canvas.after.addChildCanvas(child.canvas)
    else:
      w.canvas.add(child.canvas)
  else:
    # Kivy places the child in `self.canvas` here, whatever `canvas` says.
    let c = w.canvas
    # A negative index counts from the end, as Python's list indexing does.
    var i = Natural(max(0, if index < 0: children.len + index else: index))
    var nextIndex = 0
    if i >= children.len:
      i = children.len
      nextIndex = c.indexof(children[children.len - 1].canvas)
    else:
      let nextChild = children[i]
      nextIndex = c.indexof(nextChild.canvas)
      if nextIndex == -1:
        nextIndex = c.length
      else:
        inc nextIndex
    children.insert([WidgetBase(child)], i)
    w.children = children
    # never before canvas.before
    if nextIndex == 0 and c.hasBefore:
      nextIndex = 1
    c.insert(nextIndex, child.canvas)

method removeWidget*(w: Widget; widget: WidgetBase) =
  ## Removes a child and its canvas; a widget that is not a child is
  ## ignored. Widget.remove_widget
  var children = w.children
  let i = children.find(widget)
  if i < 0:
    return
  children.delete(i)
  w.children = children
  let c = widget.canvas
  if w.canvas.indexof(c) >= 0:
    w.canvas.remove(c)
  elif w.canvas.after.indexof(c) >= 0:
    w.canvas.after.remove(c)
  elif w.canvas.before.indexof(c) >= 0:
    w.canvas.before.remove(c)
  widget.parent = nil
  if widget of Widget:
    Widget(widget).decDisabled(w.disabledCount)

proc clearWidgets*(w: Widget; children: seq[WidgetBase]) =
  ## Removes the given children. Widget.clear_widgets
  for c in children:
    w.removeWidget(c)

proc clearWidgets*(w: Widget) =
  ## Removes every child. Widget.clear_widgets
  w.clearWidgets(w.children)

proc walkFrom(w: Widget; restrict, loopback: bool; index: int; start: Widget;
    acc: var seq[Widget]): bool =
  # Widget._walk, feeding Widget.walk: a node is added unless it is the start
  # widget again, which ends the walk (returns true). `index` -1 is None.
  var index = index
  if index < 0:
    index = w.children.len
    if acc.len > 0 and w == start: return true
    acc.add w
  let children = w.children
  var i = index - 1
  while i >= 0:
    let c = children[i]
    if c of Widget:
      if walkFrom(Widget(c), true, false, -1, start, acc): return true
    dec i
  result = false
  if not restrict:
    let parent = w.parent
    var next = w
    var nextIndex = -1
    if parent == nil or not (parent of Widget) or parent.children.find(WidgetBase(w)) < 0:
      if not loopback:
        return false
    else:
      next = Widget(parent)
      nextIndex = parent.children.find(WidgetBase(w))
    result = walkFrom(next, false, loopback, nextIndex, start, acc)

proc walk*(w: Widget; restrict = false; loopback = false): seq[Widget] =
  ## The widget, then its descendants depth first, oldest child first; then,
  ## unless `restrict`, the widgets added after it to its parent and on up
  ## the tree; with `loopback`, round to the start again. Widget.walk
  result = @[]
  discard walkFrom(w, restrict, loopback, -1, w, result)

# ------------------------------------------------------------------ coordinates

method toLocal*(w: Widget; x, y: float; relative = false): (float, float) {.base.} =
  ## Parent coordinates to this widget's: unchanged, or relative to the
  ## widget's position with `relative`. Widget.to_local
  if relative: (x - w.x, y - w.y) else: (x, y)

method toParent*(w: Widget; x, y: float; relative = false): (float, float) =
  ## This widget's coordinates to its parent's. Widget.to_parent
  if relative: (x + w.x, y + w.y) else: (x, y)

method toWidget*(w: Widget; x, y: float; relative = false): (float, float) =
  ## Window coordinates to this widget's. Widget.to_widget
  var (x, y) = (x, y)
  let p = w.parent
  if p != nil:
    (x, y) = p.toWidget(x, y)
  result = w.toLocal(x, y, relative = relative)

method toWindow*(w: Widget; x, y: float; initial = true;
    relative = false): (float, float) =
  ## This widget's coordinates to the window's. Widget.to_window
  var (x, y) = (x, y)
  if not initial:
    (x, y) = w.toParent(x, y, relative = relative)
  let p = w.parent
  if p != nil:
    return p.toWindow(x, y, initial = false, relative = relative)
  result = (x, y)
