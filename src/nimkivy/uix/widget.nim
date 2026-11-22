## The widget: Kivy's `kivy/uix/widget.py` (Widget).
##
## A widget is a box (`x`, `y`, `width`, `height` and the properties made of
## them), size and position hints for the layouts, a canvas, children, and
## the touch events. Touches go to the children, newest first, until one
## returns true; a disabled widget swallows a touch down on it and ignores
## moves and ends. `disabled` is a count shared down the tree, as in Kivy's
## `inc_disabled` and `dec_disabled`.
##
## The box and the hints are typed properties of `HintedWidget`
## (core/window), Widget's base, which the window reads and binds too;
## `opacity` and `disabled` are Widget's own.
##
## Build a widget with `newWidget()`. A subclass's constructor makes the
## object (`T(canvas: newCanvas())`), calls `initProps` once
## (for its own type: this sets every property's default, the base types'
## too), then `initWidget` (or its base's `init` proc, which calls it). As
## in Kivy, creating a widget opens the window (`EventLoop.ensureWindow`).
##
## Out of scope (SCOPE.md): `ids`, `cls`, `motion_filter` and `on_motion`,
## `on_kv_post`, `export_to_png` and `export_as_image`, `walk_reverse`,
## `proxy_ref`, `get_parent_window` and `get_window_matrix`.

import std/[opt, sequtils, syncio]
import ../base
import ../graphics/instructions

export opt, base, instructions

properties:
  type
    Widget* = ref object of HintedWidget
      ## The base of every widget. uix/widget.py Widget
      disabledCount: int            # _disabled_count: own and inherited
      disabledValue: bool           # _disabled_value: the value last set
      opacity* {.prop, handler.}: float = 1.0  ## multiplies down to the children
      disabled* {.alias: (getDisabled, setDisabled).}: bool  ## it or a parent is disabled

  method onOpacityChanged*(w: Widget; v: float) {.base.} =
    ## The canvas follows `opacity`. Widget.on_opacity
    w.canvas.opacity = v

  proc getDisabled(w: Widget): bool =
    # Widget.get_disabled
    w.disabledCount > 0

  proc incDisabled*(w: Widget; count = 1)
  proc decDisabled*(w: Widget; count = 1)

  proc setDisabled(w: Widget; value: bool): bool =
    # Widget.set_disabled
    result = false
    if value != w.disabledValue:
      w.disabledValue = value
      if value:
        w.incDisabled()
      else:
        w.decDisabled()
      result = true

  # ---------------------------------------------------------------- construction

  proc initWidget*(w: Widget) =
    ## Sets up a new widget whose properties `initProps` has set: opens the
    ## window first, as Kivy's Widget.__init__ does, then the widget base.
    EventLoop.ensureWindow()
    w.disabledValue = false
    w.disabledCount = 0
    w.initWidgetBase()

  proc newWidget*(): Widget =
    ## A plain widget at (0, 0), 100 x 100.
    result = Widget(canvas: newCanvas(), disabledCount: 0,
      disabledValue: false)
    result.initProps()
    result.initWidget()

  iterator widgetChildren*(w: WidgetBase): Widget {.sideEffect.} =
    ## The children that are widgets, newest first.
    for c in w.children:
      if c of Widget: yield Widget(c)

  # ------------------------------------------------------------------ disabled

  proc incDisabled*(w: Widget; count = 1) =
    ## Adds `count` to the disabled count of the widget and its children.
    ## Widget.inc_disabled
    w.disabledCount += count
    if w.disabledCount - count < 1 and 1 <= w.disabledCount:
      w.dispatchDisabled()
    for c in w.widgetChildren:
      c.incDisabled(count)

  proc decDisabled*(w: Widget; count = 1) =
    ## Takes `count` from the disabled count of the widget and its children.
    ## Widget.dec_disabled
    w.disabledCount -= count
    if w.disabledCount <= 0 and 0 < w.disabledCount + count:
      w.dispatchDisabled()
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
      if c.dispatchTouchDown(touch):
        return true

  method onTouchMove*(w: Widget; touch: MotionEvent): bool =
    ## The children get the move, newest first; nothing while disabled.
    ## Widget.on_touch_move
    result = false
    if w.disabled:
      return false
    for c in w.children:
      if c.dispatchTouchMove(touch):
        return true

  method onTouchUp*(w: Widget; touch: MotionEvent): bool =
    ## The children get the end, newest first; nothing while disabled.
    ## Widget.on_touch_up
    result = false
    if w.disabled:
      return false
    for c in w.children:
      if c.dispatchTouchUp(touch):
        return true

  # ------------------------------------------------------------------ tree

  proc addChildCanvas(group: InstructionGroup; c: sink Canvas) =
    group.add(c)

  # GAP: `widget` is not sink, because a captured sink parameter is never freed
  # (planetis-m/nimony-bugs-llms#348; WindowBase's override captures it, and an
  # override keeps its base's signature)
  method addWidget*(w: Widget; widget: WidgetBase; index = 0; canvas = layerCanvas) =
    ## Adds a child at `index` in `children` (0: on top). Its canvas goes
    ## after the canvas of the child it is placed above, into `canvas.before`
    ## or `canvas.after` when `canvas` says so and `index` is 0. Adding a
    ## non-widget, the widget itself or a widget that has a parent stops the
    ## program (Kivy raises WidgetException). Widget.add_widget
    if not (widget of Widget):
      quit "only a Widget can be added to a widget"
    let child = Widget(widget)
    if child == w:
      quit "a widget cannot be added to itself"
    let parent = child.parent
    if parent != nil:
      quit "cannot add a widget that already has a parent"
    child.parent = w
    child.incDisabled(w.disabledCount)
    var children = w.children
    if index == 0 or children.len == 0:
      children.insert([WidgetBase(child)], 0)
      w.children = children
      case canvas
      of layerBefore: w.canvas.before.addChildCanvas(child.canvas)
      of layerAfter: w.canvas.after.addChildCanvas(child.canvas)
      of layerCanvas: w.canvas.add(child.canvas)
    else:
      # Kivy places the child in `self.canvas` here, whatever `canvas` says.
      let c = w.canvas
      # A negative index counts from the end, as in Kivy.
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
      acc: var seq[WidgetBase]): bool =
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

  iterator walk*(w: Widget; restrict = false; loopback = false): Widget {.sideEffect.} =
    ## The widget, then its descendants depth first, oldest child first; then,
    ## unless `restrict`, the widgets added after it to its parent and on up
    ## the tree; with `loopback`, round to the start again. Widget.walk (a
    ## generator: here the walk is collected first, then yielded)
    # A `seq[Widget]` in this module crashes shoggoth
    # (planetis-m/nimony-bugs-llms#337), so the walk is kept as WidgetBase.
    var acc: seq[WidgetBase] = @[]
    discard walkFrom(w, restrict, loopback, -1, w, acc)
    for c in acc: yield Widget(c)

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
