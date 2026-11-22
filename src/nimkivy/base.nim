## The event loop: Kivy's `kivy/base.py` (EventLoopBase, runTouchApp,
## stopTouchApp).
##
## Each frame `idle` ticks the Clock, reads the input providers and
## dispatches their motion events, runs the Clock's before-frame events, and
## draws the window if its canvas changed. `postDispatchInput` sends a motion
## event to the window (`motion`, which turns it into `touchDown`,
## `touchMove` and `touchUp`), then again to every widget that grabbed it,
## with `grabCurrent` set. Kivy's tests post touches straight into
## `postDispatchInput`, and so can tests here.
##
## Out of scope (SCOPE.md): input providers other than the mouse and SDL's
## fingers, the postproc modules (double and triple tap, dejitter, retain
## touch, ignore list, calibration), async running and the Android presplash.

import std/syncio
import ./[props, clock, config]
import input/motionevent
import graphics/instructions
import core/window/window_sdl3

export window_sdl3

type
  LoopStatus* = enum
    ## Where the event loop is (Kivy's `status` strings).
    loopIdle = "idle", loopStarted = "started", loopStopped = "stopped",
    loopClosed = "closed"

properties:
  type
    EventLoopBase* = ref object of RootObj
      ## The main loop. `EventLoop` is the application's one.
      quit*: bool                   ## leave the main loop
      status*: LoopStatus
      stopping*: bool
      inputEvents: seq[InputEvent]
      inputProviders*: seq[MotionEventProvider]
      inputProvidersAutoremove: seq[MotionEventProvider]
      eventListeners*: seq[WindowBase]  ## they receive `motion` (the window)
      window*: nil WindowSDL
      meList*: seq[MotionEvent]     ## the touches currently down
      start* {.event.}: proc ()
      pause* {.event.}: proc ()
      stop* {.event.}: proc ()

  proc newEventLoopBase*(): EventLoopBase =
    ## An idle event loop without a window. base.py EventLoopBase.__init__
    result = EventLoopBase(quit: false, status: loopIdle, stopping: false,
      inputEvents: @[], inputProviders: @[], inputProvidersAutoremove: @[],
      eventListeners: @[], window: nil, meList: @[])
    result.initProps()

  proc touches*(el: EventLoopBase): seq[MotionEvent] {.inline.} =
    ## The touches currently down or moving.
    el.meList

  proc setWindow*(el: EventLoopBase; window: WindowSDL) =
    ## Sets the window the loop draws and dispatches to.
    el.window = window

  proc addInputProvider*(el: EventLoopBase; provider: MotionEventProvider;
      autoRemove = false) =
    ## Adds a source of motion events.
    if provider notin el.inputProviders:
      el.inputProviders.add provider
      if autoRemove:
        el.inputProvidersAutoremove.add provider

  proc removeInputProvider*(el: EventLoopBase; provider: MotionEventProvider) =
    ## Removes a source of motion events.
    let i = el.inputProviders.find(provider)
    if i >= 0:
      el.inputProviders.delete(i)
      let k = el.inputProvidersAutoremove.find(provider)
      if k >= 0:
        el.inputProvidersAutoremove.delete(k)

  proc addEventListener*(el: EventLoopBase; listener: WindowBase) =
    ## Adds a receiver of `motion` (the window).
    if listener notin el.eventListeners:
      el.eventListeners.add listener

  proc removeEventListener*(el: EventLoopBase; listener: WindowBase) =
    ## Removes a receiver of `motion`.
    let i = el.eventListeners.find(listener)
    if i >= 0:
      el.eventListeners.delete(i)

  proc ensureWindow*(el: EventLoopBase) =
    ## Opens the window, unless the loop has one: creates the system window,
    ## registers the window as the loop's window and listener, and adds its
    ## finger provider. Kivy does this when `kivy.core.window` is imported
    ## (WindowBase.__init__, register, WindowSDL.create_window).
    if el.window == nil:
      let w = Window
      w.createWindow()
      el.setWindow(w)
      el.addEventListener(w)
      el.addInputProvider(w.motionProvider)
      # WindowBase.on_close: EventLoop.remove_event_listener(self). An
      # observer, because the window's module cannot see the loop.
      discard w.bindClose(proc (): bool {.closure.} =
        el.removeEventListener(w)
        result = false)

  proc start*(el: EventLoopBase) =
    ## Starts the Clock and the input providers, then dispatches `start`;
    ## does nothing if already started. base.py EventLoopBase.start
    if el.status == loopStarted:
      return
    el.status = loopStarted
    el.quit = false
    # The Clock read graphics.maxfps when the program started; Kivy's Clock
    # reads it after the program has set Config.
    Clock.maxFps = float(Config.graphics.maxfps)
    Clock.startClock()
    let providers = el.inputProviders
    for p in providers:
      p.start()
    discard el.dispatchStart()

  proc stop*(el: EventLoopBase) =
    ## Stops and removes the input providers, stops the Clock, then
    ## dispatches `stop`; does nothing unless started.
    ## base.py EventLoopBase.stop
    if el.status != loopStarted:
      return
    # Stop in the reverse order they were started.
    let providers = el.inputProviders
    var i = providers.len - 1
    while i >= 0:
      providers[i].stop()
      el.removeInputProvider(providers[i])
      dec i
    el.inputEvents = @[]
    Clock.stopClock()
    el.stopping = false
    el.status = loopStopped
    discard el.dispatchStop()

  proc close*(el: EventLoopBase) =
    ## Leaves the main loop and stops the input providers.
    el.quit = true
    el.stop()
    el.status = loopClosed

  proc postDispatchInput*(el: EventLoopBase; action: MotionAction; me: MotionEvent) =
    ## Dispatches one motion event: to the listeners (the window's
    ## `motion`), then to each widget that grabbed it, in that widget's
    ## coordinates and with `grabCurrent` set. base.py post_dispatch_input
    case action
    of maBegin:
      el.meList.add me
    of maEnd:
      let i = el.meList.find(me)
      if i >= 0: el.meList.delete(i)
    of maUpdate:
      discard
    if me.grabExclusiveClass == nil:
      let listeners = el.eventListeners
      for listener in listeners:
        discard listener.dispatchMotion(action, me)
    if not me.isTouch:
      return
    me.grabState = true
    let grabbed = me.grabList
    for wid in grabbed:
      var rootWindow: nil WidgetBase = nil
      if wid of WidgetBase:
        rootWindow = WidgetBase(wid).getRootWindow()
      let transformed = rootWindow != nil and RootRef(rootWindow) != wid
      var skip = false
      if transformed:
        me.push()
        if rootWindow of WindowBase:
          WindowBase(rootWindow).transformMotionEvent2d(me, WidgetBase(wid))
        else:
          # Kivy's AttributeError: the widget's ancestors are not a window.
          me.pop()
          skip = true
      if not skip:
        me.grabCurrent = wid
        if wid of WidgetBase:
          case action
          of maUpdate: discard WidgetBase(wid).dispatchTouchMove(me)
          of maEnd: discard WidgetBase(wid).dispatchTouchUp(me)
          of maBegin: discard   # the touch down is not dispatched again
        me.grabCurrent = nil
        if transformed:
          me.pop()
    me.grabState = false
    me.dispatchDone()

  proc queueInput(el: EventLoopBase; action: MotionAction; me: MotionEvent) =
    # base.py _dispatch_input: an event already waiting moves to the end.
    var i = 0
    while i < el.inputEvents.len:
      if el.inputEvents[i][0] == action and el.inputEvents[i][1] == me:
        el.inputEvents.delete(i)
      else:
        inc i
    el.inputEvents.add (action, me)

  proc dispatchInput*(el: EventLoopBase) =
    ## Reads the input providers and dispatches their events, oldest first.
    ## base.py dispatch_input (the postproc modules are out of scope)
    let providers = el.inputProviders
    for p in providers:
      for (action, me) in p.update():
        el.queueInput(action, me)
    while el.inputEvents.len > 0:
      let (action, me) = el.inputEvents[0]
      el.inputEvents.delete(0)
      el.postDispatchInput(action, me)

  proc exit*(el: EventLoopBase)

  proc idle*(el: EventLoopBase): bool =
    ## One frame: tick the Clock, dispatch input, run the before-frame
    ## events, and draw the window (`draw`, `flip`) if its canvas changed.
    ## Returns whether the loop must quit. base.py idle
    Clock.tick()
    if not el.quit:
      el.dispatchInput()
    if not el.quit:
      Clock.tickDraw()
    if not el.quit:
      let window = el.window
      if window != nil and window.canvas.needsRedraw:
        discard window.dispatchDraw()
        discard window.dispatchFlip()
    # Don't loop if we don't have listeners.
    if el.eventListeners.len == 0:
      stderr.writeLine "[ERROR  ] [Base        ] No event listeners have been created"
      stderr.writeLine "[ERROR  ] [Base        ] Application will leave"
      el.exit()
      return false
    result = el.quit

  proc mainloop*(el: EventLoopBase) =
    ## Runs frames until the loop quits: `idle`, then the window's events.
    ## base.py mainloop
    # GAP: an exception raised in a frame is not passed to an ExceptionManager,
    # because callbacks cannot raise in Nimony's error model (no unwinding
    # through closures)
    while not el.quit and el.status == loopStarted:
      discard el.idle()
      let window = el.window
      if window != nil:
        window.mainloop()

  proc run*(el: EventLoopBase) =
    ## Runs `idle` until the loop quits, then closes the loop and the window.
    while not el.quit:
      discard el.idle()
    el.exit()

  proc exit*(el: EventLoopBase) =
    ## Closes the main loop and the window.
    el.close()
    let window = el.window
    if window != nil:
      window.close()

let EventLoop* = newEventLoopBase()
  ## The application's event loop.

proc stopTouchApp*()

proc prepareTouchApp(widget: nil WidgetBase) =
  # base.py _runTouchApp_prepare
  if widget != nil:
    EventLoop.ensureWindow()
  # The input providers of Config's [input] section: only the mouse is in
  # scope.
  if Config.input.mouse:
    EventLoop.addInputProvider(newMouseMotionEventProvider("mouse", Config.input.mouseOptions,
      Window), true)
  let window = EventLoop.window
  if widget != nil and window != nil:
    if widget notin window.children:
      window.addWidget(widget)
  stderr.writeLine "[INFO   ] [Base        ] Start application main loop"
  EventLoop.start()

proc runTouchApp*(widget: nil WidgetBase = nil; embedded = false) =
  ## Starts the application loop: opens the window (with a widget, which
  ## becomes a root widget), starts the input providers and runs frames
  ## until the loop stops. `embedded` only prepares; the caller then runs
  ## the frames. base.py runTouchApp
  prepareTouchApp(widget)
  if embedded:
    return
  EventLoop.mainloop()
  stopTouchApp()

proc stopTouchApp*() =
  ## Stops the application loop; if it has not started yet, on the next
  ## Clock tick. base.py stopTouchApp
  if EventLoop.status in {loopStopped, loopClosed}:
    return
  if EventLoop.status != loopStarted:
    if not EventLoop.stopping:
      EventLoop.stopping = true
      discard Clock.scheduleOnce(proc (dt: float) {.closure.} = stopTouchApp(), 0)
    return
  stderr.writeLine "[INFO   ] [Base        ] Leaving application in progress..."
  EventLoop.close()

# The window calls into this module through these (core/window).
Window.stopTouchApp = proc () {.closure.} = stopTouchApp()
Window.quitEventLoop = proc () {.closure.} = EventLoop.quit = true
