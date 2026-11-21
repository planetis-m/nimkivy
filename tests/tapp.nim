# Ports kivy/tests/test_app.py (ACCEPTANCE.md, layer 5): test_graphics_app,
# and the App lifecycle the kiosk relies on. test_basic_app needs Label and
# is finished in layer 7. Each app stops itself from a Clock callback, as
# Kivy's UnitKivyApp does when the test is done.

import std/[assertions, os, syncio]
from std/dirs import createDir
from std/files import tryRemoveFile
from std/paths import path
import nimkivy/[app, clock]
import nimkivy/sdl3/[sdl, image]
import nimkivy/graphics/[instructions, context_instructions, vertex_instructions]
import stubs

type
  GraphicsApp = ref object of App
    shot: string

  LifecycleApp = ref object of App
    log: seq[string]
    builds: int

proc shotPath(): string =
  var dir = "tests/out/tapp"
  try:
    dir = getCurrentDir() / dir
    createDir(path(dir))
  except:
    quit "cannot create " & dir
  result = dir / "graphics.png"
  discard tryRemoveFile(path(dir / "graphics0001.png"))

let GraphicsAppClass = newDispatcherClass("TestApp", AppClass)

method build(a: GraphicsApp): nil WidgetBase =
  # test_app.py graphics_app
  let widget = newStubWidget()
  widget.canvas.add newColor(1, 0, 0, 1)
  widget.canvas.add newRectangle((0.0, 0.0), (100.0, 100.0))
  widget.canvas.add newColor(0, 1, 0, 1)
  widget.canvas.add newRectangle((100.0, 0.0), (100.0, 100.0))
  discard Clock.scheduleOnce(proc (dt: float) {.closure.} =
    a.shot = Window.screenshot(shotPath())
    a.stop(), 0.2)
  result = widget

proc rgbAt(s: ptr SDL_Surface; x, y: int): (int, int, int) =
  # The pixel at Kivy's (x, y), y up, of an RGB24 surface.
  let p = cast[ptr UncheckedArray[uint8]](s.pixels)
  let i = (int(s.h) - 1 - y) * int(s.pitch) + x * 3
  result = (int(p[i]), int(p[i + 1]), int(p[i + 2]))

block test_graphics_app:
  # kivy/tests/test_app.py::test_graphics_app. Kivy draws the widget's
  # canvas into an Fbo; here the window's screenshot is read.
  let a = GraphicsApp(cls: GraphicsAppClass, shot: "")
  a.initApp()
  a.run()
  assert a.shot.len > 0
  let img = IMG_Load(a.shot.toCString)
  assert img != nil, fromCString(SDL_GetError())
  let rgb = SDL_ConvertSurface(img, SDL_PIXELFORMAT_RGB24)
  assert rgb != nil
  let (r1, g1, b1) = rgbAt(rgb, 50, 50)
  let (r2, g2, b2) = rgbAt(rgb, 150, 50)
  assert g1 == 0 and b1 == 0 and r2 == 0 and b2 == 0
  assert r1 > 50 and g2 > 50
  SDL_DestroySurface(rgb)
  SDL_DestroySurface(img)
  discard tryRemoveFile(path(a.shot))

let LifecycleAppClass = newDispatcherClass("LifecycleApp", AppClass)

method build(a: LifecycleApp): nil WidgetBase =
  inc a.builds
  a.log.add "build " & $Window.width & "x" & $Window.height
  discard Clock.scheduleOnce(proc (dt: float) {.closure.} = a.stop(), 0.1)
  result = newStubWidget()

proc logEvent(a: LifecycleApp; name: string): EventCallback =
  result = proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    a.log.add name
    result = false

block app_lifecycle:
  # App.run: build after the window opened, on_start, then stop() from a
  # Clock callback: on_stop, and on_stop again when run returns, as Kivy's
  # App.run calls _stop after runTouchApp (checked with Kivy 2.3.2).
  let a = LifecycleApp(cls: LifecycleAppClass, log: @[], builds: 0)
  a.initApp()
  assert getRunningApp() == App(a)
  for name in ["on_start", "on_stop"]:
    a.bind(name, a.logEvent(name))
  a.run()
  assert a.builds == 1
  assert a.log == @["build 800.0x600.0", "on_start", "on_stop", "on_stop"], $a.log
  assert getRunningApp() == nil
  let root = a.root
  assert Window.children.len == 0 and root != nil and root.parent == nil
  assert a.getApplicationName() == "Lifecycle" and a.name == "lifecycle"
  # WindowSDL.set_title shows the title but leaves Window.title as it is.
  assert Window.getProperty("title").str == "Kivy"
  assert EventLoop.status == "closed"

block app_on_pause_and_title:
  # on_pause returns true by default (the app survives Android's pause);
  # an observer can refuse.
  let a = newApp()
  assert a.dispatch("on_pause")
  a.bind("on_pause", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} = false)
  assert a.dispatch("on_pause")     # an observer's false does not stop the default
  assert a.getApplicationName() == ""
  a.title = "PHILOSYKOS"
  assert a.title == "PHILOSYKOS" and a.getApplicationName() == "PHILOSYKOS"
