# Replays the steps of reference/traces.py and writes tests/out/traces/<name>.txt,
# which must equal reference/out/traces/<name>.txt line for line.
#
# Layer 1 writes `events` and `clock`, and the part of `properties` that a
# plain dispatcher can show (the ReferenceList and Alias order of a Widget's
# geometry, and VariableList forms). The Widget lines follow in layer 6.
# Layer 4 writes `label`, through the core label. Layer 5 writes `touch`,
# with stub widgets in place of FloatLayout and ButtonBehavior (layers 6
# and 7).

import std/[dirs, formatfloat, os, paths, strutils, syncio]
import nimkivy/[properties, clock, config, base]
import nimkivy/core/text
import nimkivy/core/text/text_sdl3
import nimkivy/graphics/instructions
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

proc pyBool(b: bool): string =
  # What Kivy's dispatch returns, printed: True, or None from the handlers.
  if b: "True" else: "None"

proc args(a: seq[Value]): string =
  # A Python tuple of numbers, as `print` shows `a[1:]`: (7,)
  result = "("
  for i, v in a:
    if i > 0: result.add ", "
    result.add $int(v.num)
  if a.len == 1: result.add ","
  result.add ")"

# ------------------------------------------------------------------ properties

type Geometry = ref object of EventDispatcher
  # The geometry properties of kivy/uix/widget.py, on a plain dispatcher.

let GeometryClass = newDispatcherClass("Widget", EventDispatcherClass)
let gX = GeometryClass.addNumeric("x", 0)
let gY = GeometryClass.addNumeric("y", 0)
let gWidth = GeometryClass.addNumeric("width", 100)
let gHeight = GeometryClass.addNumeric("height", 100)
discard GeometryClass.addReferenceList("pos", @[Property(gX), gY])
discard GeometryClass.addReferenceList("size", @[Property(gWidth), gHeight])
let gRight = GeometryClass.addAlias("right",
  proc (d: EventDispatcher): Value = toValue(gX.getNumber(d) + gWidth.getNumber(d)),
  proc (d: EventDispatcher; v: Value): bool =
    gX.setNumber(d, v.num - gWidth.getNumber(d))
    result = false,
  @["x", "width"], cache = true, watchBeforeUse = false)
let gTop = GeometryClass.addAlias("top",
  proc (d: EventDispatcher): Value = toValue(gY.getNumber(d) + gHeight.getNumber(d)),
  proc (d: EventDispatcher; v: Value): bool =
    gY.setNumber(d, v.num - gHeight.getNumber(d))
    result = false,
  @["y", "height"], cache = true, watchBeforeUse = false)
let gCenterX = GeometryClass.addAlias("center_x",
  proc (d: EventDispatcher): Value = toValue(gX.getNumber(d) + gWidth.getNumber(d) / 2),
  proc (d: EventDispatcher; v: Value): bool =
    gX.setNumber(d, v.num - gWidth.getNumber(d) / 2)
    result = false,
  @["x", "width"], cache = true, watchBeforeUse = false)
let gCenterY = GeometryClass.addAlias("center_y",
  proc (d: EventDispatcher): Value = toValue(gY.getNumber(d) + gHeight.getNumber(d) / 2),
  proc (d: EventDispatcher; v: Value): bool =
    gY.setNumber(d, v.num - gHeight.getNumber(d) / 2)
    result = false,
  @["y", "height"], cache = true, watchBeforeUse = false)
discard GeometryClass.addReferenceList("center", @[Property(gCenterX), gCenterY])

let PaddedClass = newDispatcherClass("BoxLayout", EventDispatcherClass)
let pPadding = PaddedClass.addVariableList("padding", @[0.0, 0.0, 0.0, 0.0])

proc logger(name: string): PropertyCallback =
  result = proc (d: EventDispatcher; v: Value) {.closure.} = log.emit(name, $v)

proc traceProperties() =
  let w = Geometry(cls: GeometryClass)
  w.initEventDispatcher()
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
  let b = EventDispatcher(cls: PaddedClass)
  b.initEventDispatcher()
  let forms = [("5", toValue(5)), ("(10, 20)", toValue([10.0, 20.0])),
    ("(1, 2, 3, 4)", toValue([1.0, 2.0, 3.0, 4.0])), ("[7]", toValue([7.0]))]
  for (text, v) in forms:
    discard pPadding.set(b, v)
    log.emit("padding", text, "->", $pPadding.get(b))
  # The Widget lines (defaults, inherited disabled) come with layer 6.
  log.save "properties"

# ------------------------------------------------------------------ events

type D = ref object of EventDispatcher

let DClass = newDispatcherClass("D", EventDispatcherClass)
discard DClass.addNumeric("v", 0)
DClass.addPropertyHandler("v",
  proc (d: EventDispatcher; v: Value) = log.emit("default on_v", $v))
DClass.addEvent("on_go",
  proc (d: EventDispatcher; a: seq[Value]): bool =
    log.emit("default on_go", args(a))
    result = false)

proc traceEvents() =
  let d = D(cls: DClass)
  d.initEventDispatcher()
  d.bind("v", proc (d: EventDispatcher; v: Value) {.closure.} = log.emit "v1")
  d.bind("v", proc (d: EventDispatcher; v: Value) {.closure.} = log.emit "v2 returns True")
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
  log.emit("dispatch ->", pyBool(d.dispatch("on_go", toValue(7))))
  let uid = d.fbind("on_go", proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
    log.emit "g3 returns True"
    result = true)
  log.emit("dispatch ->", pyBool(d.dispatch("on_go", toValue(8))))
  d.unbindUid("on_go", uid)
  log.emit("dispatch after unbind_uid ->", pyBool(d.dispatch("on_go", toValue(9))))
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
    log.emit("# tick_draw " & $step)
    c.tickDraw()
    log.emit("# tick " & $step)
    c.tick()
  ev.cancel()
  log.emit "# after cancel"
  c.tick()
  c.stopClock()
  log.save "clock"

# ------------------------------------------------------------------ label

proc fmt3(v: int): string =
  # Python's f"{float(v):.3f}"
  formatFloat(float(v), ffDecimal, 3)

proc labelTextureSize(l: LabelBase): (int, int) =
  # uix/label.py Label.texture_update, which layer 7 ports: no texture for
  # an empty text, else the refreshed core label's texture size.
  let o = l.options
  if l.text.len == 0 or ((o.halign == halignJustify or o.strip) and
      pyStrip(l.text).len == 0):
    result = (0, 0)
  else:
    l.refresh()
    let t = l.texture
    result = if t != nil: (t.width, t.height) else: (0, 0)

proc traceLabel() =
  # reference/traces.py trace_label, through the core label (LabelBase) with
  # the options a Label passes it: font_size sp(15), halign 'auto'.
  register("Deja", "data/fonts/DejaVuSans.ttf", fnBold = "data/fonts/Roboto-Bold.ttf")
  const text = "Figs have been grown in Greece for thousands of years. The fruit is " &
    "dried in the sun, pressed by hand and packed the same day."
  type Setup = proc (l: LabelBase) {.closure.}
  let r = "{'text': '" & text & "'"
  proc wrap(l: LabelBase) =
    l.text = text
    l.textSize = (some(300.0), none[float]())
  # An array: a seq literal of proc literals is rejected
  # (planetis-m/nimony-bugs-llms#311).
  let cases: array[20, (string, Setup)] = [
    ("{'text': ''}", proc (l: LabelBase) {.closure.} = l.text = ""),
    ("{'text': 'A'}", proc (l: LabelBase) {.closure.} = l.text = "A"),
    ("{'text': 'Hello world'}", proc (l: LabelBase) {.closure.} = l.text = "Hello world"),
    ("{'text': 'two\\nlines'}", proc (l: LabelBase) {.closure.} = l.text = "two\nlines"),
    ("{'text': 'trailing space '}", proc (l: LabelBase) {.closure.} =
      l.text = "trailing space "),
    ("{'text': 'Ελληνικά'}", proc (l: LabelBase) {.closure.} = l.text = "Ελληνικά"),
    ("{'text': 'Hello', 'font_size': 40}", proc (l: LabelBase) {.closure.} =
      l.text = "Hello"
      l.options.fontSize = 40),
    ("{'text': 'Hello', 'bold': True}", proc (l: LabelBase) {.closure.} =
      l.text = "Hello"
      l.options.bold = true),
    ("{'text': 'Hello', 'font_name': 'Deja'}", proc (l: LabelBase) {.closure.} =
      l.text = "Hello"
      l.options.fontName = "Deja"),
    ("{'text': 'Hello', 'font_name': 'Deja', 'bold': True}",
      proc (l: LabelBase) {.closure.} =
        l.text = "Hello"
        l.options.fontName = "Deja"
        l.options.bold = true),
    (r & ", 'text_size': (300, None)}", proc (l: LabelBase) {.closure.} = wrap(l)),
    (r & ", 'text_size': (300, None), 'line_height': 1.25}",
      proc (l: LabelBase) {.closure.} =
        wrap(l)
        l.options.lineHeight = 1.25),
    (r & ", 'text_size': (300, None), 'line_height': 0.8}",
      proc (l: LabelBase) {.closure.} =
        wrap(l)
        l.options.lineHeight = 0.8),
    (r & ", 'text_size': (300, 100)}", proc (l: LabelBase) {.closure.} =
      l.text = text
      l.textSize = (some(300.0), some(100.0))),
    (r & ", 'text_size': (300, 40), 'valign': 'middle'}",
      proc (l: LabelBase) {.closure.} =
        l.text = text
        l.textSize = (some(300.0), some(40.0))
        l.options.valign = valignMiddle),
    ("{'text': 'Hello', 'padding': (10, 5)}", proc (l: LabelBase) {.closure.} =
      l.text = "Hello"
      l.options.setPadding([10.0, 5])),
    (r & ", 'text_size': (300, None), 'padding': (20, 0)}",
      proc (l: LabelBase) {.closure.} =
        wrap(l)
        l.options.setPadding([20.0, 0])),
    (r & ", 'text_size': (300, None), 'halign': 'justify'}",
      proc (l: LabelBase) {.closure.} =
        wrap(l)
        l.options.halign = halignJustify),
    ("{'text': 'averyveryverylongwordthatcannotwrap', 'text_size': (100, None)}",
      proc (l: LabelBase) {.closure.} =
        l.text = "averyveryverylongwordthatcannotwrap"
        l.textSize = (some(100.0), none[float]())),
    ("{'text': 'Hello', 'text_size': (None, 100)}", proc (l: LabelBase) {.closure.} =
      l.text = "Hello"
      l.textSize = (none[float](), some(100.0)))]
  for (kw, setup) in cases:
    let l = newLabelSDL3()
    l.options.fontSize = 15
    l.options.halign = halignAuto
    setup(l)
    let (w, h) = labelTextureSize(l)
    log.emit(kw, "->", "(" & fmt3(w) & ", " & fmt3(h) & ")")
  log.save "label"

# ------------------------------------------------------------------ touch

type
  Btn = ref object of StubWidget
    # traces.py trace_touch Btn(ButtonBehavior, Widget), with the ButtonBehavior
    # part written out here until layer 7 ports it (uix/behaviors/button.py).
    tag: string
    touchTime: float

let BtnClass = newDispatcherClass("Btn", StubWidgetClass)
discard BtnClass.addString("state", "normal")

proc r(p: (float, float)): string =
  # traces.py r(): numbers with 3 decimals.
  "(" & formatFloat(p[0], ffDecimal, 3) & ", " & formatFloat(p[1], ffDecimal, 3) & ")"

proc pyResult(b: bool; falsy: string): string =
  # What the Python method returned, printed: True, or its falsy value
  # (False from on_touch_down and on_touch_move, None from on_touch_up).
  if b: "True" else: falsy

proc tagOf(d: nil EventDispatcher): string =
  if d == nil: "None"
  elif d of Btn: Btn(d).tag
  else: "?"

proc newBtn(tag: string; x, y, w, h: float): Btn =
  result = Btn(cls: BtnClass, canvas: newCanvas(), tag: tag, touchTime: 0)
  result.initStubWidget(x, y, w, h)
  result.bind("state", proc (d: EventDispatcher; v: Value) {.closure.} =
    log.emit(tag, "state", v.str))

proc doRelease(b: Btn) =
  b.setProperty("state", toValue("normal"))

proc key(b: Btn): Value = toValue(RootRef(b))

proc buttonTouchDown(b: Btn; t: MotionEvent): bool =
  # ButtonBehavior.on_touch_down
  if procCall onTouchDown(StubWidget(b), t): return true
  if t.isMouseScrolling: return false
  if not b.collidePoint(t.x, t.y): return false
  if b.key in t.ud: return false
  t.grab(b)
  t.ud[b.key] = toValue(true)
  b.touchTime = time()
  b.setProperty("state", toValue("down"))
  log.emit(b.tag, "on_press")
  result = true

proc buttonTouchMove(b: Btn; t: MotionEvent): bool =
  # ButtonBehavior.on_touch_move
  if t.grabCurrent == EventDispatcher(b): return true
  if procCall onTouchMove(StubWidget(b), t): return true
  result = b.key in t.ud

proc buttonTouchUp(b: Btn; t: MotionEvent): bool =
  # ButtonBehavior.on_touch_up
  if t.grabCurrent != EventDispatcher(b):
    return procCall onTouchUp(StubWidget(b), t)
  t.ungrab(b)
  if not b.collidePoint(t.pos[0], t.pos[1]):
    b.doRelease()
    return false
  let touchtime = time() - b.touchTime
  let minStateTime = Config.getfloat("graphics", "min_state_time")
  if touchtime < minStateTime:
    discard Clock.scheduleOnce(proc (dt: float) {.closure.} = b.doRelease(),
      minStateTime - touchtime)
  else:
    b.doRelease()
  log.emit(b.tag, "on_release")
  result = true

method onTouchDown(b: Btn; t: MotionEvent): bool =
  log.emit(b.tag, "on_touch_down", r(t.pos))
  result = b.buttonTouchDown(t)
  log.emit(b.tag, "on_touch_down ->", pyResult(result, "False"))

method onTouchMove(b: Btn; t: MotionEvent): bool =
  result = b.buttonTouchMove(t)
  log.emit(b.tag, "on_touch_move grab_current", tagOf(t.grabCurrent), "->",
    pyResult(result, "False"))

method onTouchUp(b: Btn; t: MotionEvent): bool =
  result = b.buttonTouchUp(t)
  log.emit(b.tag, "on_touch_up grab_current", tagOf(t.grabCurrent), "->",
    pyResult(result, "None"))

proc tap(x, y: float; name: string; moveTo = (-1.0, -1.0)) =
  # traces.py trace_touch tap()
  log.emit "# " & name
  let t = newUnitTestTouch(x, y)
  t.touchDown()
  if moveTo[0] >= 0:
    t.touchMove(moveTo[0], moveTo[1])
  t.touchUp()
  log.emit "(wait past min_state_time .035 s, tick the clock)"
  sleep(60)
  Clock.tick()

proc traceTouch() =
  # reference/traces.py trace_touch, in an 800 x 600 window. The root is a
  # plain widget (a FloatLayout there, which only passes touches on here).
  Config.set("graphics", "width", "800")
  Config.set("graphics", "height", "600")
  Config.set("graphics", "resizable", "0")
  EventLoop.ensureWindow()
  let win = Window
  let root = newStubWidget()
  let a = newBtn("A", 100, 100, 200, 200)
  let b = newBtn("B", 200, 200, 200, 200)      # added later: on top
  let c = newBtn("C", 600, 100, 100, 100)
  c.disabled = true
  for w in [a, b, c]:
    root.addWidget(w)
  win.addWidget(root)
  win.bind("on_touch_down", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    log.emit("Window observer on_touch_down", r(toMotionEvent(args[0]).pos))
    result = false)
  tap(150, 150, "tap A only")
  tap(250, 250, "tap overlap: B is on top")
  tap(150, 150, "press A, release outside", (700.0, 500.0))
  tap(150, 150, "press A, release over B", (350.0, 350.0))
  tap(650, 150, "tap disabled C")
  tap(50, 550, "tap empty space")
  win.removeWidget(root)
  log.save "touch"

traceProperties()
traceEvents()
traceClock()
traceLabel()
traceTouch()
