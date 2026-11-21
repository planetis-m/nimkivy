# Tests of input/motionevent (ACCEPTANCE.md, layer 5): grab and ungrab,
# push, pop and apply_transform_2d on plain numbers, the normalized and
# window positions, and `ud`. Kivy's test_motion_event.py tests rotation,
# which is out of scope.

import std/assertions
import nimkivy/event
import nimkivy/input/motionevent

type
  Touch = ref object of MotionEvent
    # kivy/tests/common.py UnitTestTouch: args are (sx, sy).

method depack(t: Touch; args: seq[Value]) =
  t.sx = args[0].num
  t.sy = args[1].num
  procCall depack(MotionEvent(t), args)

proc newTouch(sx, sy: float): Touch =
  result = Touch()
  result.initMotionEvent("UnitTestTouch", "99", @[toValue(sx), toValue(sy)],
    isTouch = true, typeId = "touch")
  result.profile = @["pos"]

proc newDispatcher(): EventDispatcher =
  newEventDispatcher(newDispatcherClass("Widget"))

block grab_and_ungrab:
  let t = newTouch(0.5, 0.5)
  let a = newDispatcher()
  let b = newDispatcher()
  t.grab(a)
  t.grab(b)
  assert t.grabList.len == 2 and t.grabList[0] == a and t.grabList[1] == b
  t.ungrab(a)
  assert t.grabList.len == 1 and t.grabList[0] == b
  t.ungrab(a)                      # not grabbed: nothing happens
  assert t.grabList.len == 1
  t.ungrab(b)
  assert t.grabList.len == 0
  t.grab(a, exclusive = true)
  assert t.grabExclusiveClass == a
  t.ungrab(a)
  assert t.grabExclusiveClass == nil and t.grabList.len == 0

block positions:
  let t = newTouch(0.25, 0.5)
  assert t.osx == 0.25 and t.psx == 0.25 and t.dsx == 0.0
  t.scaleForScreen(801, 601)
  assert t.pos == (200.0, 300.0)
  assert t.opos == (200.0, 300.0) and t.ppos == (200.0, 300.0) and t.dpos == (0.0, 0.0)
  t.dispatchDone()
  t.move(@[toValue(0.5), toValue(0.75)])
  assert t.psx == 0.25 and t.osx == 0.25 and t.dsx == 0.25
  t.scaleForScreen(801, 601)
  assert t.pos == (400.0, 450.0)
  assert t.opos == (200.0, 300.0) and t.ppos == (200.0, 300.0) and t.dpos == (200.0, 150.0)
  # A second move before the dispatch keeps the previous position.
  t.move(@[toValue(1.0), toValue(1.0)])
  assert t.psx == 0.25
  assert t.spos == (1.0, 1.0)
  assert not t.isMouseScrolling
  t.profile.add "button"
  t.button = "scrollup"
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

block user_data:
  let t = newTouch(0.0, 0.0)
  let w = newDispatcher()
  assert toValue(RootRef(w)) notin t.ud
  t.ud[toValue(RootRef(w))] = toValue(true)
  assert toValue(RootRef(w)) in t.ud
  assert toValue(RootRef(newDispatcher())) notin t.ud
  t.ud["name"] = toValue("x")
  assert "name" in t.ud and t.ud.getOrDefault("name").str == "x"
  assert t.ud.len == 2
  t.ud.del(toValue("name"))
  assert "name" notin t.ud

block unique_ids:
  let a = newTouch(0.0, 0.0)
  let b = newTouch(0.0, 0.0)
  assert b.uid == a.uid + 1
  assert toMotionEvent(toValue(a)) == MotionEvent(a)
