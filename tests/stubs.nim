# Test helpers (not a test file: the name does not start with `t`):
# UnitTestTouch, kivy/tests/common.py: a touch posted straight into the
# event loop, as Kivy's tests and archive/reference/traces.py do.

import nimkivy/base

type
  UnitTestTouch* = ref object of MotionEvent
    ## kivy/tests/common.py UnitTestTouch: a touch at a window position.

proc newUnitTestTouch*(x, y: float): UnitTestTouch =
  ## A touch at window position (x, y).
  let win = Window
  result = UnitTestTouch()
  result.initMotionEvent("UnitTestTouch", "99", x / (win.width - 1.0),
    y / (win.height - 1.0), isTouch = true, typeId = "touch")
  result.profile = {mpPos}

proc touchDown*(t: UnitTestTouch) =
  EventLoop.postDispatchInput(maBegin, t)

proc touchMove*(t: UnitTestTouch; x, y: float) =
  let win = Window
  t.move(x / (win.width - 1.0), y / (win.height - 1.0))
  EventLoop.postDispatchInput(maUpdate, t)

proc touchUp*(t: UnitTestTouch) =
  EventLoop.postDispatchInput(maEnd, t)
