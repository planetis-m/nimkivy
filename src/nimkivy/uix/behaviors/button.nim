## Button behaviour: Kivy's `kivy/uix/behaviors/button.py` (ButtonBehavior).
##
## Kivy's ButtonBehavior is a mixin: `class Btn(ButtonBehavior, Widget)`.
## Nim has single inheritance, so here the button part is an object with its
## own properties and events that the widget owns (PORTING.md, decision 4):
##
## .. code-block:: nim
##   type Btn = ref object of Widget
##     button: ButtonBehavior        # newButtonBehavior(), or a subclass
##
##   method onTouchDown(b: Btn; t: MotionEvent): bool =
##     result = procCall onTouchDown(Widget(b), t)
##     if not result: result = b.button.touchDown(b, t)
##
##   method onTouchMove(b: Btn; t: MotionEvent): bool =
##     result = b.button.grabbed(b, t)
##     if not result: result = procCall onTouchMove(Widget(b), t)
##     if not result: result = b.button.touchMove(b, t)
##
##   method onTouchUp(b: Btn; t: MotionEvent): bool =
##     if b.button.grabbed(b, t): result = b.button.touchUp(b, t)
##     else: result = procCall onTouchUp(Widget(b), t)
##
## The widget's parent class is called where Kivy's ButtonBehavior calls
## `super()`. A subclass of ButtonBehavior overrides `onPress` and
## `onRelease` (Kivy's `on_press` and `on_release` methods); anyone binds
## them with `bindPress` and `bindRelease`.
##
## A touch down on the widget grabs the touch, sets `state` to down and
## dispatches `press`. Its end dispatches `release` when it is still on the
## widget (or always, with `alwaysRelease`), and `state` goes back to
## normal, but not sooner than `minStateTime` after the press.

import std/assertions
import ../../[props, clock, config]
import ../widget

export widget, props

type
  ButtonState* = enum
    ## The `state` of a button (Kivy's strings).
    stateNormal = "normal"     ## not pressed
    stateDown = "down"         ## pressed

properties:
  type
    ButtonBehavior* = ref object of RootObj
      ## The button part of a widget. uix/behaviors/button.py ButtonBehavior
      stateEvent: nil ClockEvent   # __state_event: the delayed release
      touchTime: float             # __touch_time: when the touch went down
      state* {.prop.}: ButtonState = stateNormal  ## down while a touch presses it
      lastTouch* {.prop.}: nil MotionEvent = nil  ## the last touch that pressed or released it
      minStateTime* {.prop.}: float = 0.0  ## the shortest time, in seconds, the state stays down
      alwaysRelease* {.prop.}: bool = false  ## `release` also for a touch that ends off the widget
      press* {.event.}: proc ()    ## the button was pressed
      release* {.event.}: proc ()  ## the button was released

  proc cancelEvent(b: ButtonBehavior) =
    # ButtonBehavior.cancel_event
    let ev = b.stateEvent
    if ev != nil:
      ev.cancel()
      b.stateEvent = nil

  proc initButtonBehavior*(b: ButtonBehavior) =
    ## Sets up a new button part whose properties `initProps` has set: sets
    ## `minStateTime` from Config (graphics, minStateTime); a later
    ## `minStateTime=` overrides it, as a keyword argument does in Kivy.
    ## ButtonBehavior.__init__
    b.stateEvent = nil
    b.touchTime = 0
    b.minStateTime = Config.graphics.minStateTime
    discard b.bindState(proc (v: ButtonState) {.closure.} = b.cancelEvent())

  proc newButtonBehavior*(): ButtonBehavior =
    ## A button part with the default handlers, for a widget to own.
    result = ButtonBehavior(stateEvent: nil, touchTime: 0)
    result.initProps()
    result.initButtonBehavior()

  # ---------------------------------------------------------------- press and release

  proc doPress(b: ButtonBehavior) =
    # ButtonBehavior._do_press
    b.state = stateDown

  proc doRelease(b: ButtonBehavior) =
    # ButtonBehavior._do_release
    b.state = stateNormal

  proc grabbed*(b: ButtonBehavior; w: Widget; touch: MotionEvent): bool {.inline.} =
    ## Whether `touch` is grabbed by `w` and dispatched to it as the grabber:
    ## the touch that pressed the button, whose moves and end are the
    ## button's, not the children's.
    touch.grabCurrent == RootRef(w)

  proc touchDown*(b: ButtonBehavior; w: Widget; touch: sink MotionEvent): bool =
    ## A touch down that the widget's children did not take: on the widget,
    ## not a scroll and not seen before, it is grabbed and presses the
    ## button. The widget, as the key, claims the touch (Kivy's
    ## `touch.ud[self]`). ButtonBehavior.on_touch_down, after `super()`
    if touch.isMouseScrolling:
      return false
    if not w.collidePoint(touch.x, touch.y):
      return false
    if RootRef(w) in touch.claimedBy:
      return false
    touch.grab(w)
    touch.claimedBy.add RootRef(w)
    b.lastTouch = touch
    b.touchTime = time()
    b.doPress()
    discard b.dispatchPress()
    result = true

  proc touchMove*(b: ButtonBehavior; w: Widget; touch: MotionEvent): bool =
    ## A move that is not `grabbed` and that the children did not take: the
    ## button's if it pressed the touch. ButtonBehavior.on_touch_move, after
    ## `super()`
    RootRef(w) in touch.claimedBy

  proc touchUp*(b: ButtonBehavior; w: Widget; touch: sink MotionEvent): bool =
    ## The end of the `grabbed` touch: ungrabs it and releases the button,
    ## with `release` when the touch is still on the widget (or
    ## `alwaysRelease`), and `state` normal after `minStateTime`. Returns
    ## false (Kivy's None) for a release off the widget.
    ## ButtonBehavior.on_touch_up
    assert RootRef(w) in touch.claimedBy
    touch.ungrab(w)
    b.lastTouch = touch
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
    discard b.dispatchRelease()
    result = true

  proc triggerRelease(b: ButtonBehavior) =
    b.doRelease()
    discard b.dispatchRelease()

  proc triggerAction*(b: ButtonBehavior; duration = 0.1) =
    ## Presses the button without a touch: `press` now, then `release`
    ## after `duration` seconds (at once for 0).
    ## ButtonBehavior.trigger_action
    b.doPress()
    discard b.dispatchPress()
    if duration == 0:
      b.triggerRelease()
    else:
      discard Clock.scheduleOnce(proc (dt: float) {.closure.} = b.triggerRelease(), duration)
