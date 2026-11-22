# Tests of input/motionevent (ACCEPTANCE.md, layer 5): grab and ungrab,
# push, pop and apply_transform_2d on plain numbers, the normalized and
# window positions, and `claimedBy` (Kivy's `ud`). Kivy's test_motion_event.py tests rotation,
# which is out of scope.

import std/assertions
import nimkivy/input/motionevent

type
  Touch = ref object of MotionEvent
    # kivy/tests/common.py UnitTestTouch: a touch at (sx, sy).
  Thing = ref object of RootObj
    # Something that grabs or claims a touch.

proc newTouch(sx, sy: float): Touch =
  result = Touch()
  result.initMotionEvent("UnitTestTouch", "99", sx, sy, isTouch = true, typeId = "touch")
  result.profile = {mpPos}

proc newThing(): Thing =
  Thing()

block grab_and_ungrab:
  let t = newTouch(0.5, 0.5)
  let a = newThing()
  let b = newThing()
  t.grab(a)
  t.grab(b)
  assert t.grabList.len == 2 and t.grabList[0] == RootRef(a) and t.grabList[1] == RootRef(b)
  t.ungrab(a)
  assert t.grabList.len == 1 and t.grabList[0] == RootRef(b)
  t.ungrab(a)                      # not grabbed: nothing happens
  assert t.grabList.len == 1
  t.ungrab(b)
  assert t.grabList.len == 0
  t.grab(a, exclusive = true)
  assert t.grabExclusiveClass == RootRef(a)
  t.ungrab(a)
  assert t.grabExclusiveClass == nil and t.grabList.len == 0

block positions:
  let t = newTouch(0.25, 0.5)
  assert t.osx == 0.25 and t.psx == 0.25 and t.dsx == 0.0
  t.scaleForScreen(801, 601)
  assert t.pos == (200.0, 300.0)
  assert t.opos == (200.0, 300.0) and t.ppos == (200.0, 300.0) and t.dpos == (0.0, 0.0)
  t.dispatchDone()
  t.move(0.5, 0.75)
  assert t.psx == 0.25 and t.osx == 0.25 and t.dsx == 0.25
  t.scaleForScreen(801, 601)
  assert t.pos == (400.0, 450.0)
  assert t.opos == (200.0, 300.0) and t.ppos == (200.0, 300.0) and t.dpos == (200.0, 150.0)
  # A second move before the dispatch keeps the previous position.
  t.move(1.0, 1.0)
  assert t.psx == 0.25
  assert t.spos == (1.0, 1.0)
  assert not t.isMouseScrolling
  t.profile.incl mpButton
  t.button = mbScrollUp
  assert t.isMouseScrolling

block push_pop_apply_transform_2d:
  let t = newTouch(0.0, 0.0)
  t.x = 10
  t.y = 20
  t.pos = (10.0, 20.0)
  t.px = 5
  t.py = 6
  t.ox = 1
  t.oy = 2
  t.push()
  t.applyTransform2d(proc (x, y: float): (float, float) {.closure.} = (x - 100, y * 2))
  assert t.pos == (-90.0, 40.0) and t.x == -90.0 and t.y == 40.0
  assert t.ppos == (-95.0, 12.0) and t.opos == (-99.0, 4.0)
  assert t.dpos == (5.0, 28.0)
  t.push()
  t.applyTransform2d(proc (x, y: float): (float, float) {.closure.} = (x + 1, y + 1))
  assert t.pos == (-89.0, 41.0)
  t.pop()
  assert t.pos == (-90.0, 40.0)
  t.pop()
  assert t.pos == (10.0, 20.0) and t.x == 10.0 and t.y == 20.0
  assert t.ppos == (5.0, 6.0) and t.opos == (1.0, 2.0)

block claimed_by:
  let t = newTouch(0.0, 0.0)
  let w = newThing()
  assert RootRef(w) notin t.claimedBy
  t.claimedBy.add w
  assert RootRef(w) in t.claimedBy
  assert RootRef(newThing()) notin t.claimedBy

block unique_ids:
  let a = newTouch(0.0, 0.0)
  let b = newTouch(0.0, 0.0)
  assert b.uid == a.uid + 1
