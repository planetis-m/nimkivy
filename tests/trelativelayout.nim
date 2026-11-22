# Tests of uix/relativelayout (ACCEPTANCE.md, layer 6):
# kivy/tests/test_uix_relativelayout.py and the Widget and RelativeLayout
# cases of test_uix_translate_coordinates.py (Scatter and ScrollView are out
# of scope; the kv trees are built in code), plus touches in local
# coordinates.

import std/[assertions, syncio]
import nimkivy/clock
import nimkivy/uix/relativelayout

type UTMotionEvent = ref object of MotionEvent
  # kivy/tests/__init__.py UTMotionEvent: a touch at a normalized position.

method depack(t: UTMotionEvent; sx, sy: float) =
  t.isTouch = true
  t.profile = {mpPos}
  procCall depack(MotionEvent(t), sx, sy)

proc newUTMotionEvent(device: string; id: int; x, y: float): UTMotionEvent =
  result = UTMotionEvent()
  result.initMotionEvent(device, $id, x, y)

block test_relativelayout_on_touch_move:
  # kivy/tests/test_uix_relativelayout.py::test_relativelayout_on_touch_move
  EventLoop.ensureWindow()
  let rl = newRelativeLayout()
  Window.addWidget(rl)
  let touch = newUTMotionEvent("unittest", 1, 0.5, 0.5)
  EventLoop.postDispatchInput(maBegin, touch)
  touch.move(0.6, 0.4)
  EventLoop.postDispatchInput(maUpdate, touch)
  EventLoop.postDispatchInput(maEnd, touch)
  Window.removeWidget(rl)

block test_relativelayout_coordinates:
  # kivy/tests/test_uix_relativelayout.py::test_relativelayout_coordinates
  EventLoop.ensureWindow()
  let rl = newRelativeLayout()
  rl.pos = (100.0, 100.0)
  Window.addWidget(rl)   # do_layout() called
  assert rl.toParent(50, 50) == (150.0, 150.0)
  assert rl.toLocal(50, 50) == (-50.0, -50.0)
  Window.removeWidget(rl)

block test_to_local_and_to_parent_relative:
  # kivy/tests/test_uix_translate_coordinates.py::test_to_local_and_to_parent__relative,
  # RelativeLayout (Nim block names cannot hold "__")
  let widget = newRelativeLayout()
  widget.pos = (100.0, 100.0)
  Clock.tick()
  assert widget.toLocal(0, 0) == (-100.0, -100.0)
  assert widget.toParent(0, 0) == (100.0, 100.0)

block test_to_local_and_to_parent_not_relative:
  # kivy/tests/test_uix_translate_coordinates.py::
  # test_to_local_and_to_parent__not_relative, Widget
  let widget = newWidget()
  widget.pos = (100.0, 100.0)
  Clock.tick()
  assert widget.toLocal(0, 0) == (0.0, 0.0)
  assert widget.toParent(0, 0) == (0.0, 0.0)

proc make(relative: bool): Widget =
  if relative: result = newRelativeLayout()
  else: result = newWidget()

block test_to_window_and_to_widget:
  # kivy/tests/test_uix_translate_coordinates.py::test_to_window_and_to_widget, every pair of Widget and
  # RelativeLayout: root at (100, 0), a plain Widget at (0, 0) in it, and
  # the target at (0, 100) in that.
  for rootRelative in [false, true]:
    for targetRelative in [false, true]:
      let root = make(rootRelative)
      root.pos = (100.0, 0.0)
      let cushion = newWidget()
      cushion.pos = (0.0, 0.0)
      root.addWidget(cushion)
      let target = make(targetRelative)
      target.pos = (0.0, 100.0)
      cushion.addWidget(target)
      Clock.tick()
      Clock.tickDraw()
      if rootRelative:
        assert target.toWindow(target.x, target.y) == (100.0, 100.0)
        assert target.toWidget(0, 0) ==
          (if targetRelative: (-100.0, -100.0) else: (-100.0, 0.0))
      else:
        assert target.toWindow(target.x, target.y) == (0.0, 100.0)
        assert target.toWidget(0, 0) ==
          (if targetRelative: (0.0, -100.0) else: (0.0, 0.0))

block touches_in_local_coordinates:
  # RelativeLayout.on_touch_*: children get the touch in local
  # coordinates, and the touch is back in the parent's afterwards.
  let rl = newRelativeLayout()
  rl.pos = (100.0, 50.0)
  let child = newWidget()
  var seen: seq[(float, float)] = @[]
  discard child.bindTouchDown(proc (t: MotionEvent): bool {.closure.} =
    seen.add t.pos
    result = false)
  rl.addWidget(child)
  let t = newUTMotionEvent("unittest", 2, 0.5, 0.5)
  t.scaleForScreen(800, 600)
  discard rl.dispatchTouchDown(t)
  assert seen.len == 1 and seen[0] == (t.x - 100.0, t.y - 50.0)
  # The canvas is translated by pos, and follows it.
  let tr = rl.translate
  assert tr != nil
  assert tr.xy == (100.0, 50.0)
  rl.pos = (7.0, 8.0)
  assert tr.xy == (7.0, 8.0)
  assert rl.canvas.hasBefore and rl.canvas.hasAfter
  # Children are laid out in local coordinates, not again on a move.
  rl.size = (300.0, 200.0)
  child.posHint = {phX: 0.5}
  Clock.tickDraw()
  assert child.pos == (150.0, 0.0) and child.size == (300.0, 200.0)
  rl.pos = (40.0, 40.0)
  Clock.tickDraw()
  assert child.pos == (150.0, 0.0)

echo "trelativelayout: ok"
