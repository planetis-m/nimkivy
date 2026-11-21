## The SDL3 window: Kivy's `kivy/core/window/window_sdl2.py` and
## `_window_sdl2.pyx`, and the mouse provider of
## `kivy/input/providers/mouse.py`.
##
## `Window` is the application's one window. Its system window opens when
## the event loop needs it (`base.ensureWindow`, called by `App.run` and
## `runTouchApp`), not when this module is loaded as Kivy's does on import:
## Kivy programs set `Config` before importing the window, and a Nim
## program's own code runs only after every module is loaded.
##
## `mainloop` reads the SDL events of one frame: a mouse button and the mouse
## wheel become `on_mouse_down`/`on_mouse_up` (the mouse provider makes
## touches of them), a mouse move with a button held `on_mouse_move`, SDL's
## fingers become touches through the window's own provider, keys become
## `on_key_down`, `on_keyboard` and `on_key_up` with Kivy's key codes, and
## the app lifecycle events call the running App's `on_pause` and
## `on_resume`. SDL's mouse events made from touches are ignored, so a finger
## makes exactly one touch. Drawing is the canvas tree through
## `graphics/renderer` on an SDL renderer.

import std/[strutils, syncio, tables]
from std/unicode import Rune, toUTF8
import ../../[properties, clock, config, metrics]
import ../../sdl3/[sdl, image]
import ../../graphics/[instructions, renderer]
import ../../input/motionevent
import ../window

export window

type
  SDLMotionEvent* = ref object of MotionEvent
    ## A finger (window_sdl2.py SDL2MotionEvent): args are x, y, pressure.
    pressure*: float

  SDLMotionEventProvider* = ref object of MotionEventProvider
    ## Turns the window's finger events into touches
    ## (window_sdl2.py SDL2MotionEventProvider).
    queue: seq[(string, SDL_FingerID, float, float, float)]
    touchmap: Table[SDL_FingerID, nil SDLMotionEvent]

  MouseMotionEvent* = ref object of MotionEvent
    ## A mouse touch (mouse.py MouseMotionEvent): args are x, y, button.
    multitouchSim*: bool

  MouseMotionEventProvider* = ref object of MotionEventProvider
    ## Turns the window's mouse events into touches (mouse.py
    ## MouseMotionEventProvider), without multitouch simulation or hover.
    window: WindowSDL
    waitingEvent: seq[InputEvent]
    touches: seq[MouseMotionEvent]    # in creation order, like Kivy's dict
    counter: int
    currentDrag: nil MouseMotionEvent
    disableMultitouch*: bool
    multitouchOnDemand*: bool
    uids: seq[(string, int)]

  WindowSDL* = ref object of WindowBase
    ## The SDL3 window (window_sdl2.py WindowSDL).
    sdlWindow: nil SDL_Window
    sdlRenderer: nil SDL_Renderer
    renderer: nil Renderer
    pauseLoop: bool
    mouseX, mouseY: float
    mouseButtonsDown: seq[uint8]
    keyMap: Table[uint32, int]
    commandKeys: seq[int]
    doResizeEv: nil ClockEvent
    motionProvider*: SDLMotionEventProvider  ## the finger provider; `base` adds it

proc log(level, msg: string) =
  # Kivy's Logger, on stderr in its layout.
  stderr.writeLine "[" & alignLeft(level, 7) & "] [WindowSDL   ] " & msg

# ------------------------------------------------------------------ fingers

method depack*(me: SDLMotionEvent; args: seq[Value]) =
  ## x, y and pressure, normalized.
  me.sx = args[0].num
  me.sy = args[1].num
  me.pressure = args[2].num
  procCall depack(MotionEvent(me), args)

proc newSDLMotionEvent(device, id: string; x, y, pressure: float): SDLMotionEvent =
  # window_sdl2.py SDL2MotionEvent.__init__
  result = SDLMotionEvent(pressure: 0)
  result.initMotionEvent(device, id, @[toValue(x), toValue(y), toValue(pressure)],
    isTouch = true, typeId = "touch")
  result.profile = @["pos", "pressure"]

proc newSDLMotionEventProvider(): SDLMotionEventProvider =
  SDLMotionEventProvider(device: "sdl", queue: @[],
    touchmap: initTable[SDL_FingerID, nil SDLMotionEvent]())

proc push(p: SDLMotionEventProvider; action: string; fid: SDL_FingerID; x, y, pressure: float) =
  # The window queues a finger event (`q.appendleft`).
  p.queue.add (action, fid, x, y, pressure)

method update*(p: SDLMotionEventProvider): seq[InputEvent] =
  ## Makes or moves a touch per queued finger event, oldest first.
  ## window_sdl2.py SDL2MotionEventProvider.update
  result = @[]
  while p.queue.len > 0:
    let (action, fid, x, sdlY, pressure) = p.queue[0]
    p.queue.delete(0)
    let y = 1 - sdlY
    let existing = p.touchmap.getOrDefault(fid, nil)
    let me = if existing == nil: newSDLMotionEvent("sdl", $fid, x, y, pressure)
      else: existing
    if existing == nil:
      p.touchmap[fid] = me
    else:
      me.move(@[toValue(x), toValue(y), toValue(pressure)])
    if action == "fingerdown":
      result.add ("begin", MotionEvent(me))
    elif action == "fingerup":
      me.updateTimeEnd()
      result.add ("end", MotionEvent(me))
      p.touchmap.del(fid)
    else:
      result.add ("update", MotionEvent(me))

# ------------------------------------------------------------------ mouse

method depack*(me: MouseMotionEvent; args: seq[Value]) =
  ## x and y normalized, then the button and whether multitouch is
  ## simulated. mouse.py MouseMotionEvent.depack
  me.sx = args[0].num
  me.sy = args[1].num
  if me.isTouch:
    if me.profile.len == 0:
      me.profile.add "pos"
      me.profile.add "button"
    if args.len >= 3:
      me.button = args[2].str
    if args.len == 4:
      me.multitouchSim = args[3].flag
      me.profile.add "multitouch_sim"
  else:
    if me.profile.len == 0:
      me.profile.add "pos"
  procCall depack(MotionEvent(me), args)

proc newMouseMotionEventProvider*(device, args: string; window: WindowSDL): MouseMotionEventProvider =
  ## The mouse provider for Config's `input` value `mouse,<args>`.
  ## mouse.py MouseMotionEventProvider.__init__
  result = MouseMotionEventProvider(device: device, window: window, waitingEvent: @[],
    touches: @[], counter: 0, currentDrag: nil, disableMultitouch: false,
    multitouchOnDemand: false, uids: @[])
  for part in args.split(','):
    let arg = part.strip()
    case arg
    of "": discard
    of "disable_multitouch": result.disableMultitouch = true
    of "multitouch_on_demand": result.multitouchOnDemand = true
    of "disable_on_activity", "disable_hover":
      discard    # other providers and hover events are out of scope
    else:
      stderr.writeLine "[ERROR  ] [Mouse       ] unknown parameter <" & arg & ">"

proc modifiersOf(v: Value): seq[string] =
  result = @[]
  for m in v.items: result.add m.str

proc toNormalizedPos(w: WindowSDL; x, y: float): (float, float) =
  # WindowBase.to_normalized_pos
  let (sw, sh) = w.systemSize
  let xMax = sw - 1.0
  let yMax = sh - 1.0
  let nx = if xMax > 0: x / xMax else: 0.0
  let ny = if yMax > 0: y / yMax else: 0.0
  result = (nx, ny)

proc findTouch(p: MouseMotionEventProvider; x, y: float): nil MouseMotionEvent =
  # mouse.py find_touch: a touch left at about this position.
  let factor = 10.0 / p.window.systemSize[0]
  result = nil
  for i in 0 ..< p.touches.len:
    let t = p.touches[i]
    if abs(x - t.sx) < factor and abs(y - t.sy) < factor:
      return t

proc createTouch(p: MouseMotionEventProvider; nx, ny: float; isDoubleTap, doGraphics: bool;
    button: string): MouseMotionEvent =
  # mouse.py create_touch. Multitouch simulation (the red dot) is out of
  # scope: `do_graphics` only adds the `multitouch_sim` profile entry.
  inc p.counter
  let eventId = p.device & $p.counter
  var args = @[toValue(nx), toValue(ny), toValue(button)]
  if doGraphics:
    args.add toValue(not p.multitouchOnDemand)
  let t = MouseMotionEvent(multitouchSim: false)
  t.initMotionEvent(p.device, eventId, args, isTouch = true, typeId = "touch")
  p.currentDrag = t
  p.touches.add t
  p.waitingEvent.add ("begin", MotionEvent(t))
  result = t

proc removeTouch(p: MouseMotionEventProvider; t: MouseMotionEvent) =
  # mouse.py remove_touch
  let i = p.touches.find(t)
  if i >= 0:
    p.touches.delete(i)
    t.updateTimeEnd()
    p.waitingEvent.add ("end", MotionEvent(t))

proc onMouseMotion(p: MouseMotionEventProvider; x, y: float) =
  # mouse.py on_mouse_motion (alt_touch is part of the simulation)
  var (nx, ny) = p.window.toNormalizedPos(x, y)
  ny = 1.0 - ny
  let t = p.currentDrag
  if t != nil:
    t.move(@[toValue(nx), toValue(ny)])
    p.waitingEvent.add ("update", MotionEvent(t))

proc onMousePress(p: MouseMotionEventProvider; x, y: float; button: string;
    modifiers: seq[string]) =
  # mouse.py on_mouse_press
  var (nx, ny) = p.window.toNormalizedPos(x, y)
  ny = 1.0 - ny
  let found = p.findTouch(nx, ny)
  if found != nil:
    p.currentDrag = found
  else:
    let isDoubleTap = "shift" in modifiers
    let doGraphics = not p.disableMultitouch and (button != "left" or "ctrl" in modifiers)
    discard p.createTouch(nx, ny, isDoubleTap, doGraphics, button)

proc onMouseRelease(p: MouseMotionEventProvider; x, y: float; button: string;
    modifiers: seq[string]) =
  # mouse.py on_mouse_release. Without multitouch simulation every touch
  # ends when its button is released (Kivy keeps a right-click touch alive
  # as a simulated finger unless `multitouch_on_demand`).
  if button == "all":
    let all = p.touches
    for t in all: p.removeTouch(t)
    p.currentDrag = nil
  let t = p.currentDrag
  if t != nil:
    p.removeTouch(t)
    p.currentDrag = nil

method start*(p: MouseMotionEventProvider) =
  ## Listens to the window's mouse events. mouse.py start
  let w = p.window
  p.uids = @[]
  p.uids.add ("on_mouse_down", w.fbind("on_mouse_down",
    proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
      p.onMousePress(a[0].num, a[1].num, a[2].str, modifiersOf(a[3]))
      result = false))
  p.uids.add ("on_mouse_move", w.fbind("on_mouse_move",
    proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
      p.onMouseMotion(a[0].num, a[1].num)
      result = false))
  p.uids.add ("on_mouse_up", w.fbind("on_mouse_up",
    proc (d: EventDispatcher; a: seq[Value]): bool {.closure.} =
      p.onMouseRelease(a[0].num, a[1].num, a[2].str, modifiersOf(a[3]))
      result = false))

method stop*(p: MouseMotionEventProvider) =
  ## Stops listening. mouse.py stop
  for i in 0 ..< p.uids.len:
    let (name, uid) = p.uids[i]
    p.window.unbindUid(name, uid)
  p.uids = @[]

method update*(p: MouseMotionEventProvider): seq[InputEvent] =
  ## The waiting events, oldest first. mouse.py update
  result = p.waitingEvent
  p.waitingEvent = @[]

# ------------------------------------------------------------------ WindowSDL

const
  # window_sdl2.py: Kivy's key codes for SDL's (key_map) and the keys that
  # have no codepoint (command_keys).
  CommandKeys = [27, 9, 8, 13, 127, 271, 273, 274, 275, 276, 278, 279, 280, 281]

proc newKeyMap(): Table[uint32, int] =
  result = initTable[uint32, int]()
  for (k, v) in [(SDLK_LEFT, 276), (SDLK_RIGHT, 275), (SDLK_UP, 273), (SDLK_DOWN, 274),
      (SDLK_HOME, 278), (SDLK_END, 279), (SDLK_PAGEDOWN, 281), (SDLK_PAGEUP, 280),
      (SDLK_RSHIFT, 303), (SDLK_LSHIFT, 304), (SDLK_LGUI, 309), (SDLK_LCTRL, 305),
      (SDLK_RCTRL, 306), (SDLK_LALT, 308), (SDLK_RALT, 307), (SDLK_CAPSLOCK, 301),
      (SDLK_INSERT, 277), (SDLK_F1, 282), (SDLK_F2, 283), (SDLK_F3, 284), (SDLK_F4, 285),
      (SDLK_F5, 286), (SDLK_F6, 287), (SDLK_F7, 288), (SDLK_F8, 289), (SDLK_F9, 290),
      (SDLK_F10, 291), (SDLK_F11, 292), (SDLK_F12, 293), (SDLK_F13, 294), (SDLK_F14, 295),
      (SDLK_F15, 296), (SDLK_NUMLOCKCLEAR, 300), (SDLK_KP_DIVIDE, 267),
      (SDLK_KP_MULTIPLY, 268), (SDLK_KP_MINUS, 269), (SDLK_KP_PLUS, 270),
      (SDLK_KP_ENTER, 271), (SDLK_KP_PERIOD, 266), (SDLK_KP_0, 256), (SDLK_KP_1, 257),
      (SDLK_KP_2, 258), (SDLK_KP_3, 259), (SDLK_KP_4, 260), (SDLK_KP_5, 261),
      (SDLK_KP_6, 262), (SDLK_KP_7, 263), (SDLK_KP_8, 264), (SDLK_KP_9, 265)]:
    result[uint32(k)] = v
  when defined(android):
    # Map the Android back button to Escape.
    result[uint32(SDLK_AC_BACK)] = 27

let WindowSDLClass* = newDispatcherClass("WindowSDL", WindowBaseClass)
  ## The class of `WindowSDL`.

proc newWindowSDL*(): WindowSDL =
  ## The window object, before its system window exists.
  ## window_sdl2.py WindowSDL.__init__
  result = WindowSDL(cls: WindowSDLClass, canvas: newCanvas(), sdlWindow: nil,
    sdlRenderer: nil, renderer: nil, pauseLoop: false, mouseX: -1, mouseY: -1,
    mouseButtonsDown: @[], keyMap: newKeyMap(), commandKeys: @CommandKeys,
    doResizeEv: nil, motionProvider: newSDLMotionEventProvider())
  result.initWindowBase()

proc windowSize(w: WindowSDL): (float, float) =
  # _window_sdl2.pyx window_size: the size in window coordinates.
  var ww = 0.cint
  var wh = 0.cint
  let win = w.sdlWindow
  if win != nil:
    discard SDL_GetWindowSize(win, addr ww, addr wh)
  result = (float(ww), float(wh))

method glSize*(w: WindowSDL): (float, float) =
  ## The drawable size in pixels.
  let win = w.sdlWindow
  if win == nil:
    result = procCall glSize(WindowBase(w))
  else:
    var pw = 0.cint
    var ph = 0.cint
    discard SDL_GetWindowSizeInPixels(win, addr pw, addr ph)
    result = (float(pw), float(ph))

proc updateDensityAndDpi(w: WindowSDL) =
  # window_sdl2.py _update_density_and_dpi, and the platform values that
  # Kivy's Metrics reads on Android (Hardware.getDPI, scaledDensity).
  let (gw, _) = w.glSize()
  let sw = w.getProperty("_size").toFloats[0]
  let density = if sw > 0: gw / sw else: 1.0
  w.setProperty("_density", toValue(density))
  when defined(android):
    let win = w.sdlWindow
    var scale = 1.0
    if win != nil:
      let s = SDL_GetDisplayContentScale(SDL_GetDisplayForWindow(win))
      if s > 0: scale = float(s)
    # GAP: on Android the density is SDL's display content scale and the dpi
    # 160 times it, where Kivy reads Android's scaledDensity (which includes
    # the user's font scale) and densityDpi, and the font scale stays 1,
    # because SDL3 exposes only the content scale and JNI is out of scope
    Metrics.platformDensity = scale
    Metrics.platformDpi = 160 * scale
    w.setProperty("dpi", toValue(160 * scale))
  else:
    w.setProperty("dpi", toValue(density * 96))
    Metrics.platformDpi = density * 96

method createWindow*(w: WindowSDL) =
  ## Opens the system window the first time, with the size, fullscreen and
  ## resizable settings of Config; later, resizes it to `system_size`.
  ## window_sdl2.py WindowSDL.create_window and _window_sdl2.pyx setup_window
  if not w.initialized:
    # Kivy's window object reads Config when the program imports it; here
    # the object exists from the start, so Config is read again now.
    let width = Config.getint("graphics", "width")
    let height = Config.getint("graphics", "height")
    var flags = SDL_WINDOW_HIGH_PIXEL_DENSITY
    if Config.getboolean("graphics", "resizable"):
      flags = flags or SDL_WINDOW_RESIZABLE
    when defined(android):
      # p4a's fullscreen build (the kiosk's buildozer.spec has fullscreen = 1).
      flags = flags or SDL_WINDOW_FULLSCREEN
    else:
      let fullscreen = Config.getdefault("graphics", "fullscreen", "0").toLowerAscii
      if fullscreen in ["auto", "true", "1", "yes"]:
        flags = flags or SDL_WINDOW_FULLSCREEN
    discard SDL_SetHint(SDL_HINT_ANDROID_TRAP_BACK_BUTTON, "1")
    # A finger is a touch of its own: no mouse events made from touches.
    discard SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0")
    if not SDL_Init(SDL_INIT_VIDEO):
      quit "[CRITICAL] [WindowSDL   ] Unable to initialize SDL: " & fromCString(SDL_GetError())
    var title = w.getProperty("title").str
    let win = SDL_CreateWindow(title.toCString, cint(width), cint(height), flags)
    if win == nil:
      quit "[CRITICAL] [WindowSDL   ] Unable to create the window: " &
        fromCString(SDL_GetError())
    w.sdlWindow = win
    let r = SDL_CreateRenderer(win, nil)
    if r == nil:
      quit "[CRITICAL] [WindowSDL   ] Unable to create a renderer: " &
        fromCString(SDL_GetError())
    w.sdlRenderer = r
    w.renderer = newRenderer(r)
    let (sw, sh) = w.windowSize()
    w.setProperty("system_size", toValue([sw, sh]))
    w.updateDensityAndDpi()
  else:
    let win = w.sdlWindow
    if win != nil:
      # _window_sdl2.pyx resize_window
      let s = w.getProperty("system_size").toFloats
      if w.windowSize() != (s[0], s[1]):
        discard SDL_SetWindowSize(win, cint(s[0]), cint(s[1]))
  procCall createWindow(WindowBase(w))
  if not w.initialized:
    w.initialized = true
    # WindowBase.__init__: dpi changes after the window exists reset Metrics.
    discard w.fbind("dpi", proc (d: EventDispatcher; v: Value) {.closure.} =
      WindowBase(d).resetMetricsDpi())

method setTitle*(w: WindowSDL; title: string) =
  ## Shows `title` on the system window (window_sdl2.py set_title, which,
  ## unlike WindowBase's, leaves the `title` property as it is).
  let win = w.sdlWindow
  if win != nil:
    var t = title
    discard SDL_SetWindowTitle(win, t.toCString)

method clear*(w: WindowSDL) =
  ## Fills the window with `clearcolor`.
  let r = w.renderer
  if r != nil:
    r.clear(w.clearcolor)

method drawCanvas*(w: WindowSDL) =
  ## Draws the window's canvas tree.
  let r = w.renderer
  if r != nil:
    r.draw(w.canvas)

method flip*(w: WindowSDL) =
  ## Shows the frame drawn.
  let r = w.renderer
  if r != nil:
    r.present()

method close*(w: WindowSDL) =
  ## Destroys the system window and shuts SDL down, then dispatches
  ## `on_close`. window_sdl2.py close and _window_sdl2.pyx teardown_window
  let r = w.sdlRenderer
  if r != nil:
    SDL_DestroyRenderer(r)
  let win = w.sdlWindow
  if win != nil:
    SDL_DestroyWindow(win)
  w.renderer = nil
  w.sdlRenderer = nil
  w.sdlWindow = nil
  SDL_Quit()
  procCall close(WindowBase(w))
  w.initialized = false

method screenshot*(w: WindowSDL; name = "screenshot{:04d}.png"): string =
  ## Saves the window's picture as an RGB PNG and returns its path: `name`
  ## numbered as WindowBase.screenshot does. window_sdl2.py screenshot
  result = procCall screenshot(WindowBase(w), name)
  let r = w.renderer
  if r == nil:
    return ""
  # Kivy reads the GL buffer it just drew. SDL's frame is not readable after
  # SDL_RenderPresent, so the frame is drawn again, as on_draw does, and
  # read before it is shown.
  w.clear()
  w.drawCanvas()
  let shot = r.readPixels()
  if shot == nil:
    log("ERROR", "Unable to read the frame: " & fromCString(SDL_GetError()))
    return ""
  let rgb = SDL_ConvertSurface(shot, SDL_PIXELFORMAT_RGB24)
  SDL_DestroySurface(shot)
  if rgb == nil:
    log("ERROR", "Unable to convert the frame: " & fromCString(SDL_GetError()))
    return ""
  if not IMG_SavePNG(rgb, result.toCString):
    log("ERROR", "Unable to save " & result & ": " & fromCString(SDL_GetError()))
  SDL_DestroySurface(rgb)

proc fixMousePos(w: WindowSDL; x, y: float): (float, float) =
  # window_sdl2.py _fix_mouse_pos (mouse_pos, for hover, is out of scope)
  (x, y)

proc modifiersValue(w: WindowSDL): Value =
  var items: seq[Value] = @[]
  for i in 0 ..< w.modifiers.len: items.add toValue(w.modifiers[i])
  result = toValue(items)

proc hasMod(mods, m: SDL_Keymod): bool {.inline.} =
  uint16(mods and m) != 0

proc addOnce(s: var seq[string]; name: string) =
  # Python's set.add, keeping the order of first addition.
  if name notin s: s.add name

proc updateModifiers(w: WindowSDL; mods: SDL_Keymod; hasKey: bool; key: int) =
  # window_sdl2.py _update_modifiers. Like Kivy, it compares the key code
  # with the modifier masks.
  var modifiers: seq[string] = @[]
  if hasMod(mods, SDL_KMOD_RSHIFT or SDL_KMOD_LSHIFT): modifiers.addOnce "shift"
  if hasMod(mods, SDL_KMOD_RALT or SDL_KMOD_LALT or SDL_KMOD_MODE): modifiers.addOnce "alt"
  if hasMod(mods, SDL_KMOD_RCTRL or SDL_KMOD_LCTRL): modifiers.addOnce "ctrl"
  if hasMod(mods, SDL_KMOD_RGUI or SDL_KMOD_LGUI): modifiers.addOnce "meta"
  if hasMod(mods, SDL_KMOD_NUM): modifiers.addOnce "numlock"
  if hasMod(mods, SDL_KMOD_CAPS): modifiers.addOnce "capslock"
  if hasKey:
    if key in [0x0002, 0x0001]: modifiers.addOnce "shift"
    if key in [0x0200, 0x0100, 0x4000]: modifiers.addOnce "alt"
    if key in [0x0080, 0x0040]: modifiers.addOnce "ctrl"
    if key in [0x0800, 0x0400]: modifiers.addOnce "meta"
    if key == 0x1000: modifiers.addOnce "numlock"
    if key == 0x2000: modifiers.addOnce "capslock"
  w.modifiers = modifiers

proc codepoint(key: int): Value =
  # The key's character, as Kivy's unichr(key) with an encodable result; None
  # for codes beyond Unicode and for surrogates.
  if key >= 0 and key <= 0x10FFFF and not (key >= 0xD800 and key <= 0xDFFF):
    result = toValue(Rune(key).toUTF8)
  else:
    result = noneValue()

proc doResize(w: WindowSDL) =
  # window_sdl2.py _do_resize
  let s = w.getProperty("_size").toFloats
  let win = w.sdlWindow
  if win != nil and w.windowSize() != (s[0], s[1]):
    discard SDL_SetWindowSize(win, cint(s[0]), cint(s[1]))
  let size = w.size
  discard w.dispatch("on_pre_resize", toValue(size[0]), toValue(size[1]))

proc appEvent(w: WindowSDL; t: SDL_EventType) =
  # window_sdl2.py _event_filter, for the app lifecycle. Kivy runs it in
  # SDL's event filter, as the event is pushed; here it runs when the event
  # is read.
  # GAP: on_pause and on_resume run when the event is read from the queue,
  # not in an SDL event filter as the event happens, so on Android on_pause
  # can come only after the app is back in the foreground, because nimkivy
  # installs no event filter (its callback runs on another thread)
  if t == SDL_EVENT_TERMINATING:
    let q = w.quitEventLoop
    if q != nil: q()
  elif t == SDL_EVENT_WILL_ENTER_BACKGROUND:
    let app = w.runningApp
    if app == nil:
      log("INFO", "No running App found, pause.")
    elif not app.dispatch("on_pause"):
      # GAP: on Android an app whose on_pause returns false is stopped like
      # on the desktop, where Kivy calls mActivity.finishAndRemoveTask(),
      # because SDL3 has no call for it and JNI is out of scope
      log("INFO", "App doesn't support pause mode, stop.")
      let stop = w.stopTouchApp
      if stop != nil: stop()
      return
    w.pauseLoop = true
  elif t == SDL_EVENT_DID_ENTER_FOREGROUND:
    if w.pauseLoop:
      w.pauseLoop = false
      let app = w.runningApp
      if app != nil:
        discard app.dispatch("on_resume")

proc mouseButtonName(button: uint8): string =
  case button
  of 3: "right"
  of 2: "middle"
  of 4: "mouse4"
  of 5: "mouse5"
  else: "left"

proc onKeyEvent(w: WindowSDL; ev: SDL_KeyboardEvent; down: bool) =
  # window_sdl2.py mainloop, keydown and keyup
  var key = int(uint32(ev.key))
  key = w.keyMap.getOrDefault(uint32(ev.key), key)
  if down: w.updateModifiers(ev.`mod`, true, key)
  else: w.updateModifiers(ev.`mod`, false, 0)
  var kstr = noneValue()
  if key notin w.commandKeys:
    kstr = codepoint(key)
  let scancode = toValue(int(ev.scancode))
  if not down:
    discard w.dispatch("on_key_up", toValue(key), scancode)
  elif not w.dispatch("on_key_down", toValue(key), scancode, kstr, w.modifiersValue()):
    discard w.dispatch("on_keyboard", toValue(key), scancode, kstr, w.modifiersValue())

proc pumpPaused(w: WindowSDL): bool =
  # window_sdl2.py mainloop, while paused: wait for events and drop all but
  # the lifecycle ones. False when the event loop must stop.
  result = true
  var ev = default(SDL_Event)
  while w.pauseLoop:
    if not SDL_WaitEvent(addr ev): return true
    let t = SDL_EventType(ev.`type`)
    if t == SDL_EVENT_TERMINATING or t == SDL_EVENT_DID_ENTER_FOREGROUND or
        t == SDL_EVENT_WILL_ENTER_BACKGROUND:
      w.appEvent(t)
      if t == SDL_EVENT_TERMINATING: return false

proc mainloop*(w: WindowSDL) =
  ## Reads and dispatches the SDL events that arrived since the last frame.
  ## window_sdl2.py WindowSDL.mainloop and _window_sdl2.pyx poll
  if not w.pumpPaused(): return
  var ev = default(SDL_Event)
  while SDL_PollEvent(addr ev):
    let t = SDL_EventType(ev.`type`)
    if t == SDL_EVENT_QUIT:
      if not w.dispatch("on_request_close"):
        let q = w.quitEventLoop
        if q != nil: q()
        break
    elif t == SDL_EVENT_TERMINATING or t == SDL_EVENT_WILL_ENTER_BACKGROUND or
        t == SDL_EVENT_DID_ENTER_FOREGROUND:
      w.appEvent(t)
    elif t == SDL_EVENT_FINGER_DOWN or t == SDL_EVENT_FINGER_UP or
        t == SDL_EVENT_FINGER_MOTION:
      # Every platform: SCOPE.md makes each SDL finger a touch (Kivy does it
      # on Android and iOS and leaves desktop touch screens to other
      # providers).
      let f = ev.tfinger
      let action = if t == SDL_EVENT_FINGER_DOWN: "fingerdown"
        elif t == SDL_EVENT_FINGER_UP: "fingerup"
        else: "fingermotion"
      w.motionProvider.push(action, f.fingerID, float(f.x), float(f.y), float(f.pressure))
    elif t == SDL_EVENT_MOUSE_MOTION:
      let m = ev.motion
      if m.which != SDL_TOUCH_MOUSEID:
        let (x, y) = w.fixMousePos(float(m.x), float(m.y))
        w.mouseX = x
        w.mouseY = y
        # Don't dispatch motion if no button is pressed.
        if w.mouseButtonsDown.len > 0:
          discard w.dispatch("on_mouse_move", toValue(x), toValue(y), w.modifiersValue())
    elif t == SDL_EVENT_MOUSE_BUTTON_DOWN or t == SDL_EVENT_MOUSE_BUTTON_UP:
      let b = ev.button
      if b.which != SDL_TOUCH_MOUSEID:
        let (x, y) = w.fixMousePos(float(b.x), float(b.y))
        w.mouseX = x
        w.mouseY = y
        let btn = mouseButtonName(b.button)
        var eventname = "on_mouse_down"
        if t == SDL_EVENT_MOUSE_BUTTON_DOWN:
          if b.button notin w.mouseButtonsDown: w.mouseButtonsDown.add b.button
        else:
          eventname = "on_mouse_up"
          let i = w.mouseButtonsDown.find(b.button)
          if i >= 0: w.mouseButtonsDown.delete(i)
        discard w.dispatch(eventname, toValue(x), toValue(y), toValue(btn), w.modifiersValue())
    elif t == SDL_EVENT_MOUSE_WHEEL:
      let m = ev.wheel
      # Kivy's poll: 'down' when y > 0, 'up' when y < 0, and the same
      # reversed naming for x; events without an offset are ignored.
      var btn = ""
      if m.x != 0: btn = if m.x > 0: "scrollleft" else: "scrollright"
      elif m.y != 0: btn = if m.y > 0: "scrolldown" else: "scrollup"
      let (sw, sh) = w.windowSize()
      let mx = float(m.mouse_x)
      let my = float(m.mouse_y)
      # _collide_and_dispatch_cursor_enter: ignore the title bar and edges.
      if btn.len > 0 and m.which != SDL_TOUCH_MOUSEID and 0 <= mx and mx < sw and
          0 <= my and my < sh:
        (w.mouseX, w.mouseY) = w.fixMousePos(mx, my)
        discard w.dispatch("on_mouse_down", toValue(w.mouseX), toValue(w.mouseY), toValue(btn),
          w.modifiersValue())
        discard w.dispatch("on_mouse_up", toValue(w.mouseX), toValue(w.mouseY), toValue(btn),
          w.modifiersValue())
    elif t == SDL_EVENT_WINDOW_RESIZED:
      let (sw, sh) = w.windowSize()
      w.setProperty("_size", toValue([sw, sh]))
      # Not a trigger: the resize event is delayed.
      let pending = w.doResizeEv
      if pending == nil:
        w.doResizeEv = Clock.scheduleOnce(proc (dt: float) {.closure.} = w.doResize(), 0.1)
      else:
        pending.trigger()
    elif t == SDL_EVENT_WINDOW_EXPOSED:
      w.canvas.askUpdate()
    elif t == SDL_EVENT_KEY_DOWN or t == SDL_EVENT_KEY_UP:
      w.onKeyEvent(ev.key, t == SDL_EVENT_KEY_DOWN)

proc pushEvent*(ev: SDL_Event): bool =
  ## Puts an SDL event in the queue, as the system does; for tests that
  ## drive the window headless (Kivy's tests post touches to the event loop
  ## instead).
  var e = ev
  result = SDL_PushEvent(addr e)

let Window* = newWindowSDL()
  ## The application's window. Its system window opens when the event loop
  ## needs it (`base.ensureWindow`).
