## The application: Kivy's `kivy/app.py` (App), the members in SCOPE.md.
##
## An app is a subtype of `App` that overrides `build` to return its root
## widget. `run` opens the window, builds the root, adds it to the window,
## dispatches `start` and runs the event loop until `stop`. The events
## `start`, `stop`, `pause` (true keeps the app alive when Android pauses
## it, the default) and `resume` have default handlers, the methods
## `onStart`, `onStop`, `onPause` and `onResume`, which subtypes override,
## as Kivy's methods are overridden.
##
## Out of scope (SCOPE.md): kv loading, config files and settings,
## `user_data_dir`, `directory`, icons and async running.

import std/[strutils, syncio]
import ./[props, base]

export base

properties:
  type
    App* = ref object of RootObj
      ## An application. Build a subtype with `T()`, then call `initApp`
      ## with its class name.
      root*: nil WidgetBase         ## the root widget from `build`
      built*: bool
      className*: string            ## Kivy's class name, as `name` reads it
      appWindow: nil WindowSDL
      title* {.prop, handler.}: Opt[string] = none[string]()
        # StringProperty(None): none is the class name (`getApplicationName`)
      start* {.event.}: proc ()
      stop* {.event.}: proc ()
      pause* {.event.}: proc ()
      resume* {.event.}: proc ()

  method onPause*(app: App): bool {.base.} =
    ## The default `pause` handler: pausing is supported. App.on_pause
    true

  method onTitleChanged*(app: App; v: Opt[string]) {.base.} =
    ## Shows the new title on the window. App.on_title
    let w = app.appWindow
    if w != nil:
      w.setTitle(v.get(""))

  proc `title=`*(app: App; title: string) =
    ## Sets the window title.
    app.title = some(title)

  proc initApp*(app: App; className = "App") =
    ## Sets up a new app of the class `className` (a subtype's name); it
    ## becomes the running app. App.__init__
    # GAP: the class name is given here, where Kivy reads the object's class,
    # because `$typeof(app)` of a `ref object` type is `ref T.Obj`, not `T`
    # (planetis-m/nimony-bugs-llms#340)
    app.initProps()
    app.root = nil
    app.built = false
    app.className = className
    app.appWindow = nil
    Window.runningApp = app
    Window.pauseApp = proc (): bool {.closure.} = app.dispatchPause()
    Window.resumeApp = proc () {.closure.} = discard app.dispatchResume()

  proc getRunningApp*(): nil App =
    ## The running app, or nil. App.get_running_app
    let a = Window.runningApp
    if a == nil or not (a of App): return nil
    result = App(a)

  proc newApp*(): App =
    ## A plain App.
    result = App()
    result.initApp()

  method build*(app: App): nil WidgetBase {.base.} =
    ## Returns the root widget; called once by `run`. Kivy's default returns a
    ## new Widget when there is no root; here it returns nil (see PORTING.md,
    ## Design differences: Widget comes after this module).
    nil

  proc classStem(app: App): string =
    # The class name without a trailing "App".
    result = app.className
    if result.endsWith("App"):
      result = result.substr(0, result.len - 4)

  proc getApplicationName*(app: App): string =
    ## The title, or the class name without a trailing "App".
    ## App.get_application_name
    let title = app.title
    result = if title.isSome: title.get("") else: app.classStem()

  proc name*(app: App): string =
    ## The class name without "App", in lower case. App.name
    app.classStem().toLowerAscii

  proc runPrepare(app: App) =
    # App._run_prepare. Kivy's window exists before `build` (it opens when
    # imported), so build can read Window.size; here it opens now.
    EventLoop.ensureWindow()
    if not app.built:
      let root = app.build()
      if root != nil:
        app.root = root
    let root = app.root
    if root != nil:
      Window.addWidget(root)
    let window = EventLoop.window
    if window == nil:
      stderr.writeLine "[CRITICAL] [Application ] No window is created. " &
        "Terminating application run."
      return
    app.appWindow = window
    window.setTitle(app.getApplicationName())
    # The settings keys (F1, and 27 closing the settings) are out of scope.
    discard app.dispatchStart()

  proc stopNow(app: App) =
    # App._stop. Like Kivy, it walks the window's children while removing
    # them, so every second root widget stays.
    discard app.dispatchStop()
    stopTouchApp()
    let w = app.appWindow
    if w != nil:
      var i = 0
      while i < w.children.len:
        w.removeWidget(w.children[i])
        inc i
    Window.runningApp = nil
    Window.pauseApp = nil
    Window.resumeApp = nil

  proc run*(app: App) =
    ## Builds the app and runs it until it stops. App.run
    app.runPrepare()
    runTouchApp()
    app.stopNow()

  proc stop*(app: App) =
    ## Stops the app: dispatches `stop` and leaves the event loop. App.stop
    # GAP: on Android the app stops like on the desktop, where Kivy calls
    # mActivity.finishAndRemoveTask(), because SDL3 has no call for it and
    # JNI is out of scope
    app.stopNow()
