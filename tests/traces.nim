# Replays the steps of archive/reference/traces.py and writes
# tests/out/traces/<name>.txt, which must equal tests/fixtures/traces/<name>.txt
# line for line (REDESIGN.md, Standalone, says the format).
#
# Layer 1 writes `events` and `clock`, layer 6 `properties` (through the
# real Widget and BoxLayout). Layer 4 writes `label`, through the core
# label; layer 7 moves it to the Label widget, as traces.py does. Layer 5
# writes `touch`; layers 6 and 7 give it the real Widget, FloatLayout and
# ButtonBehavior. Layer 8 writes `animation`, `screens` and `modal`; the
# Window observer `touch` binds stays bound, as in traces.py, so the `modal`
# touches are logged by it too.

import std/[dirs, formatfloat, os, paths, strutils, syncio]
import nimkivy/[properties, clock, config, base, animation]
import nimkivy/core/text
import nimkivy/uix/[boxlayout, floatlayout, label, screenmanager, modalview]
import nimkivy/uix/behaviors/button
import stubs

type Log = ref object
  lines: seq[string]

let log = Log(lines: @[])

proc emit(log: Log; parts: varargs[string]) =
  # Python's log(*parts): the parts joined by spaces.
  var line = ""
  for i, p in parts:
    if i > 0: line.add " "
    line.add p
  log.lines.add line

proc save(log: Log; name: string) =
  let dir = "tests/out/traces"
  try:
    createDir(path(dir))
    writeFile(dir & "/" & name & ".txt", log.lines.join("\n") & "\n")
  except:
    quit "cannot write " & dir & "/" & name & ".txt"
  log.lines = @[]

proc args(a: seq[Value]): string =
  # The event's arguments as a Nim tuple of numbers: (7,)
  result = "("
  for i, v in a:
    if i > 0: result.add ", "
    result.add $int(v.num)
  if a.len == 1: result.add ","
  result.add ")"

# ------------------------------------------------------------------ properties

proc logger(name: string): PropertyCallback =
  result = proc (d: EventDispatcher; v: Value) {.closure.} = log.emit(name, $v)

proc hintText(pairs: seq[(string, Value)]): string =
  # A pos_hint as a Nim seq of (key, number) pairs: @[(top, 0.9)]
  result = "@["
  for i, (k, v) in pairs:
    if i > 0: result.add ", "
    result.add "(" & k & ", " & $v.num & ")"
  result.add "]"

proc traceProperties() =
  let w = newWidget()
  for name in ["x", "y", "pos", "right", "top", "center", "width", "size"]:
    w.bind(name, logger(name))
  log.emit "# pos = (1, 2)"
  w.setProperty("pos", toValue([1.0, 2.0]))
  log.emit "# pos = (1, 2) again"
  w.setProperty("pos", toValue([1.0, 2.0]))
  log.emit "# x = 5"
  w.setProperty("x", toValue(5))
  log.emit "# size = (50, 60)"
  w.setProperty("size", toValue([50.0, 60.0]))
  log.emit "# right = 300"
  w.setProperty("right", toValue(300))
  log.emit "# center = (0, 0)"
  w.setProperty("center", toValue([0.0, 0.0]))
  w.bind("x", logger("x second observer"))
  log.emit "# x = 6"
  w.setProperty("x", toValue(6))
  let b = newBoxLayout()
  let forms = [("5", toValue(5)), ("(10, 20)", toValue([10.0, 20.0])),
    ("(1, 2, 3, 4)", toValue([1.0, 2.0, 3.0, 4.0])), ("[7]", toValue([7.0]))]
  for (text, v) in forms:
    b.setProperty("padding", v)
    log.emit("padding", text, "->", $b.getProperty("padding"))
  log.emit("defaults size", $newWidget().getProperty("size"), "sizeHint",
    $newWidget().getProperty("size_hint"), "posHint", hintText(newWidget().posHint))
  let parent = newWidget()
  let child = newWidget()
  parent.addWidget(child)
  child.bind("disabled", proc (d: EventDispatcher; v: Value) {.closure.} =
    log.emit("child disabled", $v))
  parent.disabled = true
  log.emit("parent", $parent.disabled, "child", $child.disabled)
  child.disabled = false
  log.emit("child set false while parent disabled ->", $child.disabled)
  parent.disabled = false
  log.emit("parent false ->", $child.disabled)
  log.save "properties"

# ------------------------------------------------------------------ events

type D = ref object of EventDispatcher

let DClass = newDispatcherClass("D", EventDispatcherClass)
discard DClass.addNumeric("v", 0)
DClass.addPropertyHandler("v",
  proc (d: EventDispatcher; v: Value) = log.emit("default onV", $v))
DClass.addEvent("on_go",
  proc (d: EventDispatcher; a: seq[Value]): bool =
    log.emit("default onGo", args(a))
    result = false)

proc traceEvents() =
  let d = D(cls: DClass)
  d.initEventDispatcher()
  d.bind("v", proc (d: EventDispatcher; v: Value) {.closure.} = log.emit "v1")
  d.bind("v", proc (d: EventDispatcher; v: Value) {.closure.} = log.emit "v2 returns true")
  d.bind("v", proc (d: EventDispatcher; v: Value) {.closure.} = log.emit "v3")
  d.setProperty("v", toValue(1))
  d.setProperty("v", toValue(1))
  log.emit "# events"
  d.bind("on_go", proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
    log.emit("g1", args(a))
    result = false)
  d.bind("on_go", proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
    log.emit("g2", args(a))
    result = false)
  log.emit("dispatch ->", $(d.dispatch("on_go", toValue(7))))
  let uid = d.fbind("on_go", proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
    log.emit "g3 returns true"
    result = true)
  log.emit("dispatch ->", $(d.dispatch("on_go", toValue(8))))
  d.unbindUid("on_go", uid)
  log.emit("dispatch after unbindUid ->", $(d.dispatch("on_go", toValue(9))))
  log.save "events"

# ------------------------------------------------------------------ clock

proc caller(name: string): ClockCallback =
  result = proc (dt: float) {.closure.} = log.emit("call", name)

proc traceClock() =
  let c = newClockBase()
  c.maxFps = 0
  c.startClock()
  discard c.scheduleOnce(caller("once 0 a"), 0)
  discard c.scheduleOnce(caller("once -1"), -1)
  discard c.scheduleOnce(caller("once 0 b"), 0)
  let ev = c.scheduleInterval(caller("interval 0"), 0)
  discard c.scheduleOnce(proc (dt: float) {.closure.} =
    log.emit "call nest; schedules once 0 and once -1"
    discard c.scheduleOnce(caller("nested 0"), 0)
    discard c.scheduleOnce(caller("nested -1"), -1), 0)
  let trig = c.createTrigger(caller("trigger"), 0)
  trig.trigger()
  trig.trigger()  # a trigger runs once per tick however often it is called
  for step in 0 ..< 3:
    log.emit("# tickDraw " & $step)
    c.tickDraw()
    log.emit("# tick " & $step)
    c.tick()
  ev.cancel()
  log.emit "# after cancel"
  c.tick()
  c.stopClock()
  log.save "clock"

# ------------------------------------------------------------------ label

proc fmt3(v: float): string =
  # A number with 3 decimals, as the traces print them.
  formatFloat(v, ffDecimal, 3)

proc traceLabel() =
  # archive/reference/traces.py trace_label: Label(**kw), texture_update(),
  # and its texture_size. Each case is logged as the Nim named arguments
  # it sets.
  register("Deja", "data/fonts/DejaVuSans.ttf", fnBold = "data/fonts/Roboto-Bold.ttf")
  const text = "Figs have been grown in Greece for thousands of years. The fruit is " &
    "dried in the sun, pressed by hand and packed the same day."
  type Setup = proc (l: Label) {.closure.}
  let r = "text = \"" & text & "\""
  proc wrap(l: Label) =
    l.text = text
    l.textSize = (some(300.0), none[float]())
  # An array: a seq literal of proc literals is rejected
  # (planetis-m/nimony-bugs-llms#311).
  let cases: array[20, (string, Setup)] = [
    ("text = \"\"", proc (l: Label) {.closure.} = l.text = ""),
    ("text = \"A\"", proc (l: Label) {.closure.} = l.text = "A"),
    ("text = \"Hello world\"", proc (l: Label) {.closure.} = l.text = "Hello world"),
    ("text = \"two\\nlines\"", proc (l: Label) {.closure.} = l.text = "two\nlines"),
    ("text = \"trailing space \"", proc (l: Label) {.closure.} =
      l.text = "trailing space "),
    ("text = \"Ελληνικά\"", proc (l: Label) {.closure.} = l.text = "Ελληνικά"),
    ("text = \"Hello\", fontSize = 40", proc (l: Label) {.closure.} =
      l.text = "Hello"
      l.fontSize = 40),
    ("text = \"Hello\", bold = true", proc (l: Label) {.closure.} =
      l.text = "Hello"
      l.bold = true),
    ("text = \"Hello\", fontName = \"Deja\"", proc (l: Label) {.closure.} =
      l.text = "Hello"
      l.fontName = "Deja"),
    ("text = \"Hello\", fontName = \"Deja\", bold = true",
      proc (l: Label) {.closure.} =
        l.text = "Hello"
        l.fontName = "Deja"
        l.bold = true),
    (r & ", textSize = (300, none)", proc (l: Label) {.closure.} = wrap(l)),
    (r & ", textSize = (300, none), lineHeight = 1.25",
      proc (l: Label) {.closure.} =
        wrap(l)
        l.lineHeight = 1.25),
    (r & ", textSize = (300, none), lineHeight = 0.8",
      proc (l: Label) {.closure.} =
        wrap(l)
        l.lineHeight = 0.8),
    (r & ", textSize = (300, 100)", proc (l: Label) {.closure.} =
      l.text = text
      l.textSize = (some(300.0), some(100.0))),
    (r & ", textSize = (300, 40), valign = valignMiddle",
      proc (l: Label) {.closure.} =
        l.text = text
        l.textSize = (some(300.0), some(40.0))
        l.valign = valignMiddle),
    ("text = \"Hello\", padding = (10, 5)", proc (l: Label) {.closure.} =
      l.text = "Hello"
      l.padding = [10.0, 5]),
    (r & ", textSize = (300, none), padding = (20, 0)",
      proc (l: Label) {.closure.} =
        wrap(l)
        l.padding = [20.0, 0]),
    (r & ", textSize = (300, none), halign = halignJustify",
      proc (l: Label) {.closure.} =
        wrap(l)
        l.halign = halignJustify),
    ("text = \"averyveryverylongwordthatcannotwrap\", textSize = (100, none)",
      proc (l: Label) {.closure.} =
        l.text = "averyveryverylongwordthatcannotwrap"
        l.textSize = (some(100.0), none[float]())),
    ("text = \"Hello\", textSize = (none, 100)", proc (l: Label) {.closure.} =
      l.text = "Hello"
      l.textSize = (none[float](), some(100.0)))]
  for (kw, setup) in cases:
    let l = newLabel()
    setup(l)
    l.textureUpdate()
    let (w, h) = l.textureSize
    log.emit(kw, "->", "(" & fmt3(w) & ", " & fmt3(h) & ")")
  log.save "label"

# ------------------------------------------------------------------ animation

proc tickFor(seconds: float) =
  # traces.py: `while time.time() - t0 < s: time.sleep(0.01); Clock.tick()`
  let t0 = time()
  while time() - t0 < seconds:
    sleep(10)
    Clock.tick()

proc logOnComplete(a: Animation; text: string; w: Widget) =
  # Logs `text` and w's opacity when `a` completes (one closure per call).
  a.bind("on_complete", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit(text, fmt3(w.opacity))
    result = false)

proc traceAnimation() =
  # archive/reference/traces.py trace_animation
  let w = newWidget()
  w.opacity = 0
  let anim = newAnimation({"opacity": 1.0}, duration = 0.2)
  anim.bind("on_start", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit "onStart"
    result = false)
  anim.logOnComplete("onComplete opacity", w)
  var progress: seq[float] = @[]
  anim.bind("on_progress", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    progress.add args[1].num
    result = false)
  anim.start(w)
  # traces.py checks `w in [x["widget"] for x in anim._widgets.values()]`.
  log.emit("after start opacity", fmt3(w.opacity), "running",
    $anim.havePropertiesToAnimate(w))
  tickFor(0.5)
  var monotonic = true
  for i in 1 ..< progress.len:
    if progress[i] < progress[i - 1]: monotonic = false
  log.emit("progress first", fmt3(progress[0]), "last", fmt3(progress[^1]), "monotonic",
    $monotonic)
  let w2 = newWidget()
  w2.opacity = 1
  let a1 = newAnimation({"opacity": 0.0}, duration = 0.1)
  let a2 = newAnimation({"opacity": 0.5}, duration = 0.3)
  a1.logOnComplete("a1 complete opacity", w2)
  a2.logOnComplete("a2 complete opacity", w2)
  a1.start(w2)
  a2.start(w2)  # both run on the same property; the later write each frame wins
  tickFor(0.6)
  let w3 = newWidget()
  w3.opacity = 1
  let a3 = newAnimation({"opacity": 0.0}, duration = 1)
  a3.bind("on_complete", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit "a3 complete (stop)"
    result = false)
  a3.start(w3)
  Clock.tick()
  a3.stop(w3)
  let a4 = newAnimation({"opacity": 0.0}, duration = 1)
  a4.bind("on_complete", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit "a4 complete (must not appear: cancel)"
    result = false)
  a4.start(w3)
  a4.cancel(w3)
  let a5 = newAnimation({"opacity": 0.25}, duration = 0)
  a5.logOnComplete("a5 duration 0 complete opacity", w3)
  a5.start(w3)
  Clock.tick()
  Clock.tick()
  log.save "animation"

# ------------------------------------------------------------------ touch

type
  Btn = ref object of Widget
    # traces.py trace_touch: class Btn(ButtonBehavior, Widget).
    tag: string
    button: nil ButtonBehavior

let BtnClass = newDispatcherClass("Btn", WidgetClass)
BtnClass.addButtonBehavior()

proc r(p: (float, float)): string =
  # traces.py r(): numbers with 3 decimals.
  "(" & formatFloat(p[0], ffDecimal, 3) & ", " & formatFloat(p[1], ffDecimal, 3) & ")"

proc tagOf(d: nil EventDispatcher): string =
  if d == nil: "nil"
  elif d of Btn: Btn(d).tag
  else: "?"

proc onPress(d: EventDispatcher; args: seq[Value]): bool =
  log.emit(Btn(d).tag, "onPress")
  result = false

proc onRelease(d: EventDispatcher; args: seq[Value]): bool =
  log.emit(Btn(d).tag, "onRelease")
  result = false

BtnClass.setEventHandler("on_press", onPress)
BtnClass.setEventHandler("on_release", onRelease)

proc newBtn(tag: string; x, y, w, h: float): Btn =
  result = Btn(cls: BtnClass, canvas: newCanvas(), tag: tag, button: nil)
  result.initWidget()
  result.button = newButtonBehavior(result)
  result.sizeHint = (none[float](), none[float]())
  result.size = (w, h)
  result.pos = (x, y)
  result.bind("state", proc (d: EventDispatcher; v: Value) {.closure.} =
    log.emit(tag, "state", v.str))

proc buttonOf(b: Btn): ButtonBehavior =
  let bb = b.button
  if bb == nil: quit "Btn without its ButtonBehavior"
  result = bb

method onTouchDown(b: Btn; t: MotionEvent): bool =
  log.emit(b.tag, "onTouchDown", r(t.pos))
  result = b.buttonOf.onTouchDown(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchDown(Widget(b), t))
  log.emit(b.tag, "onTouchDown ->", $result)

method onTouchMove(b: Btn; t: MotionEvent): bool =
  result = b.buttonOf.onTouchMove(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchMove(Widget(b), t))
  log.emit(b.tag, "onTouchMove grabCurrent", tagOf(t.grabCurrent), "->",
    $result)

method onTouchUp(b: Btn; t: MotionEvent): bool =
  result = b.buttonOf.onTouchUp(t, proc (t: MotionEvent): bool {.closure.} =
    procCall onTouchUp(Widget(b), t))
  log.emit(b.tag, "onTouchUp grabCurrent", tagOf(t.grabCurrent), "->",
    $result)

proc tap(x, y: float; name: string; moveTo = (-1.0, -1.0)) =
  # traces.py trace_touch tap()
  log.emit "# " & name
  let t = newUnitTestTouch(x, y)
  t.touchDown()
  if moveTo[0] >= 0:
    t.touchMove(moveTo[0], moveTo[1])
  t.touchUp()
  log.emit "(wait past minStateTime 0.035 s, tick the clock)"
  sleep(60)
  Clock.tick()

proc traceTouch() =
  # archive/reference/traces.py trace_touch, in an 800 x 600 window.
  EventLoop.ensureWindow()
  let win = Window
  let root = newFloatLayout()
  let a = newBtn("A", 100, 100, 200, 200)
  let b = newBtn("B", 200, 200, 200, 200)      # added later: on top
  let c = newBtn("C", 600, 100, 100, 100)
  c.disabled = true
  for w in [a, b, c]:
    root.addWidget(w)
  win.addWidget(root)
  win.bind("on_touch_down", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit("Window observer onTouchDown", r(toMotionEvent(args[0]).pos))
    result = false)
  tap(150, 150, "tap A only")
  tap(250, 250, "tap overlap: B is on top")
  tap(150, 150, "press A, release outside", (700.0, 500.0))
  tap(150, 150, "press A, release over B", (350.0, 350.0))
  tap(650, 150, "tap disabled C")
  tap(50, 550, "tap empty space")
  win.removeWidget(root)
  log.save "touch"

# ------------------------------------------------------------------ screens

proc nimList(items: seq[string]): string =
  # A seq of names as a Nim literal: @["a", "b"]
  result = "@["
  for i, x in items:
    if i > 0: result.add ", "
    result.add "\"" & x & "\""
  result.add "]"

proc childNames(sm: ScreenManager): string =
  var names: seq[string] = @[]
  for c in sm.children:
    if c of Screen: names.add Screen(c).name
  result = nimList(names)

proc logScreenEvent(s: Screen; e, shown: string) =
  # Logs `shown` (the event's Nim name) when event `e` is dispatched. One
  # closure per call: closures made in a loop share the loop's variables.
  s.bind(e, proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit(Screen(d).name, shown)
    result = false)

proc newS(name: string): Screen =
  # traces.py trace_screens: class S(Screen) logging its four events.
  result = newScreen(name)
  for (ev, shown) in [("on_pre_enter", "onPreEnter"), ("on_enter", "onEnter"),
      ("on_pre_leave", "onPreLeave"), ("on_leave", "onLeave")]:
    result.logScreenEvent(ev, shown)

proc traceScreens() =
  # archive/reference/traces.py trace_screens
  let win = Window
  let sm = newScreenManager()
  let fade = newFadeTransition()
  fade.duration = 0.1
  sm.transition = fade
  win.addWidget(sm)
  log.emit "# add first screen"
  sm.addWidget(newS("a"))
  log.emit("current", sm.current.get("none"))
  sm.addWidget(newS("b"))
  sm.addWidget(newS("c"))
  log.emit("screenNames", nimList(sm.screenNames), "children", childNames(sm))
  log.emit "# current = b"
  sm.current = "b"
  log.emit("isActive", $(sm.transition.isActive), "children", childNames(sm))
  log.emit "# current = c while a->b is running"
  sm.current = "c"
  tickFor(0.4)
  log.emit("after", "current", sm.current.get("none"), "isActive",
    $(sm.transition.isActive), "children", childNames(sm))
  log.emit "# current = c again (no-op)"
  sm.current = "c"
  win.removeWidget(sm)
  log.save "screens"

# ------------------------------------------------------------------ modal

proc logModalEvent(mv: ModalView; e, shown: string) =
  # Logs `shown` (the event's Nim name) when event `e` is dispatched.
  mv.bind(e, proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit shown
    result = false)

proc touchAt(x, y: float) =
  # traces.py make_touch(x, y): touch_down() then touch_up()
  let t = newUnitTestTouch(x, y)
  t.touchDown()
  t.touchUp()

proc traceModal() =
  # archive/reference/traces.py trace_modal
  let win = Window
  let mv = newModalView()
  mv.sizeHint = (none[float](), none[float]())
  mv.size = (200.0, 100.0)
  for (ev, shown) in [("on_pre_open", "onPreOpen"), ("on_open", "onOpen"),
      ("on_pre_dismiss", "onPreDismiss"), ("on_dismiss", "onDismiss")]:
    mv.logModalEvent(ev, shown)
  proc inWindow(mv: ModalView): string =
    $(Window.children.find(WidgetBase(mv)) >= 0)
  log.emit "# open(animation = false)"
  mv.open(animation = false)
  log.emit("isOpen", $(mv.isOpen), "center", r(mv.center), "in window", inWindow(mv))
  log.emit "# touch inside"
  touchAt(400, 300)
  log.emit("isOpen", $(mv.isOpen))
  log.emit "# touch outside"
  touchAt(10, 10)
  log.emit("isOpen", $(mv.isOpen), "in window", inWindow(mv))
  log.emit "# open again, escape key"
  mv.open(animation = false)
  discard win.dispatch("on_keyboard", toValue(27), toValue(41), noneValue(),
    toValue(newSeq[Value]()))
  log.emit("isOpen after escape (animated dismiss pending)", $(mv.isOpen))
  tickFor(0.3)
  log.emit("isOpen after animation", $(mv.isOpen))
  log.emit "# autoDismiss false"
  mv.autoDismiss = false
  mv.open(animation = false)
  touchAt(10, 10)
  log.emit("isOpen", $(mv.isOpen))
  mv.dismiss(animation = false)
  log.emit("isOpen", $(mv.isOpen))
  log.save "modal"

# traces.py sets Config before anything opens the window (a Widget does).
Config.set("graphics", "width", "800")
Config.set("graphics", "height", "600")
Config.set("graphics", "resizable", "0")
traceProperties()
traceEvents()
traceClock()
traceAnimation()
traceLabel()
traceTouch()
traceScreens()
traceModal()
