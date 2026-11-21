# Replays the steps of reference/traces.py and writes tests/out/traces/<name>.txt,
# which must equal reference/out/traces/<name>.txt line for line.
#
# Layer 1 writes `events` and `clock`, and the part of `properties` that a
# plain dispatcher can show (the ReferenceList and Alias order of a Widget's
# geometry, and VariableList forms). The Widget lines follow in layer 6.

import std/[dirs, paths, strutils, syncio]
import nimkivy/[properties, clock]

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

traceProperties()
traceEvents()
traceClock()
