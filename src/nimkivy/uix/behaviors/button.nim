## Button behaviour: Kivy's `kivy/uix/behaviors/button.py` (ButtonBehavior).
##
## Kivy's ButtonBehavior is a mixin: `class Btn(ButtonBehavior, Widget)`.
## Nim has single inheritance, so here the widget holds a `ButtonBehavior`
## and calls into it (PORTING.md, decision 4):
##
## - `addButtonBehavior(cls)` declares the properties `state`, `last_touch`,
##   `min_state_time` and `always_release`, and the events `on_press` and
##   `on_release`, on the widget's class; a subclass overrides their default
##   handlers with `setEventHandler`.
## - `newButtonBehavior(widget)`, called after the widget is set up, reads
##   `min_state_time` from Config, as Kivy's `__init__` does.
## - The widget's `onTouchDown`, `onTouchMove` and `onTouchUp` methods call
##   the behaviour's, passing what Kivy's `super()` would call there (the
##   parent class's method, through `procCall`) as `inherited`.
##
## A touch down on the widget grabs the touch, sets `state` to down and
## dispatches `on_press`. Its end dispatches `on_release` when it is still on
## the widget (or always, with `always_release`), and `state` goes back to
## normal, but not sooner than `min_state_time` after the press.

import std/assertions
import ../../[properties, clock, config]
import ../widget

export widget

type
  ButtonState* = enum
    ## The `state` of a button (Kivy's strings).
    stateNormal = "normal"     ## not pressed
    stateDown = "down"         ## pressed

  TouchHandler* = proc (touch: MotionEvent): bool {.closure.}
    ## A touch method of the widget's parent class: Kivy's `super()` call.

  ButtonBehavior* = ref object
    ## The button part of a widget. uix/behaviors/button.py ButtonBehavior
    widget: Widget
    stateEvent: nil ClockEvent   # __state_event: the delayed release
    touchTime: float             # __touch_time: when the touch went down

proc noHandler(d: EventDispatcher; args: seq[Value]): bool =
  # ButtonBehavior.on_press and on_release: nothing.
  false

proc addButtonBehavior*(cls: DispatcherClass) =
  ## Declares ButtonBehavior's properties and events on a widget class.
  discard cls.addOption("state", "normal", @["normal", "down"])
  discard cls.addObject("last_touch", noneValue(), allowNone = true)
  discard cls.addNumeric("min_state_time", 0)
  discard cls.addBoolean("always_release", false)
  cls.addEvent("on_press", noHandler)
  cls.addEvent("on_release", noHandler)

proc cancelEvent(b: ButtonBehavior) =
  # ButtonBehavior.cancel_event
  let ev = b.stateEvent
  if ev != nil:
    ev.cancel()
    b.stateEvent = nil

proc newButtonBehavior*(widget: Widget): ButtonBehavior =
  ## The button part of `widget`, whose class has `addButtonBehavior` and
  ## which is set up. Sets `min_state_time` from Config (graphics,
  ## min_state_time); a later `minStateTime=` overrides it, as a keyword
  ## argument does in Kivy. ButtonBehavior.__init__
  result = ButtonBehavior(widget: widget, stateEvent: nil, touchTime: 0)
  widget.setProperty("min_state_time",
    toValue(Config.graphics.minStateTime))
  let b = result
  discard widget.fbind("state", proc (d: EventDispatcher; v: Value) {.closure.} =
    b.cancelEvent())

# ------------------------------------------------------------------ accessors

proc widget*(b: ButtonBehavior): Widget {.inline.} =
  ## The widget this is the button part of (Kivy's `self`).
  b.widget

proc state*(b: ButtonBehavior): ButtonState =
  ## Down while a touch presses the button, else normal.
  if b.widget.getProperty("state").str == "down": stateDown else: stateNormal
proc `state=`*(b: ButtonBehavior; v: ButtonState) =
  ## Sets the state.
  b.widget.setProperty("state", toValue($v))

proc lastTouch*(b: ButtonBehavior): nil MotionEvent =
  ## The last touch that pressed or released the button; nil before.
  result = nil
  let v = b.widget.getProperty("last_touch")
  if v.kind == vkObject:
    let o = v.obj
    if o != nil and o of MotionEvent:
      result = MotionEvent(o)

proc minStateTime*(b: ButtonBehavior): float =
  ## The shortest time, in seconds, the state stays down.
  b.widget.getProperty("min_state_time").num
proc `minStateTime=`*(b: ButtonBehavior; v: float) =
  ## Sets the shortest time the state stays down.
  b.widget.setProperty("min_state_time", toValue(v))

proc alwaysRelease*(b: ButtonBehavior): bool =
  ## Whether `on_release` is dispatched when the touch ends off the button
  ## (default false).
  b.widget.getProperty("always_release").flag
proc `alwaysRelease=`*(b: ButtonBehavior; v: bool) =
  ## Dispatches `on_release` for a touch that ends off the button, or not.
  b.widget.setProperty("always_release", toValue(v))

# ------------------------------------------------------------------ press and release

proc doPress(b: ButtonBehavior) =
  # ButtonBehavior._do_press
  b.state = stateDown

proc doRelease(b: ButtonBehavior) =
  # ButtonBehavior._do_release
  b.state = stateNormal

proc key(b: ButtonBehavior): RootRef {.inline.} =
  # The widget, as it claims a touch (Kivy's `self in touch.ud`).
  RootRef(b.widget)

proc onTouchDown*(b: ButtonBehavior; touch: MotionEvent; inherited: TouchHandler): bool =
  ## The children first (`inherited`); then a touch down on the widget,
  ## not a scroll and not seen before, is grabbed and presses the button.
  ## ButtonBehavior.on_touch_down
  if inherited(touch):
    return true
  if touch.isMouseScrolling:
    return false
  let w = b.widget
  if not w.collidePoint(touch.x, touch.y):
    return false
  if b.key in touch.claimedBy:
    return false
  touch.grab(w)
  touch.claimedBy.add b.key
  w.setProperty("last_touch", toValue(RootRef(touch)))
  b.touchTime = time()
  b.doPress()
  discard w.dispatch("on_press")
  result = true

proc onTouchMove*(b: ButtonBehavior; touch: MotionEvent; inherited: TouchHandler): bool =
  ## A grabbed touch is the button's; otherwise the children's
  ## (`inherited`), or the button's if it pressed it.
  ## ButtonBehavior.on_touch_move
  if touch.grabCurrent == RootRef(b.widget):
    return true
  if inherited(touch):
    return true
  result = b.key in touch.claimedBy

proc onTouchUp*(b: ButtonBehavior; touch: MotionEvent; inherited: TouchHandler): bool =
  ## The end of the touch that pressed the button: ungrabs it and releases
  ## the button, with `on_release` when the touch is still on the widget
  ## (or `always_release`), and `state` normal after `min_state_time`.
  ## Other touches go to `inherited`. Returns false (Kivy's None) for a
  ## release off the widget. ButtonBehavior.on_touch_up
  let w = b.widget
  if touch.grabCurrent != RootRef(w):
    return inherited(touch)
  assert b.key in touch.claimedBy
  touch.ungrab(w)
  w.setProperty("last_touch", toValue(RootRef(touch)))
  if not b.alwaysRelease and not w.collidePoint(touch.pos[0], touch.pos[1]):
    b.doRelease()
    return false
  let touchtime = time() - b.touchTime
  let minStateTime = b.minStateTime
  if touchtime < minStateTime:
    b.stateEvent = Clock.scheduleOnce(proc (dt: float) {.closure.} = b.doRelease(),
      minStateTime - touchtime)
  else:
    b.doRelease()
  discard w.dispatch("on_release")
  result = true

proc triggerAction*(b: ButtonBehavior; duration = 0.1) =
  ## Presses the button without a touch: `on_press` now, then `on_release`
  ## after `duration` seconds (at once for 0). ButtonBehavior.trigger_action
  b.doPress()
  discard b.widget.dispatch("on_press")
  proc triggerRelease(b: ButtonBehavior) =
    b.doRelease()
    discard b.widget.dispatch("on_release")
  if duration == 0:
    triggerRelease(b)
  else:
    discard Clock.scheduleOnce(proc (dt: float) {.closure.} = triggerRelease(b), duration)
