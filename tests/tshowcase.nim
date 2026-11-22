# The whole-stack check (LAYERS.md, layer 10): examples/showcase.nim, an
# App with every phase-1 piece, walked through by a script. The script runs
# from a Clock interval inside the real event loop (App.run) and feeds SDL
# finger events (SDL_PushEvent), so the touches take the same path as on a
# device: SDL queue, window, input provider, EventLoop, widgets. Each step
# waits a given time after the previous one, then acts and checks what is
# shown. Headless: run_tests.sh sets the offscreen video driver, the OpenGL
# renderer and the dummy audio driver.
#
# With SHOWCASE_PROFILE=<file> the same run is the profiling baseline
# (tools/profile.sh): the frame rate is not capped (maxfps 0, or
# SHOWCASE_MAXFPS), and the duration of every frame that drew is written to
# <file>, one per line in milliseconds with the last step run before it,
# and a summary on stdout. A frame's
# duration is Clock's dt at the next tick; it is the frame's whole cost only
# when nothing sleeps between frames (maxfps 0). SHOWCASE_VERBOSE=1 prints
# each step's name.

import std/[algorithm, assertions, envvars, math, strutils, syncio]
import nimkivy/sdl3/sdl
import ../examples/showcase

type
  Ready = proc (): bool {.closure.}

  Step = object
    delay: float               # seconds after the previous step, at least
    name: string
    ready: Ready               # then it waits until this is true
    action: proc () {.closure.}

  Script = ref object
    steps: seq[Step]
    next: int
    due: float                 # Clock time the next step runs at
    finished: bool
    drew: bool                 # the last frame drew
    frameMs: seq[float]        # durations of the frames that drew
    frameStep: seq[string]     # the last step run before each of them
    frames: int

const Patience = 10.0
  # Seconds a step waits for its `ready` before the run fails. The waits make
  # the run independent of the frame rate (a slow machine, valgrind).

proc always(): bool = true

proc add(sc: Script; delay: float; name: string; action: proc () {.closure.}) =
  sc.steps.add Step(delay: delay, name: name, ready: always, action: action)

proc add(sc: Script; delay: float; name: string; ready: Ready; action: proc () {.closure.}) =
  sc.steps.add Step(delay: delay, name: name, ready: ready, action: action)

# ------------------------------------------------------------------ input

proc pushFinger(t: SDL_EventType; x, y: float) =
  # An SDL finger event at window position (x, y), y up (Kivy's).
  var ev = default(SDL_Event)
  ev.tfinger = SDL_TouchFingerEvent(`type`: t, touchID: 1, fingerID: SDL_FingerID(1),
    x: float32(x / Window.width), y: float32(1.0 - y / Window.height), pressure: 1)
  assert pushEvent(ev)

proc centre(w: Widget): (float, float) =
  # The widget's centre in window coordinates (through the RelativeLayouts).
  w.toWindow(w.centerX, w.centerY)

type Point = proc (): (float, float) {.closure.}

proc tap(sc: Script; delay: float; name: string; at: Point) =
  # Down now, up two frames' worth later.
  sc.add(delay, name & " (down)", proc () {.closure.} =
    let (x, y) = at()
    pushFinger(SDL_EVENT_FINGER_DOWN, x, y))
  sc.add(0.05, name & " (up)", proc () {.closure.} =
    let (x, y) = at()
    pushFinger(SDL_EVENT_FINGER_UP, x, y))

proc on(w: Widget): Point =
  result = proc (): (float, float) {.closure.} = w.centre

# ------------------------------------------------------------------ checks

proc near(a, b: float; eps = 0.5): bool = abs(a - b) <= eps

proc covers(im: Image): bool =
  # fit_mode cover: the picture fills the widget and overflows one side.
  let (w, h) = im.normImageSize
  result = w >= im.width - 0.5 and h >= im.height - 0.5 and
    (near(w, im.width) or near(h, im.height))

proc contains(im: Image): bool =
  # fit_mode contain: the picture fits and touches two sides.
  let (w, h) = im.normImageSize
  result = w <= im.width + 0.5 and h <= im.height + 0.5 and
    (near(w, im.width) or near(h, im.height))

proc current(s: Showcase): string = s.sm.current.get("")

proc settled(s: Showcase; name: string): bool =
  # The screen is current and its fade has ended.
  result = false
  let scr = s.sm.currentScreen
  if scr != nil:
    result = s.current == name and not s.sm.transition.isActive and scr.parent != nil

# ------------------------------------------------------------------ the run

let profileOut = getEnv("SHOWCASE_PROFILE")
let verbose = getEnv("SHOWCASE_VERBOSE").len > 0   # prints each step's name
Config.graphics.width = 800
Config.graphics.height = 600
if profileOut.len > 0:
  Config.graphics.maxfps = try: parseInt(getEnv("SHOWCASE_MAXFPS", "0")) except: 0

let kiosk = newShowcaseApp()
kiosk.slideInterval = 1.5
kiosk.fadeDuration = 0.5
kiosk.idleTimeout = 3.0
let sc = Script(steps: @[], next: 0, due: 0, finished: false, drew: false, frameMs: @[],
  frameStep: @[], frames: 0)

proc percentile(sorted: seq[float]; p: float): float =
  # The nearest-rank percentile of sorted samples.
  let n = sorted.len
  result = sorted[min(n - 1, int(floor(p * float(n - 1) + 0.5)))]

proc build(app: ShowcaseApp) =
  let s = app.show
  let en = texts("en")

  sc.add(0.3, "start", proc () {.closure.} =
    assert s.settled("attract"), s.current
    assert s.attractTitle.text == "Figs of Crete"
    assert s.slides[0].opacity == 1.0 and s.slides[1].opacity == 0.0
    assert s.slides[0].covers
    assert s.sm.size == (800.0, 600.0), $s.sm.size & " (Window " & $Window.size & ")")
  # The first change starts at 1.5 s and ends at 2.0 s. On a slow run
  # (valgrind) more may have happened: the photo shown is the last one.
  sc.add(1.0, "crossfade", proc (): bool {.closure.} =
    "slide 1" in s.log and s.slides[s.front].opacity == 1.0 and
      s.slides[1 - s.front].opacity == 0.0, proc () {.closure.} =
    let shown = s.slides[s.front]
    assert shown.source.endsWith(Photos[s.slide]), shown.source
    assert s.log[^1] == "slide " & $s.slide
    assert shown.covers, $(shown.normImageSize, shown.size))
  sc.tap(0.1, "attract", proc (): (float, float) {.closure.} = (400.0, 300.0))
  sc.add(0.25, "home", proc (): bool {.closure.} = s.settled("home"), proc () {.closure.} =
    assert s.tiles.len == 3 and s.tileLabels[1].text == en.topics[1]
    for i in 0 ..< 3:
      assert s.tileImages[i].covers
      assert near(s.tiles[i].width, (800.0 - 32.0 - 32.0) / 3.0), $s.tiles[i].width
    assert s.homeTitle.textureSize[0] > 0)
  sc.add(0.0, "tile down", proc () {.closure.} =
    let (x, y) = s.tiles[1].centre
    pushFinger(SDL_EVENT_FINGER_DOWN, x, y))
  sc.add(0.0, "tile pressed", proc (): bool {.closure.} = s.tiles[1].opacity < 1.0,
      proc () {.closure.} =
    let (x, y) = s.tiles[1].centre
    pushFinger(SDL_EVENT_FINGER_UP, x, y))
  sc.add(0.25, "topic", proc (): bool {.closure.} =
    s.settled("topic") and s.tiles[1].opacity == 1.0, proc () {.closure.} =
    assert s.card == 1 and s.cardText.text == en.bodies[1]
    assert s.cardImage.source.endsWith("portrait.png") and s.cardImage.contains
    # The body wraps: at least two lines, within the label's width.
    let (tw, th) = s.cardText.textureSize
    assert tw <= s.cardText.width and th >= 2.0 * s.cardText.fontSize, $(tw, th)
    assert s.listenLabel.text == en.listen)
  sc.tap(0.0, "next", on(s.next))
  sc.add(0.0, "card 2", proc (): bool {.closure.} = s.card == 2, proc () {.closure.} =
    assert s.cardText.text == en.bodies[2]
    assert s.cardImage.source.endsWith("landscape.png"))
  sc.tap(0.0, "prev", on(s.prev))
  sc.add(0.0, "card 1", proc (): bool {.closure.} = s.card == 1, proc () {.closure.} =
    assert s.cardText.text == en.bodies[1])
  # A swipe to the left over the card's text turns to the next card.
  sc.add(0.0, "swipe (down)", proc () {.closure.} =
    let (x, y) = s.cardText.centre
    pushFinger(SDL_EVENT_FINGER_DOWN, x + 100.0, y))
  sc.add(0.03, "swipe (move)", proc () {.closure.} =
    let (x, y) = s.cardText.centre
    pushFinger(SDL_EVENT_FINGER_MOTION, x, y))
  sc.add(0.03, "swipe (up)", proc () {.closure.} =
    let (x, y) = s.cardText.centre
    pushFinger(SDL_EVENT_FINGER_UP, x - 100.0, y))
  sc.add(0.0, "swiped", proc (): bool {.closure.} = s.card == 2, proc () {.closure.} =
    assert s.cardImage.source.endsWith("landscape.png"))
  sc.tap(0.0, "listen", on(s.listen))
  sc.add(0.0, "playing", proc (): bool {.closure.} = "play" in s.log, proc () {.closure.} =
    let snd = s.sound
    assert snd != nil and snd.state == statePlay
    assert s.listenLabel.text == en.stop)
  # tone.wav is 1.40 s; the end is seen within the 0.1 s check after it.
  sc.add(1.3, "played", proc (): bool {.closure.} = "stop" in s.log, proc () {.closure.} =
    let snd = s.sound
    assert snd != nil and snd.state == stateStop
    assert s.listenLabel.text == en.listen)
  sc.tap(0.0, "home button", on(s.homeButton))
  sc.add(0.25, "home again", proc (): bool {.closure.} = s.settled("home"),
    proc () {.closure.} = assert s.sm.currentScreen == s.sm.getScreen("home"))
  sc.tap(0.0, "language", on(s.langButton))
  sc.add(0.1, "picker", proc (): bool {.closure.} = s.picker.isOpen, proc () {.closure.} =
    assert s.picker.parent != nil
    assert near(s.picker.width, 0.7 * 800.0) and near(s.picker.height, 0.4 * 600.0)
    assert s.picker.center == (400.0, 300.0), $s.picker.center)
  sc.tap(0.0, "Greek", on(s.choices[1]))
  sc.add(0.1, "greek", proc (): bool {.closure.} = s.picker.parent == nil, proc () {.closure.} =
    let el = texts("el")
    assert s.lang == "el", s.lang
    assert not s.picker.isOpen
    assert s.homeTitle.text == el.title and s.tileLabels[0].text == el.topics[0]
    assert s.cardText.text == el.bodies[s.card])
  sc.add(0.0, "resize", proc () {.closure.} =
    Window.size = (1000.0, 750.0))
  sc.add(0.0, "resized", proc (): bool {.closure.} = s.sm.size == (1000.0, 750.0),
      proc () {.closure.} =
    assert Window.size == (1000.0, 750.0), $Window.size
    assert s.headers[0].height == 100.0, $s.headers[0].height
    assert near(s.tiles[0].width, (1000.0 - 32.0 - 32.0) / 3.0), $s.tiles[0].width
    assert s.homeTitle.fontSize == 37.5
    for i in 0 ..< 3: assert s.tileImages[i].covers)
  # No touch for idleTimeout: back to the attract screen.
  sc.add(2.5, "idle reset", proc (): bool {.closure.} = s.settled("attract"),
      proc () {.closure.} =
    assert "idle reset" in s.log
    assert Clock.getTime() - s.lastTouch >= 3.0)
  sc.add(0.0, "stop", proc () {.closure.} =
    sc.finished = true
    kiosk.stop())

proc runScript() =
  # Each frame: the step that is due, if any.
  discard Clock.scheduleInterval(proc (dt: float) {.closure.} =
    # Frame durations: a frame that drew is timed at the next tick (Clock's
    # dt, from tick to tick; with maxfps 0 nothing sleeps in between).
    inc sc.frames
    if sc.drew:
      sc.frameMs.add dt * 1000.0
      sc.frameStep.add(if sc.next > 0: sc.steps[sc.next - 1].name else: "-")
      sc.drew = false
    if sc.next >= sc.steps.len: return
    let now = Clock.getTime()
    if sc.due == 0: sc.due = now + sc.steps[0].delay
    if now < sc.due: return
    if not sc.steps[sc.next].ready():
      if now > sc.due + Patience:
        quit "tshowcase: step '" & sc.steps[sc.next].name & "' never got ready"
    else:
      let step = sc.steps[sc.next]
      inc sc.next
      if verbose: stderr.writeLine "step " & step.name
      step.action()
      if sc.next < sc.steps.len:
        sc.due = now + sc.steps[sc.next].delay, 0)

discard kiosk.bindStart(proc (): bool {.closure.} =
  build(kiosk)
  discard Window.bindFlip(proc (): bool {.closure.} =
    sc.drew = true
    result = false)
  runScript()
  result = false)
kiosk.run()

assert sc.finished, "the script did not finish: step " & $sc.next & " of " & $sc.steps.len
let s = kiosk.show
# The order of what happened, without the photo changes (they depend on how
# long the attract screen is shown).
var order: seq[string] = @[]
for i in 0 ..< s.log.len:
  if not s.log[i].startsWith("slide"): order.add s.log[i]
assert order == @["card 0", "screen home", "card 1",
  "screen topic", "card 2", "card 1", "card 2", "play", "stop", "screen home", "card 2",
  "lang el", "idle reset", "screen attract"], $order

if profileOut.len > 0:
  var sorted = sc.frameMs
  sorted.sort()
  let n = sorted.len
  var total = 0.0
  for x in sorted: total += x
  var lines = ""
  for i in 0 ..< sc.frameMs.len:
    lines.add formatFloat(sc.frameMs[i], ffDecimal, 4) & "\t" & sc.frameStep[i] & "\n"
  try:
    writeFile(profileOut, lines)
  except:
    quit "cannot write " & profileOut
  echo "frames ", sc.frames, " drawn ", n, " mean ", formatFloat(total / float(n), ffDecimal, 3),
    " p50 ", formatFloat(sorted.percentile(0.5), ffDecimal, 3), " p95 ", formatFloat(sorted.percentile(0.95), ffDecimal, 3),
    " max ", formatFloat(sorted[n - 1], ffDecimal, 3), " ms"
echo "tshowcase: ", sc.steps.len, " steps"
