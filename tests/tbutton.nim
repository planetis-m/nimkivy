# Tests uix/behaviors/button (ButtonBehavior) against kivy/uix/behaviors/
# button.py: press and release through the event loop, a release off the
# button, always_release, min_state_time, trigger_action, the children
# first, mouse scrolling and the `touch.ud` guard. The `touch` trace checks
# the dispatch order against Kivy's.

import std/[assertions, os, syncio]
import nimkivy/[clock, config, base]
import nimkivy/uix/behaviors/button
import stubs

type
  TButton = ref object of Widget
    # class TButton(ButtonBehavior, Widget)
    button: nil ButtonBehavior
    log: seq[string]

  Blocker = ref object of Widget
    # A child that takes every touch down.

let TButtonClass = newDispatcherClass("TButton", WidgetClass)
TButtonClass.addButtonBehavior()
let BlockerClass = newDispatcherClass("Blocker", WidgetClass)

proc onPress(d: EventDispatcher; args: seq[Value]): bool =
  TButton(d).log.add "press"
  result = false

proc onRelease(d: EventDispatcher; args: seq[Value]): bool =
  TButton(d).log.add "release"
  result = false

TButtonClass.setEventHandler("on_press", onPress)
TButtonClass.setEventHandler("on_release", onRelease)

proc bb(b: TButton): ButtonBehavior =
  let x = b.button
  if x == nil: quit "TButton without its ButtonBehavior"
  result = x

method onTouchDown(b: TButton; t: MotionEvent): bool =
  b.bb.onTouchDown(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchDown(Widget(b), t))

method onTouchMove(b: TButton; t: MotionEvent): bool =
  b.bb.onTouchMove(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchMove(Widget(b), t))

method onTouchUp(b: TButton; t: MotionEvent): bool =
  b.bb.onTouchUp(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchUp(Widget(b), t))

method onTouchDown(b: Blocker; t: MotionEvent): bool = b.collidePoint(t.x, t.y)

proc newTButton(): TButton =
  # A 100 x 100 button at (100, 100), in the window.
  result = TButton(cls: TButtonClass, canvas: newCanvas(), button: nil, log: @[])
  result.initWidget()
  result.button = newButtonBehavior(result)
  result.sizeHint = (none[float](), none[float]())
  result.pos = (100.0, 100.0)
  let b = result
  b.bind("state", proc (d: EventDispatcher; v: Value) {.closure.} =
    b.log.add "state " & v.str)
  Window.addWidget(result)

proc tap(x, y: float; moveTo = (-1.0, -1.0)): UnitTestTouch =
  let t = newUnitTestTouch(x, y)
  t.touchDown()
  if moveTo[0] >= 0:
    t.touchMove(moveTo[0], moveTo[1])
  t.touchUp()
  result = t

proc settle() =
  # Waits past min_state_time (.035 s) and runs the delayed release.
  sleep(60)
  Clock.tick()

Config.set("graphics", "width", "800")
Config.set("graphics", "height", "600")
EventLoop.ensureWindow()

block defaults:
  let b = newTButton()
  let bb = b.bb
  assert bb.state == stateNormal and bb.lastTouch == nil
  assert not bb.alwaysRelease
  assert bb.minStateTime == Config.getfloat("graphics", "min_state_time")
  assert bb.minStateTime == 0.035
  assert bb.widget == Widget(b)
  Window.removeWidget(b)

block press_and_release:
  # The press is down until min_state_time has passed, then normal.
  let b = newTButton()
  let t = tap(150, 150)
  assert b.log == @["state down", "press", "release"], $b.log
  assert b.bb.state == stateDown
  assert b.bb.lastTouch == MotionEvent(t)
  settle()
  assert b.log == @["state down", "press", "release", "state normal"], $b.log
  assert b.bb.state == stateNormal
  Window.removeWidget(b)

block release_outside:
  # Ending off the button releases it at once, without on_release.
  let b = newTButton()
  discard tap(150, 150, (500.0, 500.0))
  assert b.log == @["state down", "press", "state normal"], $b.log
  settle()
  assert b.log.len == 3
  # always_release: on_release even off the button.
  b.log = @[]
  b.bb.alwaysRelease = true
  discard tap(150, 150, (500.0, 500.0))
  settle()
  assert b.log == @["state down", "press", "release", "state normal"], $b.log
  Window.removeWidget(b)

block min_state_time:
  # 0: normal at once. A pending delayed release is cancelled when the state
  # changes before it runs.
  let b = newTButton()
  b.bb.minStateTime = 0
  discard tap(150, 150)
  assert b.log == @["state down", "press", "state normal", "release"], $b.log
  b.log = @[]
  b.bb.minStateTime = 10
  discard tap(150, 150)
  assert b.bb.state == stateDown
  b.bb.state = stateNormal            # cancels the delayed release
  b.bb.state = stateDown
  settle()
  assert b.bb.state == stateDown
  Window.removeWidget(b)

block trigger_action:
  let b = newTButton()
  b.bb.triggerAction(0)
  assert b.log == @["state down", "press", "state normal", "release"], $b.log
  b.log = @[]
  b.bb.triggerAction(0.01)
  assert b.log == @["state down", "press"], $b.log
  settle()
  assert b.log == @["state down", "press", "state normal", "release"], $b.log
  Window.removeWidget(b)

block children_first:
  # A child that takes the touch keeps the button from being pressed.
  let b = newTButton()
  let child = Blocker(cls: BlockerClass, canvas: newCanvas())
  child.initWidget()
  child.pos = (100.0, 100.0)
  child.size = (50.0, 50.0)
  b.addWidget(child)
  discard tap(120, 120)
  assert b.log.len == 0
  discard tap(180, 180)                # outside the child
  settle()
  assert b.log == @["state down", "press", "release", "state normal"], $b.log
  Window.removeWidget(b)

block scroll_and_ud:
  # A mouse wheel step does not press; a touch the button has seen does not
  # press it again.
  let b = newTButton()
  # Dispatched to the button directly: the window coordinates are set as the
  # event loop sets them.
  let wheel = newUnitTestTouch(150, 150)
  wheel.scaleForScreen(Window.width, Window.height)
  wheel.profile.add "button"
  wheel.button = "scrolldown"
  assert not b.dispatch("on_touch_down", toValue(wheel))
  assert b.log.len == 0
  let t = newUnitTestTouch(150, 150)
  t.scaleForScreen(Window.width, Window.height)
  assert b.dispatch("on_touch_down", toValue(t))
  assert not b.dispatch("on_touch_down", toValue(t))
  assert b.log == @["state down", "press"], $b.log
  # A move of the grabbed touch, or of one it pressed, is the button's.
  assert b.dispatch("on_touch_move", toValue(t))
  t.ungrab(b)
  Window.removeWidget(b)

