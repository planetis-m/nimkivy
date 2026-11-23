## The clock: Kivy's `kivy/_clock.pyx` (CyClockBase, ClockEvent) and
## `kivy/clock.py` (ClockBaseBehavior, ClockBase).
##
## Scheduled events wait in one list in scheduling order. `tick` runs every
## due event once; `tickDraw` runs the events with timeout -1 before a frame
## is drawn, repeating while they schedule more (up to `maxIteration`). An
## event scheduled while events are being processed waits for the next pass.
##
## Callbacks receive `dt`, the seconds since the event was scheduled or last
## ran. Out of scope (SCOPE.md): a callback returning false to stop an
## interval, lifecycle-aware triggers, `schedule_del_safe`, threads, async
## clocks and the `triggered` decorator.

import std/syncio
import config, sdl3/sdl

type
  ClockCallback* = proc (dt: float) {.closure.}
    ## What an event calls, with the seconds since it last ran.

  ClockEvent* = ref object
    ## One scheduled callback. Calling it (`trigger`) schedules it unless it
    ## is already scheduled; `cancel` removes it.
    clock: ClockBase
    loop*: bool                   ## repeat until cancelled (an interval)
    callback*: ClockCallback
    timeout*: float               ## seconds; 0 is the next tick, -1 before the next frame
    lastDt: float                 # the time it was scheduled or last ran
    dt: float
    isTriggered: bool
    next, prev: nil ClockEvent

  ClockBase* = ref object
    ## A clock. `Clock` is the application's one; tests make their own.
    rootEvent, lastEvent: nil ClockEvent    # the scheduled events, in order
    nextEvent, capEvent: nil ClockEvent     # the processing cursor and its end
    clockResolution*: float       ## -1: derived from `maxFps`
    maxFps*: float                ## frames per second `idle` paces to; 0 does not wait
    maxIteration*: int            ## passes of `tickDraw` before it gives up
    hasStarted, hasEnded: bool
    startTick, lastTick: float
    dt: float
    frames, framesDisplayed: int
    lastFpsTick: float
    fps: float
    rfps: int
    fpsCounter, rfpsCounter: int

proc time*(): float =
  ## Seconds on the monotonic clock (Kivy's `_default_time`).
  float(SDL_GetTicksNS()) / 1e9

proc newClockBase*(): ClockBase =
  ## A clock that has not started, paced to `graphics.maxfps`.
  ## clock.py ClockBaseBehavior.__init__ and _clock.pyx CyClockBase.__init__
  let now = time()
  result = ClockBase(rootEvent: nil, lastEvent: nil, nextEvent: nil, capEvent: nil,
    clockResolution: -1.0, maxFps: float(Config.graphics.maxfps),
    maxIteration: 20, hasStarted: false, hasEnded: false, startTick: now,
    lastTick: now, dt: 0.0001, frames: 0, framesDisplayed: 0, lastFpsTick: -1.0,
    fps: 0.0, rfps: 0, fpsCounter: 0, rfpsCounter: 0)

# ------------------------------------------------------------------ ClockEvent

proc onSchedule(c: ClockBase; ev: ClockEvent) =
  # CyClockBase.on_schedule: a hook for interrupting clocks; nothing here.
  discard

proc append(c: ClockBase; ev: sink ClockEvent) =
  # Puts `ev` last in the list of scheduled events.
  ev.isTriggered = true
  let last = c.lastEvent
  if last == nil:
    c.rootEvent = ev
    c.lastEvent = ev
  else:
    last.next = ev
    ev.prev = last
    c.lastEvent = ev

proc newClockEvent(c: ClockBase; loop: bool; callback: sink ClockCallback;
    timeout, starttime: float; trigger: bool): ClockEvent =
  # _clock.pyx ClockEvent.__init__
  result = ClockEvent(clock: c, loop: loop, callback: callback, timeout: timeout,
    lastDt: starttime, dt: 0.0, isTriggered: false, next: nil, prev: nil)
  if trigger:
    c.append(result)
    c.onSchedule(result)

proc trigger*(ev: ClockEvent) =
  ## Schedules the event, unless it is already scheduled (Kivy's
  ## `event()`). Its time counts from the clock's last tick.
  if not ev.isTriggered:
    ev.lastDt = ev.clock.lastTick
    ev.clock.append(ev)
    ev.clock.onSchedule(ev)

proc isTriggered*(ev: ClockEvent): bool {.inline.} =
  ## Whether the event is scheduled.
  ev.isTriggered

proc cancel*(ev: ClockEvent) =
  ## Unschedules the event; nothing happens if it is not scheduled.
  ## _clock.pyx ClockEvent.cancel
  if ev.isTriggered:
    ev.isTriggered = false
    let c = ev.clock
    if c.capEvent == ev:
      # The pass in progress must still stop: move its end to the previous
      # event, or end it here if this was also the next one to run.
      if c.capEvent == c.nextEvent: c.capEvent = nil
      else: c.capEvent = ev.prev
    if c.nextEvent == ev:
      c.nextEvent = ev.next
    let prev = ev.prev
    let next = ev.next
    if prev == nil:
      if next == nil:
        c.rootEvent = nil
        c.lastEvent = nil
      else:
        c.rootEvent = next
        next.prev = nil
    else:
      if next == nil:
        c.lastEvent = prev
        prev.next = nil
      else:
        prev.next = next
        next.prev = prev
    ev.prev = nil
    ev.next = nil

proc getResolution*(c: ClockBase): float =
  ## The smallest time step the clock tells apart: a third of a frame.
  result = c.clockResolution
  if result < 0:
    result = if c.maxFps > 0: 1 / (3.0 * c.maxFps) else: 0.0001

proc tick(ev: ClockEvent; curtime: float) =
  # Runs the event if its timeout has passed. _clock.pyx ClockEvent.tick
  if curtime - ev.lastDt < ev.timeout - ev.clock.getResolution():
    return
  ev.dt = curtime - ev.lastDt
  ev.lastDt = curtime
  if not ev.loop: ev.cancel()
  # GAP: an exception in a callback is not caught and passed to the
  # ExceptionManager, because callbacks cannot raise in Nimony's error model
  # (no unwinding through closures)
  ev.callback(ev.dt)

# ------------------------------------------------------------------ scheduling

proc startClock*(c: ClockBase) =
  ## Starts the clock (once).
  c.hasStarted = true

proc stopClock*(c: ClockBase) =
  ## Stops the clock. Lifecycle-aware callbacks are out of scope.
  c.hasEnded = true

proc createTrigger*(c: ClockBase; callback: sink ClockCallback; timeout = 0.0;
    interval = false): ClockEvent =
  ## An event that is not scheduled yet: `trigger` it as often as wanted, it
  ## runs once per tick.
  # GAP: the event holds `callback` strongly, where Kivy keeps only a weak
  # reference (`release_ref`), so a dropped widget's callback still runs and
  # keeps it alive, because Nimony has no weak references
  result = c.newClockEvent(interval, callback, timeout, 0.0, false)

proc scheduleOnce*(c: ClockBase; callback: sink ClockCallback; timeout = 0.0): ClockEvent =
  ## Runs `callback` once: on the next `tick` (timeout 0), before the next
  ## frame (-1, in `tickDraw`), or on the first tick `timeout` seconds later.
  result = c.newClockEvent(false, callback, timeout, c.lastTick, true)

proc scheduleInterval*(c: ClockBase; callback: sink ClockCallback; timeout: float): ClockEvent =
  ## Runs `callback` every `timeout` seconds until it is cancelled.
  result = c.newClockEvent(true, callback, timeout, c.lastTick, true)

proc unschedule*(c: ClockBase; ev: ClockEvent) =
  ## Cancels `ev`.
  ev.cancel()

proc unschedule*(c: ClockBase; callback: ClockCallback; all = true) =
  ## Cancels the scheduled events whose callback is `callback` (the same
  ## closure): every one, or the first with `all` false.
  var events: seq[ClockEvent] = @[]
  var ev = c.rootEvent
  while ev != nil:
    if ev.callback == callback:
      events.add ev
      if not all: break
    ev = ev.next
  for e in events: e.cancel()

proc getEvents*(c: ClockBase): seq[ClockEvent] =
  ## The scheduled events, in order.
  result = @[]
  var ev = c.rootEvent
  while ev != nil:
    result.add ev
    ev = ev.next

proc getBeforeFrameEvents*(c: ClockBase): seq[ClockEvent] =
  ## The scheduled events with timeout -1.
  result = @[]
  var ev = c.rootEvent
  while ev != nil:
    if ev.timeout == -1: result.add ev
    ev = ev.next

proc getMinTimeout*(c: ClockBase): float =
  ## The time at which the next event is due (0 if one is due now).
  result = high(float)
  var ev = c.rootEvent
  while ev != nil:
    if ev.timeout <= 0:
      return 0.0
    result = min(result, ev.timeout + ev.lastDt)
    ev = ev.next

# ------------------------------------------------------------------ processing

proc processEvents(c: ClockBase) =
  # Runs the events scheduled before this pass started, in order: `capEvent`
  # is the last of them, and `nextEvent` survives a cancel of the next one.
  # _clock.pyx CyClockBase._process_events
  if c.rootEvent == nil: return
  c.capEvent = c.lastEvent
  var event = c.rootEvent
  var done = false
  while not done and event != nil:
    c.nextEvent = event.next
    done = c.capEvent == event or c.capEvent == nil
    event.tick(c.lastTick)
    event = c.nextEvent
  c.nextEvent = nil
  c.capEvent = nil

proc processEventsBeforeFrame(c: ClockBase) =
  # Runs the -1 events, again while they schedule more, at most
  # `maxIteration` passes. _clock.pyx CyClockBase._process_events_before_frame
  var count = c.maxIteration
  var found = true
  while found:
    dec count
    if count == -1:
      stderr.writeLine "[CRITICAL] [Clock       ] Warning, too much iteration done " &
        "before the next frame. Check your code, or increase the " &
        "Clock.max_iteration attribute."
      break
    found = false
    var done = false
    if c.rootEvent == nil: return
    c.capEvent = c.lastEvent
    var event = c.rootEvent
    while not done and event != nil:
      if event.timeout != -1:
        done = c.capEvent == event or c.capEvent == nil
        event = event.next
      else:
        c.nextEvent = event.next
        done = c.capEvent == event or c.capEvent == nil
        found = true
        event.tick(c.lastTick)
        event = c.nextEvent
    c.nextEvent = nil
    c.capEvent = nil

proc usleep*(microseconds: float) =
  ## Sleeps (Kivy's `_usleep`).
  SDL_DelayPrecise(uint64(max(microseconds, 0.0) * 1000))

proc checkReady(c: ClockBase; fps, minSleep, undershoot: float): (bool, float) =
  # clock.py ClockBaseBehavior._check_ready
  let sleeptime = 1 / fps - (time() - c.lastTick)
  result = (sleeptime - undershoot <= minSleep, sleeptime - undershoot)

proc idle*(c: ClockBase): float =
  ## Waits until the next frame is due (`maxFps`), then advances the time.
  ## clock.py ClockBaseBehavior.idle
  let fps = c.maxFps
  if fps > 0:
    let minSleep = c.getResolution()
    let undershoot = 4 / 5 * minSleep
    var (done, sleeptime) = c.checkReady(fps, minSleep, undershoot)
    while not done:
      usleep(1000000 * sleeptime)
      (done, sleeptime) = c.checkReady(fps, minSleep, undershoot)
  let current = time()
  c.dt = current - c.lastTick
  c.lastTick = current
  result = current

proc tick*(c: ClockBase) =
  ## Advances the clock to the next frame and runs the due events. The
  ## event loop calls it once per frame.
  ## clock.py ClockBaseBehavior.tick and post_idle
  let current = c.idle()
  inc c.frames
  inc c.fpsCounter
  if c.lastFpsTick < 0:
    c.lastFpsTick = current
  elif current - c.lastFpsTick > 1:
    c.fps = float(c.fpsCounter) / (current - c.lastFpsTick)
    c.rfps = c.rfpsCounter
    c.lastFpsTick = current
    c.fpsCounter = 0
    c.rfpsCounter = 0
  c.processEvents()

proc tickDraw*(c: ClockBase) =
  ## Runs the events with timeout -1; called before a frame is drawn.
  c.processEventsBeforeFrame()
  inc c.rfpsCounter
  inc c.framesDisplayed

proc frametime*(c: ClockBase): float {.inline.} =
  ## Seconds between the last two frames.
  c.dt

proc frames*(c: ClockBase): int {.inline.} =
  ## Frames ticked since the start.
  c.frames

proc framesDisplayed*(c: ClockBase): int {.inline.} =
  ## Frames drawn since the start.
  c.framesDisplayed

proc getFps*(c: ClockBase): float {.inline.} =
  ## The average frames per second over the last second.
  c.fps

proc getRfps*(c: ClockBase): int {.inline.} =
  ## The frames drawn in the last second.
  c.rfps

proc getTime*(c: ClockBase): float {.inline.} =
  ## The time of the last tick.
  c.lastTick

proc getBoottime*(c: ClockBase): float {.inline.} =
  ## Seconds from the clock's start to the last tick.
  c.lastTick - c.startTick

let Clock* = newClockBase()
  ## The application's clock. It reads `graphics.maxfps` when the program
  ## starts, before user code can change `Config`; the event loop (layer 5)
  ## reads it again when the app starts, where Kivy's Config is already set.
