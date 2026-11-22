# Test helpers (not a test file: the name does not start with `t`):
# UnitTestTouch, kivy/tests/common.py: a touch posted straight into the
# event loop, as Kivy's tests and archive/reference/traces.py do.

import nimkivy/base

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
