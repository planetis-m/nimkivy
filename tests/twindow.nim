# Tests of core/window, core/window/window_sdl3 and base (ACCEPTANCE.md,
# layer 5): screenshot numbering, touch dispatch to the children newest
# first, observers before the default handler, key 27 with and without
# `exit_on_escape`, and a headless run that takes SDL events the way the
# system sends them: the window opens (SDL offscreen driver), draws, takes a
# screenshot, gets finger, mouse and key events pushed with SDL_PushEvent,
# and stops on key 27. The last block closes the window, so it stays last.

import std/[assertions, os, syncio]
from std/dirs import createDir
from std/files import tryRemoveFile
from std/paths import path
import nimkivy/[app, config, clock]
import nimkivy/sdl3/[sdl, image]
import nimkivy/graphics/[instructions, context_instructions, vertex_instructions]
import stubs

type Log = ref object
  lines: seq[string]

proc logger(log: Log; tag: sink string; ret: bool): proc (): bool {.closure.} =
  result = proc (): bool {.closure.} =
    log.lines.add tag
    result = ret

proc touchLogger(log: Log; tag: sink string; ret: bool): TouchCallback =
  result = proc (t: MotionEvent): bool {.closure.} =
    log.lines.add tag
    result = ret

proc closeLogger(log: Log; tag: sink string; ret: bool): proc (keyboard: bool): bool {.closure.} =
  result = proc (keyboard: bool): bool {.closure.} =
    log.lines.add tag
    result = ret

proc keyLogger(log: Log; tag: sink string; ret: bool): proc (key, scancode: int;
    codepoint: string; modifiers: set[Modifier]): bool {.closure.} =
  result = proc (key, scancode: int; codepoint: string;
      modifiers: set[Modifier]): bool {.closure.} =
    log.lines.add tag
    result = ret

type Child = ref object of WidgetBase
  # A root widget that records its touches and returns `ret`. A bare
  # WidgetBase, not a Widget: a Widget opens the window, and this file
  # opens it last, in `headless_run`.
  tag: string
  log: Log
  ret: bool

method onTouchDown(c: Child; t: MotionEvent): bool =
  c.log.lines.add c.tag & " down"
  result = c.ret

method onTouchMove(c: Child; t: MotionEvent): bool =
  c.log.lines.add c.tag & " move"
  result = c.ret

method onTouchUp(c: Child; t: MotionEvent): bool =
  c.log.lines.add c.tag & " up"
  result = c.ret

proc newChild(tag: sink string; log: sink Log; ret = false): Child =
  result = Child(canvas: newCanvas(), tag: tag, log: log, ret: ret)
  result.initWidgetBase()

proc cwd(): string =
  try:
    result = getCurrentDir()
  except:
    quit "no current directory"

proc outDir(): string =
  result = cwd() / "tests" / "out" / "twindow"
  try:
    createDir(path(result))
  except:
    quit "cannot create " & result

proc removeFile(f: string) =
  discard tryRemoveFile(path(f))

block screenshot_numbering:
  # kivy/core/window/__init__.py WindowBase.screenshot: the first free
  # number, `<stem>0001.<ext>`, in the current directory unless absolute.
  let w = WindowBase(canvas: newCanvas())
  w.initWindowBase()
  assert w.screenshot() == cwd() / "screenshot0001.png"
  let dir = outDir()
  for f in ["shot0001.png", "shot0002.png", "shot0003.jpg"]:
    removeFile(dir / f)
  assert w.screenshot(dir / "shot.png") == dir / "shot0001.png"
  try:
    writeFile(dir / "shot0001.png", "")
  except:
    quit "cannot write"
  assert w.screenshot(dir / "shot.png") == dir / "shot0002.png"
  assert w.screenshot(dir / "shot.jpg") == dir / "shot0001.jpg"
  assert w.screenshot("rel.png") == cwd() / "rel0001.png"
  removeFile(dir / "shot0001.png")

block window_properties:
  # The window object exists before its system window, sized from Config.
  let w = WindowBase(canvas: newCanvas())
  w.initWindowBase()
  assert w.size == (800.0, 600.0) and w.width == 800 and w.height == 600
  assert w.center == (400.0, 300.0)
  assert w.clearcolor == [0.0, 0.0, 0.0, 1.0]
  w.clearcolor = [1.0, 0.0, 0.0]
  assert w.clearcolor == [1.0, 0.0, 0.0, 1.0]
  var resized: seq[(float, float)] = @[]
  discard w.bindResize(proc (width, height: float): bool {.closure.} =
    resized.add (width, height)
    result = false)
  var widths: seq[float] = @[]
  discard w.bindWidth(proc (v: float) {.closure.} = widths.add v)
  w.size = (640.0, 480.0)
  assert w.size == (640.0, 480.0) and w.systemSize == (640.0, 480.0)
  assert resized == @[(640.0, 480.0)] and widths == @[640.0]
  w.size = (640.0, 480.0)
  assert resized.len == 1
  assert w.parent == WidgetBase(w) and w.getRootWindow() == WidgetBase(w)

block children_dispatch_order:
  # WindowBase.on_touch_*: children newest first, stop at the first true.
  let w = WindowBase(canvas: newCanvas())
  w.initWindowBase()
  let log = Log(lines: @[])
  let a = newChild("a", log)
  let b = newChild("b", log, ret = true)
  let c = newChild("c", log)
  for x in [a, b, c]: w.addWidget(x)
  assert w.children == @[WidgetBase(c), b, a]
  assert a.parent == WidgetBase(w)
  assert w.canvas.indexof(a.canvas) == 0 and w.canvas.indexof(c.canvas) == 2
  let t = newUnitTestTouch(10, 10)
  assert w.dispatchTouchDown(t)
  assert log.lines == @["c down", "b down"]
  log.lines = @[]
  w.removeWidget(b)
  assert b.parent == nil and w.canvas.indexof(b.canvas) == -1
  assert not w.dispatchTouchUp(t)
  assert log.lines == @["c up", "a up"]
  # canvas 'before' and 'after'
  let d = newChild("d", log)
  w.addWidget(d, canvas = layerAfter)
  assert w.canvas.after.indexof(d.canvas) == 0
  w.removeWidget(d)
  assert w.canvas.after.indexof(d.canvas) == -1

block observer_before_default_handler:
  let w = WindowBase(canvas: newCanvas())
  w.initWindowBase()
  let log = Log(lines: @[])
  w.addWidget(newChild("child", log))
  discard w.bindTouchDown(touchLogger(log, "observer", false))
  let t = newUnitTestTouch(10, 10)
  discard w.dispatchTouchDown(t)
  assert log.lines == @["observer", "child down"]
  log.lines = @[]
  discard w.bindTouchDown(touchLogger(log, "stopper", true))
  assert w.dispatchTouchDown(t)
  assert log.lines == @["stopper"]

block key_27_without_exit_on_escape:
  let w = WindowBase(canvas: newCanvas())
  w.initWindowBase()
  let log = Log(lines: @[])
  var stopped = 0
  w.stopTouchApp = proc () {.closure.} = inc stopped
  discard w.bindRequestClose(closeLogger(log, "requestClose", false))
  discard w.bindClose(logger(log, "close", false))
  Config.kivy.exitOnEscape = false
  assert not w.dispatchKeyboard(27, 41, "", {})
  assert log.lines.len == 0 and stopped == 0
  Config.kivy.exitOnEscape = true
  # Another key does nothing either.
  assert not w.dispatchKeyboard(13, 40, "", {})
  assert log.lines.len == 0 and stopped == 0

block key_27_with_exit_on_escape:
  let w = WindowBase(canvas: newCanvas())
  w.initWindowBase()
  let log = Log(lines: @[])
  var stopped = 0
  w.stopTouchApp = proc () {.closure.} = inc stopped
  discard w.bindClose(logger(log, "close", false))
  discard w.bindRequestClose(proc (keyboard: bool): bool {.closure.} =
    log.lines.add "requestClose keyboard " & $keyboard
    result = false)
  assert w.dispatchKeyboard(27, 41, "", {})
  assert log.lines == @["requestClose keyboard true", "close"] and stopped == 1
  # A requestClose observer returning true keeps the app running.
  log.lines = @[]
  discard w.bindRequestClose(closeLogger(log, "keep", true))
  assert not w.dispatchKeyboard(27, 41, "", {})
  assert log.lines == @["keep"] and stopped == 1
  # A keyboard observer returning true comes first.
  log.lines = @[]
  discard w.bindKeyboard(keyLogger(log, "app key", true))
  assert w.dispatchKeyboard(27, 41, "", {})
  assert log.lines == @["app key"]

proc pixel(s: ptr SDL_Surface; x, y: int): array[3, uint8] =
  # One pixel of an RGB24 surface.
  let p = cast[ptr UncheckedArray[uint8]](s.pixels)
  let i = y * int(s.pitch) + x * 3
  result = [p[i], p[i + 1], p[i + 2]]

proc pushFinger(t: SDL_EventType; id: uint64; x, y: float32) =
  var ev = default(SDL_Event)
  ev.tfinger = SDL_TouchFingerEvent(`type`: t, touchID: 1, fingerID: SDL_FingerID(id),
    x: x, y: y, pressure: 1)
  assert pushEvent(ev)

proc pushButton(t: SDL_EventType; button: uint8; x, y: float32; which = SDL_MouseID(0)) =
  var ev = default(SDL_Event)
  ev.button = SDL_MouseButtonEvent(`type`: t, which: which, button: button,
    down: t == SDL_EVENT_MOUSE_BUTTON_DOWN, x: x, y: y)
  assert pushEvent(ev)

proc pushMotion(x, y: float32) =
  var ev = default(SDL_Event)
  ev.motion = SDL_MouseMotionEvent(`type`: SDL_EVENT_MOUSE_MOTION, which: 0, x: x, y: y)
  assert pushEvent(ev)

proc pushKey(t: SDL_EventType; key: SDL_Keycode) =
  var ev = default(SDL_Event)
  ev.key = SDL_KeyboardEvent(`type`: t, key: key, down: t == SDL_EVENT_KEY_DOWN)
  assert pushEvent(ev)

type Recorder = ref object of WidgetBase
  # The root widget: a blue box; it records its touches in window coordinates.
  # A bare WidgetBase (see Child): the window does not size it.
  lines: seq[string]

proc rec(r: Recorder; what: string; t: MotionEvent) =
  r.lines.add what & " " & t.device & " " & $int(t.x + 0.5) & "," & $int(t.y + 0.5) &
    " " & $t.button

method onTouchDown(r: Recorder; t: MotionEvent): bool =
  r.rec("down", t)
  t.grab(r)
  result = true

method onTouchMove(r: Recorder; t: MotionEvent): bool =
  if t.grabCurrent == RootRef(r): r.rec("move", t)
  result = true

method onTouchUp(r: Recorder; t: MotionEvent): bool =
  if t.grabCurrent == RootRef(r):
    r.rec("up", t)
    t.ungrab(r)
  result = true

block headless_run:
  # An app driven by SDL events, as on a device: it must open, draw, take a
  # screenshot, turn fingers and the mouse into touches, and stop on key 27
  # (Escape; Android's Back is mapped to it).
  removeFile(outDir() / "headless0001.png")
  Config.graphics.width = 320
  Config.graphics.height = 240
  Config.kivy.exitOnEscape = true
  let root = Recorder(canvas: newCanvas(), lines: @[])
  root.initWidgetBase()
  root.canvas.add newColor(0, 0, 1)
  root.canvas.add newRectangle((10.0, 10.0), (100.0, 50.0))
  let app = newApp()
  app.root = root
  let events = Log(lines: @[])
  discard app.bindStart(logger(events, "start", false))
  discard app.bindStop(logger(events, "stop", false))
  var keys: seq[string] = @[]
  var shot = ""
  var steps = 0
  discard Clock.scheduleInterval(proc (dt: float) {.closure.} =
    inc steps
    case steps
    of 1:
      Window.clearcolor = [1.0, 1.0, 1.0, 1.0]
      discard Window.bindKeyboard(proc (key, scancode: int; codepoint: string;
          modifiers: set[Modifier]): bool {.closure.} =
        keys.add $key
        result = false)
    of 2:
      shot = Window.screenshot(outDir() / "headless.png")
      # A finger: down at the top left quarter, moved, up. Each in its own
      # frame: a provider's events are dispatched after all its moves of
      # the frame, as in Kivy.
      pushFinger(SDL_EVENT_FINGER_DOWN, 7, 0.25, 0.25)
    of 3:
      pushFinger(SDL_EVENT_FINGER_MOTION, 7, 0.5, 0.25)
    of 4:
      pushFinger(SDL_EVENT_FINGER_UP, 7, 0.5, 0.25)
      # SDL's mouse events made from touches are ignored.
      pushButton(SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_BUTTON_LEFT, 5, 5, SDL_TOUCH_MOUSEID)
      pushButton(SDL_EVENT_MOUSE_BUTTON_UP, SDL_BUTTON_LEFT, 5, 5, SDL_TOUCH_MOUSEID)
    of 5:
      # The left button, dragged, and a right click.
      pushButton(SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_BUTTON_LEFT, 100, 40)
    of 6:
      pushMotion(110, 50)
    of 7:
      pushButton(SDL_EVENT_MOUSE_BUTTON_UP, SDL_BUTTON_LEFT, 110, 50)
      pushButton(SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_BUTTON_RIGHT, 20, 30)
    of 8:
      pushButton(SDL_EVENT_MOUSE_BUTTON_UP, SDL_BUTTON_RIGHT, 20, 30)
    of 9:
      pushKey(SDL_EVENT_KEY_DOWN, SDLK_LEFT)
      pushKey(SDL_EVENT_KEY_UP, SDLK_LEFT)
      pushKey(SDL_EVENT_KEY_DOWN, SDLK_ESCAPE)
    else:
      discard, 0.05)
  app.run()
  # Escape stopped the event loop, not the app: App.run's own stop
  # dispatches stop once.
  assert events.lines == @["start", "stop"], $events.lines
  assert Window.size == (320.0, 240.0)
  # The screenshot: RGB, white, with the blue box at (10, 10) y up.
  assert shot == outDir() / "headless0001.png", shot
  let img = IMG_Load(shot.toCString)
  assert img != nil
  let rgb = SDL_ConvertSurface(img, SDL_PIXELFORMAT_RGB24)
  assert rgb != nil and rgb.w == 320 and rgb.h == 240
  assert pixel(rgb, 50, 239 - 30) == [0'u8, 0, 255]
  assert pixel(rgb, 200, 100) == [255'u8, 255, 255]
  SDL_DestroySurface(rgb)
  SDL_DestroySurface(img)
  removeFile(shot)
  # Touches in window coordinates (y up, 0 to size - 1).
  assert root.lines == @[
    "down sdl 80,179 ", "move sdl 160,179 ", "up sdl 160,179 ",
    "down mouse 100,199 left", "move mouse 110,189 left", "up mouse 110,189 left",
    "down mouse 20,209 right", "up mouse 20,209 right"], $root.lines
  # Left is Kivy's 276; Escape (27) closed the app and the window.
  assert keys == @["276", "27"], $keys
  assert not Window.initialized
  assert EventLoop.status == loopClosed
  assert getRunningApp() == nil
  assert Window.children.len == 0
