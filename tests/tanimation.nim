# Tests animation (Animation, AnimationTransition) against kivy/tests/
# test_animations.py TestAnimation, plus the transition functions against
# their Kivy values and the events. The `animation` trace checks the order
# of the events against Kivy's.

import std/[assertions, math, os, syncio]
import nimkivy/[clock, config, animation]
import nimkivy/graphics/context_instructions
import nimkivy/uix/widget

proc sleepTicking(t: float) =
  # test_animations.py sleep(): ticks the real Clock until `t` has passed.
  let deadline = time() + t
  while time() < deadline:
    sleep(10)
    Clock.tick()

proc noAnimationsBeingPlayed(): bool =
  runningAnimations().len == 0

proc approx(a, b: float): bool = abs(a - b) <= 1e-6 * max(1.0, abs(b))

proc cleanup() =
  # The autouse fixture: Animation.cancel_all(None).
  cancelAll(nil)

Config.graphics.width = 800
Config.graphics.height = 600

block testStartAnimation:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], duration = 1)
  let w = newWidget()
  a.start(w)
  sleepTicking(1.5)
  assert approx(w.x, 100)
  assert noAnimationsBeingPlayed()

block testAnimationDuration0:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], duration = 0)
  let w = newWidget()
  a.start(w)
  sleepTicking(0.5)
  assert noAnimationsBeingPlayed()

block testCancelAll:
  cleanup()
  let a1 = newAnimation([xTo(HintedWidget, 100.0)])
  let a2 = newAnimation([yTo(HintedWidget, 100.0)])
  let w1 = newWidget()
  let w2 = newWidget()
  a1.start(w1)
  a1.start(w2)
  a2.start(w1)
  a2.start(w2)
  assert not noAnimationsBeingPlayed()
  cancelAll(nil)
  assert noAnimationsBeingPlayed()

block testCancelAll2:
  cleanup()
  let a1 = newAnimation([xTo(HintedWidget, 100.0)])
  let a2 = newAnimation([yTo(HintedWidget, 100.0)])
  let w1 = newWidget()
  let w2 = newWidget()
  a1.start(w1)
  a1.start(w2)
  a2.start(w1)
  a2.start(w2)
  assert not noAnimationsBeingPlayed()
  # Kivy cancels "x" and "z", a property Widget does not have.
  cancelAll(nil, xKey(HintedWidget), trackKey("HintedWidget.z"))
  assert not noAnimationsBeingPlayed()
  cancelAll(nil, yKey(HintedWidget))
  assert noAnimationsBeingPlayed()

block testStopAnimation:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], duration = 1)
  let w = newWidget()
  a.start(w)
  sleepTicking(0.5)
  a.stop(w)
  assert not approx(w.x, 100)
  assert not approx(w.x, 0)
  assert noAnimationsBeingPlayed()

block testStopAll:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], duration = 1)
  let w = newWidget()
  a.start(w)
  sleepTicking(0.5)
  stopAll(w)
  assert noAnimationsBeingPlayed()

block testStopAll2:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], duration = 1)
  let w = newWidget()
  a.start(w)
  sleepTicking(0.5)
  stopAll(w, xKey(HintedWidget))
  assert noAnimationsBeingPlayed()

block testDuration:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], duration = 1)
  assert a.duration == 1

block testTransition:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)], transition = outBounce)
  assert a.transition == outBounce

proc animated(a: Animation): seq[string] =
  # animated_properties: each track's property and end value.
  result = @[]
  for t in a.tracks: result.add $t

block testAnimatedProperties:
  cleanup()
  let a = newAnimation([xTo(HintedWidget, 100.0)])
  assert a.animated == @["HintedWidget.x -> 100.0"]
  assert a.tracks[0].key == xKey(HintedWidget)

block testAnimatedInstruction:
  # Adapted: Scale is out of scope (SCOPE.md), so a Translate's x.
  cleanup()
  let a = newAnimation([xTo(Translate, 100.0)], duration = 1)
  let instruction = newTranslate(3, 3)
  a.start(instruction)
  assert a.animated == @["Translate.x -> 100.0"]
  assert approx(instruction.x, 3)
  sleepTicking(1.5)
  assert approx(instruction.x, 100)
  assert noAnimationsBeingPlayed()

block events:
  # start, progress from 0 to 1, complete; stop dispatches complete, cancel
  # does not; a list property (pos) and a Color's alpha.
  cleanup()
  var log: seq[string] = @[]
  var progress: seq[float] = @[]
  let w = newWidget()
  let a = newAnimation([posTo(HintedWidget, (50.0, 60.0))], duration = 0.1)
  discard a.bindStart(proc (target: RootRef): bool {.closure.} =
    log.add "start"
    result = false)
  discard a.bindProgress(proc (target: RootRef; p: float): bool {.closure.} =
    progress.add p
    result = false)
  discard a.bindComplete(proc (target: RootRef): bool {.closure.} =
    assert target == RootRef(w)
    log.add "complete"
    result = false)
  a.start(w)
  assert a.havePropertiesToAnimate(w)
  sleepTicking(0.3)
  assert log == @["start", "complete"]
  assert progress[0] == 0 and progress[^1] == 1
  assert w.pos == (50.0, 60.0)
  assert not a.havePropertiesToAnimate(w)
  a.start(w)
  a.stop(w)
  a.start(w)
  a.cancel(w)
  assert log == @["start", "complete", "start", "complete", "start"]
  let c = newColor(1, 1, 1, 1)
  let fade = newAnimation([aTo(Color, 0.0)], duration = 0.1)
  fade.start(c)
  sleepTicking(0.3)
  assert c.a == 0
  assert noAnimationsBeingPlayed()

block stopPropertyKeepsOthers:
  cleanup()
  let w = newWidget()
  let a = newAnimation([xTo(HintedWidget, 100.0), yTo(HintedWidget, 100.0)])
  var completed = 0
  discard a.bindComplete(proc (target: RootRef): bool {.closure.} =
    inc completed
    result = false)
  a.start(w)
  a.stopProperty(w, xKey(HintedWidget))
  assert a.havePropertiesToAnimate(w) and completed == 0
  a.stopProperty(w, yKey(HintedWidget))
  assert completed == 1 and noAnimationsBeingPlayed()

block transitions:
  # Every AnimationTransition function at 0, .3, .5, .7 and 1, as Kivy
  # computes it (Nimony's sin, cos and pow may differ in the last bits).
  const expected: array[31, (string, array[5, float])] = [
    ("linear", [0.0, 0.3, 0.5, 0.7, 1.0]),
    ("in_quad", [0.0, 0.09, 0.25, 0.48999999999999994, 1.0]),
    ("out_quad", [0.0, 0.51, 0.75, 0.9099999999999999, 1.0]),
    ("in_out_quad", [0.0, 0.18, 0.5, 0.82, 1.0]),
    ("in_cubic", [0.0, 0.027, 0.125, 0.3429999999999999, 1.0]),
    ("out_cubic", [0.0, 0.657, 0.875, 0.973, 1.0]),
    ("in_out_cubic", [0.0, 0.108, 0.5, 0.8919999999999999, 1.0]),
    ("in_quart", [0.0, 0.0081, 0.0625, 0.24009999999999992, 1.0]),
    ("out_quart", [-0.0, 0.7599, 0.9375, 0.9919, 1.0]),
    ("in_out_quart", [0.0, 0.0648, 0.5, 0.9351999999999999, 1.0]),
    ("in_quint", [0.0, 0.00243, 0.03125, 0.16806999999999994, 1.0]),
    ("out_quint", [0.0, 0.8319300000000001, 0.96875, 0.99757, 1.0]),
    ("in_out_quint", [0.0, 0.03888, 0.5, 0.96112, 1.0]),
    ("in_sine", [0.0, 0.1089934758116321, 0.2928932188134524, 0.5460095002604533,
      0.9999999999999999]),
    ("out_sine", [0.0, 0.45399049973954675, 0.7071067811865475, 0.8910065241883678, 1.0]),
    ("in_out_sine", [-0.0, 0.20610737385376343, 0.49999999999999994, 0.7938926261462365,
      1.0]),
    ("in_expo", [0.0, 0.0078125, 0.03125, 0.12499999999999996, 1.0]),
    ("out_expo", [0.0, 0.875, 0.96875, 0.9921875, 1.0]),
    ("in_out_expo", [0.0, 0.03125, 0.5, 0.96875, 1.0]),
    ("in_circ", [-0.0, 0.04606079858305434, 0.1339745962155614, 0.285857157145715, 1.0]),
    ("out_circ", [0.0, 0.714142842854285, 0.8660254037844386, 0.9539392014169457, 1.0]),
    ("in_out_circ", [-0.0, 0.09999999999999998, 0.5, 0.8999999999999999, 1.0]),
    ("in_elastic", [-0.00048828124999999875, -0.0039062499999999918, -0.015625000000000045,
      0.12499999999999996, 1.0]),
    ("out_elastic", [0.0, 0.875, 1.015625, 1.00390625, 1.0]),
    ("in_out_elastic", [8.478914925143018e-05, 0.023938888847468056, 0.5, 0.9760611111525319,
      1.0]),
    ("in_back", [-0.0, -0.08019954000000001, -0.08769750000000004, 0.09286773999999981,
      0.9999999999999998]),
    ("out_back", [2.220446049250313e-16, 0.9071322600000002, 1.0876975, 1.08019954, 1.0]),
    ("in_out_back", [-0.0, -0.07883348399999998, 0.5, 1.078833484, 1.0]),
    ("in_bounce", [0.0, 0.06937499999999996, 0.234375, 0.31937499999999985, 1.0]),
    ("out_bounce", [0.0, 0.6806249999999999, 0.765625, 0.930625, 1.0]),
    ("in_out_bounce", [0.0, 0.045000000000000095, 0.5, 0.9550000000000001, 1.0])]
  # The same functions, in the same order (Kivy's names above).
  let funcs: array[31, AnimationTransitionFunc] = [linear, inQuad, outQuad, inOutQuad,
    inCubic, outCubic, inOutCubic, inQuart, outQuart, inOutQuart, inQuint, outQuint,
    inOutQuint, inSine, outSine, inOutSine, inExpo, outExpo, inOutExpo, inCirc, outCirc,
    inOutCirc, inElastic, outElastic, inOutElastic, inBack, outBack, inOutBack, inBounce,
    outBounce, inOutBounce]
  const at = [0.0, 0.3, 0.5, 0.7, 1.0]
  for k in 0 ..< expected.len:
    let (name, values) = expected[k]
    let f = funcs[k]
    for i in 0 ..< at.len:
      assert abs(f(at[i]) - values[i]) <= 1e-12, name

echo "tanimation: all tests passed"
