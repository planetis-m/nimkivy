## Animation: Kivy's `kivy/animation.py` (Animation and AnimationTransition).
##
## An Animation moves numeric properties (or lists of numbers) of a target
## from their values when it starts to the values it was given, over
## `duration` seconds, through a transition (easing) function. The target is
## an EventDispatcher (a widget, a transition), whose properties are found by
## name, or a Color or Translate instruction. Each frame (a Clock interval of
## `step` seconds; 0 is every frame) it writes the properties, then
## dispatches `on_progress`; at the end it dispatches `on_complete`.
##
## `start` first stops the animation on that target, so restarting a running
## Animation fires its `on_complete`. Two Animation objects on the same
## property both run, and the one whose Clock event comes later in a frame
## writes last.
##
## Out of scope (SCOPE.md): Sequence (`+`), Parallel (`&`), `repeat`, and
## animating dicts or non-numeric properties.

import std/[math, syncio]
import ./[properties, clock]
import graphics/[instructions, context_instructions]
import uix/widget

type
  AnimationTransitionFunc* = proc (progress: float): float {.nimcall.}
    ## An easing function: progress 0 .. 1 to the share of the way done.

  AnimatedTarget = ref object
    # One entry of Kivy's `_widgets` dict: the target, each property with its
    # start and end values, and the time since the first update (None until
    # then: `hasTime` false).
    target: RootRef
    properties: seq[(string, Value, Value)]
    time: float
    hasTime: bool

  Animation* = ref object of EventDispatcher
    ## An animation definition, which can run on several targets at once.
    ## animation.py Animation
    duration: float
    transition: AnimationTransitionFunc
    step: float
    animatedProperties: seq[(string, Value)]
    widgets: seq[AnimatedTarget]     # Kivy's `_widgets`, in insertion order
    clockInstalled: bool
    updateEv: nil ClockEvent

  AnimationRegistry = ref object
    # Kivy's class attribute `Animation._instances`: the running animations.
    instances: seq[Animation]

let registry = AnimationRegistry(instances: @[])

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

proc transitionByName*(name: string): AnimationTransitionFunc =
  ## The AnimationTransition function called `name` in Kivy (`"out_bounce"`);
  ## an unknown name stops the program, as Kivy's `getattr` raises.
  case name
  of "linear": linear
  of "in_quad": inQuad
  of "out_quad": outQuad
  of "in_out_quad": inOutQuad
  of "in_cubic": inCubic
  of "out_cubic": outCubic
  of "in_out_cubic": inOutCubic
  of "in_quart": inQuart
  of "out_quart": outQuart
  of "in_out_quart": inOutQuart
  of "in_quint": inQuint
  of "out_quint": outQuint
  of "in_out_quint": inOutQuint
  of "in_sine": inSine
  of "out_sine": outSine
  of "in_out_sine": inOutSine
  of "in_expo": inExpo
  of "out_expo": outExpo
  of "in_out_expo": inOutExpo
  of "in_circ": inCirc
  of "out_circ": outCirc
  of "in_out_circ": inOutCirc
  of "in_elastic": inElastic
  of "out_elastic": outElastic
  of "in_out_elastic": inOutElastic
  of "in_back": inBack
  of "out_back": outBack
  of "in_out_back": inOutBack
  of "in_bounce": inBounce
  of "out_bounce": outBounce
  of "in_out_bounce": inOutBounce
  else: quit "AttributeError: type object 'AnimationTransition' has no attribute '" &
    name & "'"

# ------------------------------------------------------------------ targets

proc floats(v: Value): array[4, float] =
  let f = v.toFloats
  result = [f[0], f[1], f[2], f[3]]

const widgetProperties = ["x", "y", "width", "height", "pos", "size", "right", "top",
  "center_x", "center_y", "center", "opacity"]
  # Widget's typed properties that an Animation reaches by name (phase 1
  # until step 5 gives Animation typed tracks).

proc pair(v: Value): (float, float) {.inline.} =
  (v.items[0].num, v.items[1].num)

proc getAttr(target: RootRef; name: string): Value =
  # Python's getattr(widget, key): a property of a dispatcher, or an
  # attribute of an instruction.
  # GAP: of the instructions only Color (r, g, b, a, rgb, rgba) and
  # Translate (x, y, xy) can be animated, where Kivy reaches any attribute
  # of any instruction, because Nim has no getattr/setattr by name
  if target of Widget and name in widgetProperties:
    let w = Widget(target)
    case name
    of "x": result = toValue(w.x)
    of "y": result = toValue(w.y)
    of "width": result = toValue(w.width)
    of "height": result = toValue(w.height)
    of "pos": result = toValue([w.pos[0], w.pos[1]])
    of "size": result = toValue([w.size[0], w.size[1]])
    of "right": result = toValue(w.right)
    of "top": result = toValue(w.top)
    of "center_x": result = toValue(w.centerX)
    of "center_y": result = toValue(w.centerY)
    of "center": result = toValue([w.center[0], w.center[1]])
    else: result = toValue(w.opacity)
  elif target of EventDispatcher:
    result = EventDispatcher(target).getProperty(name)
  elif target of Color:
    let c = Color(target)
    case name
    of "r": result = toValue(c.r)
    of "g": result = toValue(c.g)
    of "b": result = toValue(c.b)
    of "a": result = toValue(c.a)
    of "rgb": result = toValue(c.rgb)
    of "rgba": result = toValue(c.rgba)
    else: quit "AttributeError: Color has no attribute '" & name & "'"
  elif target of Translate:
    let t = Translate(target)
    case name
    of "x": result = toValue(t.x)
    of "y": result = toValue(t.y)
    of "xy": result = toValue([t.x, t.y])
    else: quit "AttributeError: Translate has no attribute '" & name & "'"
  else:
    quit "AttributeError: the target has no attribute '" & name & "'"

proc setAttr(target: RootRef; name: string; v: Value) =
  # Python's setattr(widget, key, value).
  if target of Widget and name in widgetProperties:
    let w = Widget(target)
    case name
    of "x": w.x = v.num
    of "y": w.y = v.num
    of "width": w.width = v.num
    of "height": w.height = v.num
    of "pos": w.pos = pair(v)
    of "size": w.size = pair(v)
    of "right": w.right = v.num
    of "top": w.top = v.num
    of "center_x": w.centerX = v.num
    of "center_y": w.centerY = v.num
    of "center": w.center = pair(v)
    else: w.opacity = v.num
  elif target of EventDispatcher:
    EventDispatcher(target).setProperty(name, v)
  elif target of Color:
    let c = Color(target)
    case name
    of "r": c.r = v.num
    of "g": c.g = v.num
    of "b": c.b = v.num
    of "a": c.a = v.num
    of "rgb":
      let f = v.toFloats
      c.rgb = [f[0], f[1], f[2]]
    of "rgba": c.rgba = floats(v)
    else: quit "AttributeError: Color has no attribute '" & name & "'"
  elif target of Translate:
    let t = Translate(target)
    case name
    of "x": t.x = v.num
    of "y": t.y = v.num
    of "xy": t.xy = pair(v)
    else: quit "AttributeError: Translate has no attribute '" & name & "'"
  else:
    quit "AttributeError: the target has no attribute '" & name & "'"

# ------------------------------------------------------------------ class

proc noHandler(d: EventDispatcher; args: seq[Value]): bool =
  # The default handlers on_start, on_progress and on_complete do nothing.
  false

let AnimationClass* = newDispatcherClass("Animation", EventDispatcherClass)
  ## The class of `Animation`, with the events `on_start(widget)`,
  ## `on_progress(widget, progress)` and `on_complete(widget)`.
AnimationClass.addEvent("on_start", noHandler)
AnimationClass.addEvent("on_progress", noHandler)
AnimationClass.addEvent("on_complete", noHandler)

proc newAnimation*(properties: openArray[(string, Value)]; duration = 1.0;
    transition: AnimationTransitionFunc = linear; step = 0.0): Animation =
  ## `Animation(prop=value, ..., d=duration, t=transition, s=step)`: the
  ## properties in the order given; a value is a number or a list of
  ## numbers. animation.py Animation.__init__
  var props: seq[(string, Value)] = @[]
  for p in properties: props.add p
  result = Animation(cls: AnimationClass, duration: duration, transition: transition,
    step: step, animatedProperties: props, widgets: @[], clockInstalled: false,
    updateEv: nil)
  result.initEventDispatcher()

proc newAnimation*(properties: openArray[(string, float)]; duration = 1.0;
    transition: AnimationTransitionFunc = linear; step = 0.0): Animation =
  ## `Animation(prop=number, ...)`.
  var props: seq[(string, Value)] = @[]
  for (name, v) in properties: props.add (name, toValue(v))
  result = newAnimation(props, duration, transition, step)

proc newAnimation*(properties: openArray[(string, float)]; duration = 1.0;
    transition: string; step = 0.0): Animation =
  ## `Animation(prop=number, ..., t="out_bounce")`: the transition by its
  ## Kivy name.
  result = newAnimation(properties, duration, transitionByName(transition), step)

proc duration*(a: Animation): float {.inline.} =
  ## The duration in seconds (default 1). Animation.duration
  a.duration

proc transition*(a: Animation): AnimationTransitionFunc {.inline.} =
  ## The transition function. Animation.transition
  a.transition

proc animatedProperties*(a: Animation): seq[(string, Value)] {.inline.} =
  ## The properties and their end values. Animation.animated_properties
  a.animatedProperties

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

proc register(a: Animation) =
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
  ## Stops the animation on `target` without dispatching `on_complete`.
  ## Animation.cancel
  discard a.pop(target)
  a.clockUninstall()
  if a.widgets.len == 0:
    a.unregister()

proc stop*(a: Animation; target: RootRef) =
  ## Stops the animation on `target`, dispatching `on_complete` if it was
  ## running there. Animation.stop
  if a.pop(target):
    discard a.dispatch("on_complete", toValue(target))
  a.cancel(target)

proc stopProperty*(a: Animation; target: RootRef; prop: string) =
  ## Stops animating `prop` on `target`; with no property left, stops the
  ## animation there (`on_complete`). Animation.stop_property
  let i = a.find(target)
  if i < 0:
    return
  let entry = a.widgets[i]
  var k = 0
  while k < entry.properties.len:
    if entry.properties[k][0] == prop: entry.properties.delete(k)
    else: inc k
  if entry.properties.len == 0:
    a.stop(target)

proc cancelProperty*(a: Animation; target: RootRef; prop: string) =
  ## Stops animating `prop` on `target`; with no property left, cancels the
  ## animation there (no `on_complete`). Animation.cancel_property
  let i = a.find(target)
  if i < 0:
    return
  let entry = a.widgets[i]
  var k = 0
  while k < entry.properties.len:
    if entry.properties[k][0] == prop: entry.properties.delete(k)
    else: inc k
  if entry.properties.len == 0:
    a.cancel(target)

proc havePropertiesToAnimate*(a: Animation; target: RootRef): bool =
  ## Whether `target` still has properties to animate.
  ## Animation.have_properties_to_animate
  let i = a.find(target)
  result = i >= 0 and a.widgets[i].properties.len > 0

proc calculate(a, b: Value; t: float): Value =
  # Animation._calculate: lists element by element, numbers interpolated.
  if a.kind == vkList:
    var items: seq[Value] = @[]
    for x in 0 ..< a.items.len:
      items.add calculate(a.items[x], b.items[x], t)
    result = toValue(items)
  else:
    result = toValue((a.num * (1.0 - t)) + (b.num * t))

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
      let props = entry.properties
      for (key, va, vb) in props:
        setAttr(entry.target, key, calculate(va, vb, t))
      discard a.dispatch("on_progress", toValue(entry.target), toValue(progress))
      if progress >= 1.0:
        a.stop(entry.target)

proc clockInstall(a: Animation) =
  # Animation._clock_install
  if a.clockInstalled:
    return
  a.updateEv = Clock.scheduleInterval(proc (dt: float) {.closure.} = a.update(dt), a.step)
  a.clockInstalled = true

proc initialize(a: Animation; target: RootRef) =
  # Animation._initialize: the current values become the start values.
  var props: seq[(string, Value, Value)] = @[]
  let wanted = a.animatedProperties
  for (key, value) in wanted:
    props.add (key, getAttr(target, key), value)
  let i = a.find(target)
  let entry = AnimatedTarget(target: target, properties: props, time: 0, hasTime: false)
  # A dict keeps the place of a key that is assigned again.
  if i >= 0: a.widgets[i] = entry
  else: a.widgets.add entry
  a.clockInstall()

proc start*(a: Animation; target: RootRef) =
  ## Starts the animation on `target` (a dispatcher, Color or Translate),
  ## stopping it there first. Animation.start
  a.stop(target)
  a.initialize(target)
  a.register()
  discard a.dispatch("on_start", toValue(target))

proc stopAll*(target: RootRef; props: varargs[string]) =
  ## Stops every animation on `target`, or only the given properties.
  ## Animation.stop_all
  let snapshot = registry.instances
  if props.len > 0:
    for a in snapshot:
      for p in props:
        a.stopProperty(target, p)
  else:
    for a in snapshot:
      a.stop(target)

proc cancelAll*(target: nil RootRef; props: varargs[string]) =
  ## Cancels every animation on `target`, or only the given properties; a
  ## nil target means every animated target. Animation.cancel_all
  if target == nil:
    if props.len > 0:
      let snapshot = registry.instances
      for a in snapshot:
        let entries = a.widgets
        for entry in entries:
          for p in props:
            a.cancelProperty(entry.target, p)
    else:
      let all = registry.instances
      for a in all:
        a.widgets = @[]
        a.clockUninstall()
      registry.instances = @[]
    return
  let snapshot = registry.instances
  if props.len > 0:
    for a in snapshot:
      for p in props:
        a.cancelProperty(target, p)
  else:
    for a in snapshot:
      a.cancel(target)
