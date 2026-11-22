## Animation: Kivy's `kivy/animation.py` (Animation and AnimationTransition).
##
## An Animation moves properties of a target from their values when it
## starts to the values it was given, over `duration` seconds, through a
## transition (easing) function. What it moves are typed tracks:
##
## .. code-block:: nim
##   newAnimation([opacityTo(Widget, 1.0)], duration = 0.2).start(w)
##   newAnimation([xTo(HintedWidget, 100.0), yTo(HintedWidget, 50.0)]).start(w)
##   newAnimation([aTo(Color, 0.0)], duration = 0.1).start(color)
##
## The `properties:` block generates `propTo(Owner, value)` and
## `propKey(Owner)` for every settable property of a numeric type (`props`);
## `Owner` is the type that declares the property. This module adds the
## tracks of the Color (`r`, `g`, `b`, `a`, `rgb`, `rgba`) and Translate
## (`x`, `y`, `xy`) instructions. Each frame (a Clock interval of `step`
## seconds; 0 is every frame) the animation writes the values, then
## dispatches `progress`; at the end it dispatches `complete`.
##
## `start` first stops the animation on that target, so restarting a running
## Animation dispatches its `complete`. Two Animation objects on the same
## property both run, and the one whose Clock event comes later in a frame
## writes last.
##
## Out of scope (SCOPE.md): Sequence (`+`), Parallel (`&`), `repeat`, and
## animating dicts or non-numeric properties.

import std/math
import ./[props, clock]
import graphics/context_instructions

export props

type
  AnimationTransitionFunc* = proc (progress: float): float {.nimcall.}
    ## An easing function: progress 0 .. 1 to the share of the way done.

  AnimatedTarget = ref object
    # One entry of Kivy's `_widgets` dict: the target, its running tracks
    # (with their start values), and the time since the first update (None
    # until then: `hasTime` false).
    target: RootRef
    tracks: seq[Track]
    time: float
    hasTime: bool

# ------------------------------------------------------------------ transitions
# animation.py AnimationTransition: Clutter's easing functions, line for line.

proc linear*(progress: float): float =
  ## AnimationTransition.linear
  progress

proc inQuad*(progress: float): float =
  ## AnimationTransition.in_quad
  progress * progress

proc outQuad*(progress: float): float =
  ## AnimationTransition.out_quad
  -1.0 * progress * (progress - 2.0)

proc inOutQuad*(progress: float): float =
  ## AnimationTransition.in_out_quad
  var p = progress * 2
  if p < 1:
    return 0.5 * p * p
  p -= 1.0
  result = -0.5 * (p * (p - 2.0) - 1.0)

proc inCubic*(progress: float): float =
  ## AnimationTransition.in_cubic
  progress * progress * progress

proc outCubic*(progress: float): float =
  ## AnimationTransition.out_cubic
  let p = progress - 1.0
  result = p * p * p + 1.0

proc inOutCubic*(progress: float): float =
  ## AnimationTransition.in_out_cubic
  var p = progress * 2
  if p < 1:
    return 0.5 * p * p * p
  p -= 2
  result = 0.5 * (p * p * p + 2.0)

proc inQuart*(progress: float): float =
  ## AnimationTransition.in_quart
  progress * progress * progress * progress

proc outQuart*(progress: float): float =
  ## AnimationTransition.out_quart
  let p = progress - 1.0
  result = -1.0 * (p * p * p * p - 1.0)

proc inOutQuart*(progress: float): float =
  ## AnimationTransition.in_out_quart
  var p = progress * 2
  if p < 1:
    return 0.5 * p * p * p * p
  p -= 2
  result = -0.5 * (p * p * p * p - 2.0)

proc inQuint*(progress: float): float =
  ## AnimationTransition.in_quint
  progress * progress * progress * progress * progress

proc outQuint*(progress: float): float =
  ## AnimationTransition.out_quint
  let p = progress - 1.0
  result = p * p * p * p * p + 1.0

proc inOutQuint*(progress: float): float =
  ## AnimationTransition.in_out_quint
  var p = progress * 2
  if p < 1:
    return 0.5 * p * p * p * p * p
  p -= 2.0
  result = 0.5 * (p * p * p * p * p + 2.0)

proc inSine*(progress: float): float =
  ## AnimationTransition.in_sine
  -1.0 * cos(progress * (PI / 2.0)) + 1.0

proc outSine*(progress: float): float =
  ## AnimationTransition.out_sine
  sin(progress * (PI / 2.0))

proc inOutSine*(progress: float): float =
  ## AnimationTransition.in_out_sine
  -0.5 * (cos(PI * progress) - 1.0)

proc inExpo*(progress: float): float =
  ## AnimationTransition.in_expo
  if progress == 0:
    return 0.0
  result = pow(2.0, 10 * (progress - 1.0))

proc outExpo*(progress: float): float =
  ## AnimationTransition.out_expo
  if progress == 1.0:
    return 1.0
  result = -pow(2.0, -10 * progress) + 1.0

proc inOutExpo*(progress: float): float =
  ## AnimationTransition.in_out_expo
  if progress == 0:
    return 0.0
  if progress == 1.0:
    return 1.0
  var p = progress * 2
  if p < 1:
    return 0.5 * pow(2.0, 10 * (p - 1.0))
  p -= 1.0
  result = 0.5 * (-pow(2.0, -10 * p) + 2.0)

proc inCirc*(progress: float): float =
  ## AnimationTransition.in_circ
  -1.0 * (sqrt(1.0 - progress * progress) - 1.0)

proc outCirc*(progress: float): float =
  ## AnimationTransition.out_circ
  let p = progress - 1.0
  result = sqrt(1.0 - p * p)

proc inOutCirc*(progress: float): float =
  ## AnimationTransition.in_out_circ
  var p = progress * 2
  if p < 1:
    return -0.5 * (sqrt(1.0 - p * p) - 1.0)
  p -= 2.0
  result = 0.5 * (sqrt(1.0 - p * p) + 1.0)

proc inElastic*(progress: float): float =
  ## AnimationTransition.in_elastic
  let p = 0.3
  let s = p / 4.0
  var q = progress
  if q == 1:
    return 1.0
  q -= 1.0
  result = -(pow(2.0, 10 * q) * sin((q - s) * (2 * PI) / p))

proc outElastic*(progress: float): float =
  ## AnimationTransition.out_elastic
  let p = 0.3
  let s = p / 4.0
  let q = progress
  if q == 1:
    return 1.0
  result = pow(2.0, -10 * q) * sin((q - s) * (2 * PI) / p) + 1.0

proc inOutElastic*(progress: float): float =
  ## AnimationTransition.in_out_elastic
  let p = 0.3 * 1.5
  let s = p / 4.0
  var q = progress * 2
  if q == 2:
    return 1.0
  if q < 1:
    q -= 1.0
    result = -0.5 * (pow(2.0, 10 * q) * sin((q - s) * (2.0 * PI) / p))
  else:
    q -= 1.0
    result = pow(2.0, -10 * q) * sin((q - s) * (2.0 * PI) / p) * 0.5 + 1.0

proc inBack*(progress: float): float =
  ## AnimationTransition.in_back
  progress * progress * ((1.70158 + 1.0) * progress - 1.70158)

proc outBack*(progress: float): float =
  ## AnimationTransition.out_back
  let p = progress - 1.0
  result = p * p * ((1.70158 + 1) * p + 1.70158) + 1.0

proc inOutBack*(progress: float): float =
  ## AnimationTransition.in_out_back
  var p = progress * 2.0
  let s = 1.70158 * 1.525
  if p < 1:
    return 0.5 * (p * p * ((s + 1.0) * p - s))
  p -= 2.0
  result = 0.5 * (p * p * ((s + 1.0) * p + s) + 2.0)

proc outBounceInternal(t, d: float): float =
  # AnimationTransition._out_bounce_internal
  var p = t / d
  if p < (1.0 / 2.75):
    result = 7.5625 * p * p
  elif p < (2.0 / 2.75):
    p -= (1.5 / 2.75)
    result = 7.5625 * p * p + 0.75
  elif p < (2.5 / 2.75):
    p -= (2.25 / 2.75)
    result = 7.5625 * p * p + 0.9375
  else:
    p -= (2.625 / 2.75)
    result = 7.5625 * p * p + 0.984375

proc inBounceInternal(t, d: float): float =
  # AnimationTransition._in_bounce_internal
  1.0 - outBounceInternal(d - t, d)

proc inBounce*(progress: float): float =
  ## AnimationTransition.in_bounce
  inBounceInternal(progress, 1.0)

proc outBounce*(progress: float): float =
  ## AnimationTransition.out_bounce
  outBounceInternal(progress, 1.0)

proc inOutBounce*(progress: float): float =
  ## AnimationTransition.in_out_bounce
  let p = progress * 2.0
  if p < 1.0:
    return inBounceInternal(p, 1.0) * 0.5
  result = outBounceInternal(p - 1.0, 1.0) * 0.5 + 0.5


# ------------------------------------------------------------------ instruction tracks
# Kivy's setattr reaches any attribute of an instruction; here each one an
# Animation can move has a hand-written track.

# GAP: of the instructions only Color (r, g, b, a, rgb, rgba) and Translate
# (x, y, xy) can be animated, where Kivy reaches any attribute of any
# instruction, because Nim has no getattr/setattr by name for plain objects
type
  ColorPart = enum
    cpR = "r", cpG = "g", cpB = "b", cpA = "a", cpRgb = "rgb", cpRgba = "rgba"

  ColorTrack = ref object of Track
    part: ColorPart
    target: nil Color
    a, b: array[4, float]   # the channels; `part` says which are moved

  TranslatePart = enum
    tpX = "x", tpY = "y", tpXy = "xy"

  TranslateTrack = ref object of Track
    part: TranslatePart
    target: nil Translate
    a, b: (float, float)

proc colorTrack(part: ColorPart; v: array[4, float]): Track =
  ColorTrack(key: trackKey("Color." & $part), part: part, target: nil, a: v, b: v)

method capture(t: ColorTrack; target: sink RootRef): Track =
  if target of Color:
    let c = Color(target)
    result = ColorTrack(key: t.key, part: t.part, target: c, a: c.rgba, b: t.b)
  else:
    result = quitWrongTarget("Color." & $t.part)

method advance(t: ColorTrack; progress: float) =
  let c = t.target
  if c != nil:
    let v = lerp(t.a, t.b, progress)
    case t.part
    of cpR: c.r = v[0]
    of cpG: c.g = v[1]
    of cpB: c.b = v[2]
    of cpA: c.a = v[3]
    of cpRgb: c.rgb = [v[0], v[1], v[2]]
    of cpRgba: c.rgba = v

method `$`(t: ColorTrack): string =
  let v = t.b
  case t.part
  of cpR: result = "Color.r -> " & $v[0]
  of cpG: result = "Color.g -> " & $v[1]
  of cpB: result = "Color.b -> " & $v[2]
  of cpA: result = "Color.a -> " & $v[3]
  of cpRgb: result = "Color.rgb -> " & $[v[0], v[1], v[2]]
  of cpRgba: result = "Color.rgba -> " & $v

proc rTo*(t: typedesc[Color]; v: float): Track =
  ## Moves a Color's red to `v`.
  colorTrack(cpR, [v, 0, 0, 0])
proc gTo*(t: typedesc[Color]; v: float): Track =
  ## Moves a Color's green to `v`.
  colorTrack(cpG, [0.0, v, 0, 0])
proc bTo*(t: typedesc[Color]; v: float): Track =
  ## Moves a Color's blue to `v`.
  colorTrack(cpB, [0.0, 0, v, 0])
proc aTo*(t: typedesc[Color]; v: float): Track =
  ## Moves a Color's alpha to `v`.
  colorTrack(cpA, [0.0, 0, 0, v])
proc rgbTo*(t: typedesc[Color]; v: array[3, float]): Track =
  ## Moves a Color's red, green and blue to `v`.
  colorTrack(cpRgb, [v[0], v[1], v[2], 0])
proc rgbaTo*(t: typedesc[Color]; v: array[4, float]): Track =
  ## Moves a Color's four channels to `v`.
  colorTrack(cpRgba, v)

proc rKey*(t: typedesc[Color]): TrackKey = trackKey("Color.r")
  ## The key of a Color's red.
proc gKey*(t: typedesc[Color]): TrackKey = trackKey("Color.g")
  ## The key of a Color's green.
proc bKey*(t: typedesc[Color]): TrackKey = trackKey("Color.b")
  ## The key of a Color's blue.
proc aKey*(t: typedesc[Color]): TrackKey = trackKey("Color.a")
  ## The key of a Color's alpha.
proc rgbKey*(t: typedesc[Color]): TrackKey = trackKey("Color.rgb")
  ## The key of a Color's red, green and blue.
proc rgbaKey*(t: typedesc[Color]): TrackKey = trackKey("Color.rgba")
  ## The key of a Color's four channels.

proc translateTrack(part: TranslatePart; v: (float, float)): Track =
  TranslateTrack(key: trackKey("Translate." & $part), part: part, target: nil, a: v, b: v)

method capture(t: TranslateTrack; target: sink RootRef): Track =
  if target of Translate:
    let tr = Translate(target)
    result = TranslateTrack(key: t.key, part: t.part, target: tr, a: tr.xy, b: t.b)
  else:
    result = quitWrongTarget("Translate." & $t.part)

method advance(t: TranslateTrack; progress: float) =
  let tr = t.target
  if tr != nil:
    let v = lerp(t.a, t.b, progress)
    case t.part
    of tpX: tr.x = v[0]
    of tpY: tr.y = v[1]
    of tpXy: tr.xy = v

method `$`(t: TranslateTrack): string =
  case t.part
  of tpX: result = "Translate.x -> " & $t.b[0]
  of tpY: result = "Translate.y -> " & $t.b[1]
  of tpXy: result = "Translate.xy -> " & $t.b

proc xTo*(t: typedesc[Translate]; v: float): Track =
  ## Moves a Translate's x to `v`.
  translateTrack(tpX, (v, 0.0))
proc yTo*(t: typedesc[Translate]; v: float): Track =
  ## Moves a Translate's y to `v`.
  translateTrack(tpY, (0.0, v))
proc xyTo*(t: typedesc[Translate]; v: (float, float)): Track =
  ## Moves a Translate's x and y to `v`.
  translateTrack(tpXy, v)

proc xKey*(t: typedesc[Translate]): TrackKey = trackKey("Translate.x")
  ## The key of a Translate's x.
proc yKey*(t: typedesc[Translate]): TrackKey = trackKey("Translate.y")
  ## The key of a Translate's y.
proc xyKey*(t: typedesc[Translate]): TrackKey = trackKey("Translate.xy")
  ## The key of a Translate's x and y.

# ------------------------------------------------------------------ Animation

properties:
  type
    Animation* = ref object of RootObj
      ## An animation definition, which can run on several targets at once.
      ## animation.py Animation
      duration: float
      transition: AnimationTransitionFunc
      step: float
      tracks: seq[Track]
      widgets: seq[AnimatedTarget]   # Kivy's `_widgets`, in insertion order
      clockInstalled: bool
      updateEv: nil ClockEvent
      start* {.event.}: proc (target: RootRef)
        ## the animation started on `target`
      progress* {.event.}: proc (target: RootRef; progress: float)
        ## a step on `target`; `progress` 0 .. 1 before the transition
      complete* {.event.}: proc (target: RootRef)
        ## the animation ended or was stopped on `target` (not cancelled)

# GAP: the procs that hold a `seq[Animation]` (the running animations) are in
# a second block, because a `seq` of a type declared in a `properties:` block
# crashes shoggoth in a proc of the same block (planetis-m/nimony-bugs-llms#337)
properties:
  type
    AnimationRegistry = ref object of RootObj
      # Kivy's class attribute `Animation._instances`: the running animations.
      instances: seq[Animation]

  let registry = AnimationRegistry(instances: @[])

  proc newAnimation*(tracks: openArray[Track]; duration = 1.0;
      transition: AnimationTransitionFunc = linear; step = 0.0): Animation =
    ## `Animation(prop=value, ..., d=duration, t=transition, s=step)`: the
    ## tracks in the order given. animation.py Animation.__init__
    var all: seq[Track] = @[]
    for t in tracks: all.add t
    result = Animation(duration: duration, transition: transition, step: step,
      tracks: all, widgets: @[], clockInstalled: false, updateEv: nil)
    result.initProps()

  proc duration*(a: Animation): float {.inline.} =
    ## The duration in seconds (default 1). Animation.duration
    a.duration

  proc transition*(a: Animation): AnimationTransitionFunc {.inline.} =
    ## The transition function. Animation.transition
    a.transition

  proc tracks*(a: Animation): seq[Track] {.inline.} =
    ## The tracks: each property and its end value.
    ## Animation.animated_properties
    a.tracks

  proc runningAnimations*(): seq[Animation] =
    ## The animations running on at least one target (Kivy's
    ## `Animation._instances`).
    registry.instances

  proc find(a: Animation; target: RootRef): int =
    # The index of target's entry in `_widgets`, or -1 (Kivy keys it by uid).
    result = -1
    for i in 0 ..< a.widgets.len:
      if a.widgets[i].target == target:
        return i

  proc pop(a: Animation; target: RootRef): bool =
    # `self._widgets.pop(widget.uid, None)`: whether there was an entry.
    let i = a.find(target)
    result = i >= 0
    if result:
      a.widgets.delete(i)

  proc register(a: sink Animation) =
    # Animation._register: `_instances.add(self)`.
    if a notin registry.instances:
      registry.instances.add a

  proc unregister(a: Animation) =
    # Animation._unregister: `_instances.discard(self)`.
    let i = registry.instances.find(a)
    if i >= 0:
      registry.instances.delete(i)

  proc clockUninstall(a: Animation) =
    # Animation._clock_uninstall: only once no target is left.
    if a.widgets.len > 0 or not a.clockInstalled:
      return
    a.clockInstalled = false
    let ev = a.updateEv
    if ev != nil:
      ev.cancel()
      a.updateEv = nil

  proc cancel*(a: Animation; target: RootRef) =
    ## Stops the animation on `target` without dispatching `complete`.
    ## Animation.cancel
    discard a.pop(target)
    a.clockUninstall()
    if a.widgets.len == 0:
      a.unregister()

  proc stop*(a: Animation; target: RootRef) =
    ## Stops the animation on `target`, dispatching `complete` if it was
    ## running there. Animation.stop
    if a.pop(target):
      discard a.dispatchComplete(target)
    a.cancel(target)

  proc removeTrack(a: Animation; target: RootRef; key: TrackKey): bool =
    # Takes `key` out of target's tracks; whether none is left (false when
    # the animation does not run on `target`).
    let i = a.find(target)
    if i < 0:
      return false
    let entry = a.widgets[i]
    var k = 0
    while k < entry.tracks.len:
      if entry.tracks[k].key == key: entry.tracks.delete(k)
      else: inc k
    result = entry.tracks.len == 0

  proc stopProperty*(a: Animation; target: RootRef; key: TrackKey) =
    ## Stops animating the property `key` (`propKey(Owner)`) on `target`;
    ## with no property left, stops the animation there (`complete`).
    ## Animation.stop_property
    if a.removeTrack(target, key):
      a.stop(target)

  proc cancelProperty*(a: Animation; target: RootRef; key: TrackKey) =
    ## Stops animating the property `key` on `target`; with no property
    ## left, cancels the animation there (no `complete`).
    ## Animation.cancel_property
    if a.removeTrack(target, key):
      a.cancel(target)

  proc havePropertiesToAnimate*(a: Animation; target: RootRef): bool =
    ## Whether `target` still has properties to animate.
    ## Animation.have_properties_to_animate
    let i = a.find(target)
    result = i >= 0 and a.widgets[i].tracks.len > 0

  proc update(a: Animation; dt: float) =
    # Animation._update: one step on every target.
    let targets = a.widgets
    for entry in targets:
      # Kivy iterates over a copy of the keys; a target stopped meanwhile is
      # skipped (Kivy would raise a KeyError).
      if a.find(entry.target) >= 0:
        if not entry.hasTime:
          entry.hasTime = true
          entry.time = 0.0
        else:
          entry.time += dt
        var progress = 1.0
        if a.duration != 0:
          progress = min(1.0, entry.time / a.duration)
        let t = a.transition(progress)
        let tracks = entry.tracks
        for track in tracks:
          track.advance(t)
        discard a.dispatchProgress(entry.target, progress)
        if progress >= 1.0:
          a.stop(entry.target)

  proc clockInstall(a: Animation) =
    # Animation._clock_install
    if a.clockInstalled:
      return
    a.updateEv = Clock.scheduleInterval(proc (dt: float) {.closure.} = a.update(dt), a.step)
    a.clockInstalled = true

  proc initialize(a: Animation; target: sink RootRef) =
    # Animation._initialize: the current values become the start values.
    var running: seq[Track] = @[]
    let tracks = a.tracks
    for t in tracks:
      running.add t.capture(target)
    let i = a.find(target)
    let entry = AnimatedTarget(target: target, tracks: running, time: 0, hasTime: false)
    # A target started again keeps its place (Kivy's `_widgets` dict).
    if i >= 0: a.widgets[i] = entry
    else: a.widgets.add entry
    a.clockInstall()

  proc start*(a: Animation; target: sink RootRef) =
    ## Starts the animation on `target` (an object with the tracks'
    ## properties), stopping it there first. Animation.start
    a.stop(target)
    a.initialize(target)
    a.register()
    discard a.dispatchStart(target)

  proc stopAll*(target: RootRef; keys: varargs[TrackKey]) =
    ## Stops every animation on `target`, or only the given properties.
    ## Animation.stop_all
    let snapshot = registry.instances
    if keys.len > 0:
      for a in snapshot:
        for k in keys:
          a.stopProperty(target, k)
    else:
      for a in snapshot:
        a.stop(target)

  proc cancelAll*(target: nil RootRef; keys: varargs[TrackKey]) =
    ## Cancels every animation on `target`, or only the given properties; a
    ## nil target means every animated target. Animation.cancel_all
    if target == nil:
      if keys.len > 0:
        let snapshot = registry.instances
        for a in snapshot:
          let entries = a.widgets
          for entry in entries:
            for k in keys:
              a.cancelProperty(entry.target, k)
      else:
        let all = registry.instances
        for a in all:
          a.widgets = @[]
          a.clockUninstall()
        registry.instances = @[]
      return
    let snapshot = registry.instances
    if keys.len > 0:
      for a in snapshot:
        for k in keys:
          a.cancelProperty(target, k)
    else:
      for a in snapshot:
        a.cancel(target)
