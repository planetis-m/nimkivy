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
  TButtonPart = ref object of ButtonBehavior
    # TButton's on_press and on_release, logged.
    log: seq[string]

  TButton = ref object of Widget
    # class TButton(ButtonBehavior, Widget)
    button: TButtonPart

  Blocker = ref object of Widget
    # A child that takes every touch down.

let TButtonClass = newDispatcherClass("TButton", WidgetClass)
let BlockerClass = newDispatcherClass("Blocker", WidgetClass)

method onPress(b: TButtonPart): bool =
  b.log.add "press"
  result = false

method onRelease(b: TButtonPart): bool =
  b.log.add "release"
  result = false

method onTouchDown(b: TButton; t: MotionEvent): bool =
  result = procCall onTouchDown(Widget(b), t)
  if not result: result = b.button.touchDown(b, t)

method onTouchMove(b: TButton; t: MotionEvent): bool =
  result = b.button.grabbed(b, t)
  if not result: result = procCall onTouchMove(Widget(b), t)
  if not result: result = b.button.touchMove(b, t)

method onTouchUp(b: TButton; t: MotionEvent): bool =
  if b.button.grabbed(b, t): result = b.button.touchUp(b, t)
  else: result = procCall onTouchUp(Widget(b), t)

method onTouchDown(b: Blocker; t: MotionEvent): bool = b.collidePoint(t.x, t.y)

proc newTButtonPart(): TButtonPart =
  result = TButtonPart(log: @[])
  result.initProps()
  result.initButtonBehavior()

proc newTButton(): TButton =
  # A 100 x 100 button at (100, 100), in the window.
  result = TButton(cls: TButtonClass, canvas: newCanvas(), button: newTButtonPart())
  result.initProps()
  result.initWidget()
  result.sizeHint = (none[float](), none[float]())
  result.pos = (100.0, 100.0)
  let bb = result.button
  discard bb.bindState(proc (v: ButtonState) {.closure.} =
    bb.log.add "state " & $v)
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

Config.graphics.width = 800
Config.graphics.height = 600
EventLoop.ensureWindow()

block defaults:
  let b = newTButton()
  let bb = b.button
  assert bb.state == stateNormal and bb.lastTouch == nil
  assert not bb.alwaysRelease
  assert bb.minStateTime == Config.graphics.minStateTime
  assert bb.minStateTime == 0.035
  Window.removeWidget(b)

block press_and_release:
  # The press is down until min_state_time has passed, then normal.
  let b = newTButton()
  let t = tap(150, 150)
  assert b.button.log == @["state down", "press", "release"], $b.button.log
  assert b.button.state == stateDown
  assert b.button.lastTouch == MotionEvent(t)
  settle()
  assert b.button.log == @["state down", "press", "release", "state normal"], $b.button.log
  assert b.button.state == stateNormal
  Window.removeWidget(b)

block release_outside:
  # Ending off the button releases it at once, without on_release.
  let b = newTButton()
  discard tap(150, 150, (500.0, 500.0))
  assert b.button.log == @["state down", "press", "state normal"], $b.button.log
  settle()
  assert b.button.log.len == 3
  # always_release: on_release even off the button.
  b.button.log = @[]
  b.button.alwaysRelease = true
  discard tap(150, 150, (500.0, 500.0))
  settle()
  assert b.button.log == @["state down", "press", "release", "state normal"], $b.button.log
  Window.removeWidget(b)

block min_state_time:
  # 0: normal at once. A pending delayed release is cancelled when the state
  # changes before it runs.
  let b = newTButton()
  b.button.minStateTime = 0
  discard tap(150, 150)
  assert b.button.log == @["state down", "press", "state normal", "release"], $b.button.log
  b.button.log = @[]
  b.button.minStateTime = 10
  discard tap(150, 150)
  assert b.button.state == stateDown
  b.button.state = stateNormal            # cancels the delayed release
  b.button.state = stateDown
  settle()
  assert b.button.state == stateDown
  Window.removeWidget(b)

block trigger_action:
  let b = newTButton()
  b.button.triggerAction(0)
  assert b.button.log == @["state down", "press", "state normal", "release"], $b.button.log
  b.button.log = @[]
  b.button.triggerAction(0.01)
  assert b.button.log == @["state down", "press"], $b.button.log
  settle()
  assert b.button.log == @["state down", "press", "state normal", "release"], $b.button.log
  Window.removeWidget(b)

block children_first:
  # A child that takes the touch keeps the button from being pressed.
  let b = newTButton()
  let child = Blocker(cls: BlockerClass, canvas: newCanvas())
  child.initProps()
  child.initWidget()
  child.pos = (100.0, 100.0)
  child.size = (50.0, 50.0)
  b.addWidget(child)
  discard tap(120, 120)
  assert b.button.log.len == 0
  discard tap(180, 180)                # outside the child
  settle()
  assert b.button.log == @["state down", "press", "release", "state normal"], $b.button.log
  Window.removeWidget(b)

block scroll_and_ud:
  # A mouse wheel step does not press; a touch the button has seen does not
  # press it again.
  let b = newTButton()
  # Dispatched to the button directly: the window coordinates are set as the
  # event loop sets them.
  let wheel = newUnitTestTouch(150, 150)
  wheel.scaleForScreen(Window.width, Window.height)
  wheel.profile.incl mpButton
  wheel.button = mbScrollDown
  assert not b.dispatchTouchDown(wheel)
  assert b.button.log.len == 0
  let t = newUnitTestTouch(150, 150)
  t.scaleForScreen(Window.width, Window.height)
  assert b.dispatchTouchDown(t)
  assert not b.dispatchTouchDown(t)
  assert b.button.log == @["state down", "press"], $b.button.log
  # A move of the grabbed touch, or of one it pressed, is the button's.
  assert b.dispatchTouchMove(t)
  t.ungrab(b)
  Window.removeWidget(b)

