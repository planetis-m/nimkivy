# Stubs for the layer 5 tests (not a test file: the name does not start
# with `t`):
#
# - StubWidget, until Widget exists (layer 6): a box with a canvas, children
#   and Kivy's Widget touch dispatch (uix/widget.py on_touch_down/move/up: a
#   disabled widget swallows a touch down on it; children newest first; the
#   first true stops).
# - UnitTestTouch, kivy/tests/common.py: a touch posted straight into the
#   event loop, as Kivy's tests and reference/traces.py do.

import std/sequtils
import nimkivy/base
import nimkivy/graphics/instructions

type
  StubWidget* = ref object of WidgetBase
    x*, y*, width*, height*: float
    disabled*: bool

let StubWidgetClass* = newDispatcherClass("Widget", WidgetBaseClass)

proc initStubWidget*(w: StubWidget; x, y, width, height: float) =
  w.initWidgetBase()
  w.x = x
  w.y = y
  w.width = width
  w.height = height
  w.disabled = false

proc newStubWidget*(x = 0.0; y = 0.0; width = 100.0; height = 100.0): StubWidget =
  result = StubWidget(cls: StubWidgetClass, canvas: newCanvas())
  result.initStubWidget(x, y, width, height)

proc collidePoint*(w: StubWidget; x, y: float): bool =
  # Widget.collide_point: edges included.
  w.x <= x and x <= w.x + w.width and w.y <= y and y <= w.y + w.height

method addWidget*(w: StubWidget; widget: WidgetBase; index = 0; canvas = "") =
  # Widget.add_widget with index 0: newest first, canvas added last.
  widget.parent = w
  var cs = w.children
  cs.insert([widget], 0)
  w.children = cs
  w.canvas.add widget.canvas

method onTouchDown*(w: StubWidget; touch: MotionEvent): bool =
  result = false
  if w.disabled and w.collidePoint(touch.x, touch.y):
    return true
  for c in w.children:
    if c.dispatch("on_touch_down", toValue(touch)):
      return true

method onTouchMove*(w: StubWidget; touch: MotionEvent): bool =
  result = false
  if w.disabled:
    return false
  for c in w.children:
    if c.dispatch("on_touch_move", toValue(touch)):
      return true

method onTouchUp*(w: StubWidget; touch: MotionEvent): bool =
  result = false
  if w.disabled:
    return false
  for c in w.children:
    if c.dispatch("on_touch_up", toValue(touch)):
      return true

type
  UnitTestTouch* = ref object of MotionEvent
    ## kivy/tests/common.py UnitTestTouch: args are the normalized x and y.

method depack*(t: UnitTestTouch; args: seq[Value]) =
  t.sx = args[0].num
  t.sy = args[1].num
  procCall depack(MotionEvent(t), args)

proc newUnitTestTouch*(x, y: float): UnitTestTouch =
  ## A touch at window position (x, y).
  let win = Window
  result = UnitTestTouch()
  result.initMotionEvent("UnitTestTouch", "99",
    @[toValue(x / (win.width - 1.0)), toValue(y / (win.height - 1.0))],
    isTouch = true, typeId = "touch")
  result.profile = @["pos"]

proc touchDown*(t: UnitTestTouch) =
  EventLoop.postDispatchInput("begin", t)

proc touchMove*(t: UnitTestTouch; x, y: float) =
  let win = Window
  t.move(@[toValue(x / (win.width - 1.0)), toValue(y / (win.height - 1.0))])
  EventLoop.postDispatchInput("update", t)

proc touchUp*(t: UnitTestTouch) =
  EventLoop.postDispatchInput("end", t)
