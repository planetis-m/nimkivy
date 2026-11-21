# Tests uix/modalview (ModalView) against kivy/tests/test_uix_modal.py
# test_modal_app, adapted: the root ModalButton(Button) is a Widget with a
# ButtonBehavior, the Window's root, and the touches are posted to the
# EventLoop as UnitKivyApp does (down, moves, up, a frame after each). Also
# on_dismiss returning true, force, Escape, auto_dismiss and the canvas. The
# `modal` trace checks the event order against Kivy's.

import std/[assertions, math, os, syncio]
import nimkivy/[clock, config, base]
import nimkivy/graphics/context_instructions
import nimkivy/uix/modalview
import nimkivy/uix/behaviors/button
import stubs

type
  ModalButton = ref object of Widget
    # test_uix_modal.py ModalButton: a button used as the root widget that
    # must not get a touch while the modal is open.
    button: nil ButtonBehavior
    modal: nil ModalView

let ModalButtonClass = newDispatcherClass("ModalButton", WidgetClass)
ModalButtonClass.addButtonBehavior()

proc bb(b: ModalButton): ButtonBehavior =
  let x = b.button
  if x == nil: quit "ModalButton without its ButtonBehavior"
  result = x

proc checkClosed(b: ModalButton) =
  let m = b.modal
  if m != nil:
    assert m.window == nil
    assert not m.isOpen

method onTouchDown(b: ModalButton; t: MotionEvent): bool =
  b.checkClosed()
  b.bb.onTouchDown(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchDown(Widget(b), t))

method onTouchMove(b: ModalButton; t: MotionEvent): bool =
  b.checkClosed()
  b.bb.onTouchMove(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchMove(Widget(b), t))

method onTouchUp(b: ModalButton; t: MotionEvent): bool =
  b.checkClosed()
  b.bb.onTouchUp(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchUp(Widget(b), t))

proc newModalButton(): ModalButton =
  result = ModalButton(cls: ModalButtonClass, canvas: newCanvas(), button: nil, modal: nil)
  result.initWidget()
  result.button = newButtonBehavior(result)

proc waitFrames(n: int) =
  # UnitKivyApp.wait_clock_frames: n frames of the event loop.
  for _ in 0 ..< n:
    discard EventLoop.idle()

proc touchDownUp(x, y: float) =
  # UnitKivyApp.do_touch_down_up at window position (x, y).
  let t = newUnitTestTouch(x, y)
  t.touchDown()
  waitFrames(1)
  sleep(50)
  t.touchUp()
  waitFrames(1)

proc touchDrag(x, y, tx, ty: float) =
  # UnitKivyApp.do_touch_drag from (x, y) to (tx, ty) in 5 moves.
  let t = newUnitTestTouch(x, y)
  t.touchDown()
  waitFrames(1)
  let dx = (tx - x) / 5
  let dy = (ty - y) / 5
  for i in 0 ..< 5:
    sleep(10)
    t.touchMove(x + float(i + 1) * dx, y + float(i + 1) * dy)
    waitFrames(1)
  t.touchUp()
  waitFrames(1)

Config.set("graphics", "width", "800")
Config.set("graphics", "height", "600")
EventLoop.ensureWindow()

block testModalApp:
  let button = newModalButton()
  let modal = newModalView()
  modal.sizeHint = (0.2, 0.5)
  button.modal = modal
  Window.addWidget(button)
  waitFrames(2)
  modal.animDuration = 0
  assert modal.window == nil
  assert not modal.isOpen

  # just press button
  touchDownUp(button.centerX, button.centerY)
  touchDrag(button.centerX, button.centerY, button.centerX + button.width / 4,
    button.centerY)
  assert modal.window == nil and not modal.isOpen

  # open modal
  modal.open()
  waitFrames(2)
  assert modal.window != nil
  assert modal.isOpen
  assert abs(modal.centerX - button.centerX) <= 0.1
  assert abs(modal.centerY - button.centerY) <= 0.1

  # press within modal area - should stay open
  touchDownUp(button.centerX, button.centerY)
  assert modal.window != nil and modal.isOpen
  # start in modal but release outside - should stay open
  touchDrag(button.centerX, button.centerY, button.centerX + button.width / 4,
    button.centerY)
  assert modal.window != nil and modal.isOpen

  # start outside but release in modal - should close
  touchDrag(button.centerX + button.width / 4, button.centerY, button.centerX,
    button.centerY)
  assert modal.window == nil
  assert not modal.isOpen

  # open modal again
  modal.open()
  waitFrames(2)
  assert modal.window != nil and modal.isOpen

  # press outside modal area - should close
  touchDownUp(button.centerX + button.width / 4, button.centerY)
  assert modal.window == nil
  assert not modal.isOpen
  Window.removeWidget(button)

block events:
  # on_dismiss returning true keeps the view open unless forced; Escape;
  # auto_dismiss false; centred on the window; the fade.
  var log: seq[string] = @[]
  let m = newModalView()
  m.sizeHint = (none[float](), none[float]())
  m.size = (200.0, 100.0)
  var keep = true
  m.bind("on_dismiss", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.add "dismiss"
    result = keep)
  m.open(animation = false)
  assert m.isOpen and m.center == (400.0, 300.0) and m.animAlpha == 1
  assert Window.children[0] == WidgetBase(m)
  m.dismiss(animation = false)
  assert m.isOpen and log == @["dismiss"]
  m.dismiss(animation = false, force = true)
  assert not m.isOpen and Window.children.find(WidgetBase(m)) < 0
  keep = false
  # Escape dismisses with a fade (.1 s).
  m.open(animation = false)
  assert Window.dispatch("on_keyboard", toValue(27), toValue(41), noneValue(),
    toValue(newSeq[Value]()))
  assert m.isOpen
  let t0 = time()
  while time() - t0 < 0.3:
    sleep(10)
    Clock.tick()
  assert not m.isOpen and m.animAlpha == 0
  # Without auto_dismiss, Escape is not handled and a touch outside does
  # not dismiss (and is swallowed).
  m.autoDismiss = false
  m.open(animation = false)
  let t = newUnitTestTouch(10, 10)
  t.scaleForScreen(Window.width, Window.height)
  assert m.dispatch("on_touch_down", toValue(t))
  assert m.dispatch("on_touch_up", toValue(t))
  assert m.isOpen
  m.dismiss(animation = false)
  assert not m.isOpen

block canvas:
  # style.kv: the overlay over the whole window, alpha times _anim_alpha,
  # then the box in background_color.
  let m = newModalView()
  m.overlayColor = [0.2, 0.4, 0.6, 0.5]
  m.backgroundColor = [0.0, 0.0, 0.0, 0.0]
  let c = m.canvas
  m.open(animation = false)
  var colors: seq[array[4, float]] = @[]
  let items = c.children
  for i in items:
    if i of Color: colors.add Color(i).rgba
  assert colors.len == 2
  assert colors[0] == [0.2, 0.4, 0.6, 0.5] and colors[1] == [0.0, 0.0, 0.0, 0.0]
  m.dismiss(animation = false)

echo "tmodalview: all tests passed"
