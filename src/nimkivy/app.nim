## The application: Kivy's `kivy/app.py` (App), the members in SCOPE.md.
##
## An app is a subtype of `App` that overrides `build` to return its root
## widget. `run` opens the window, builds the root, adds it to the window,
## dispatches `on_start` and runs the event loop until `stop`. The events
## `on_start`, `on_stop`, `on_pause` (true keeps the app alive when Android
## pauses it, the default) and `on_resume` have default handlers that
## subtypes override through their class (`setEventHandler`), as Kivy's
## methods are overridden.
##
## Out of scope (SCOPE.md): kv loading, config files and settings,
## `user_data_dir`, `directory`, icons and async running.

import std/[strutils, syncio]
import ./[properties, base]

export base

type
  App* = ref object of EventDispatcher
    ## An application. Build it with `T(cls: ...)` (a class made from
    ## `AppClass`, named like the Python class), then call `initApp`.
    root*: nil WidgetBase         ## the root widget from `build`
    built*: bool
    appWindow: nil WindowSDL

proc onTitle(d: EventDispatcher; v: Value) =
  # App.on_title
  let w = App(d).appWindow
  if w != nil:
    w.setTitle(v.str)

proc noHandler(d: EventDispatcher; args: seq[Value]): bool =
  false

proc onPause(d: EventDispatcher; args: seq[Value]): bool =
  # App.on_pause: pausing is supported by default.
  true

proc newAppClass(): DispatcherClass =
  result = newDispatcherClass("App", EventDispatcherClass)
  # StringProperty(None)
  let title = newStringProperty("", allowNone = true)
  title.defaultValue = noneValue()
  result.addProperty("title", title)
  result.addPropertyHandler("title", onTitle)
  result.addEvent("on_start", noHandler)
  result.addEvent("on_stop", noHandler)
  result.addEvent("on_pause", onPause)
  result.addEvent("on_resume", noHandler)

let AppClass* = newAppClass()
  ## The class of `App`: subclass it with `newDispatcherClass("MyApp", AppClass)`.

proc initApp*(app: App) =
  ## Sets up a new app; it becomes the running app. App.__init__
  app.initEventDispatcher()
  app.root = nil
  app.built = false
  app.appWindow = nil
  Window.runningApp = app

proc newApp*(cls: DispatcherClass): App =
  ## A plain app of class `cls`.
  result = App(cls: cls, root: nil, built: false, appWindow: nil)
  result.initApp()

proc newApp*(): App =
  ## A plain App.
  newApp(AppClass)

proc getRunningApp*(): nil App =
  ## The running app, or nil. App.get_running_app
  let a = Window.runningApp
  if a == nil or not (a of App): return nil
  result = App(a)

method build*(app: App): nil WidgetBase {.base.} =
  ## Returns the root widget; called once by `run`. Kivy's default returns a
  ## new Widget when there is no root; here it returns nil (see PORTING.md,
  ## Design differences: Widget comes after this module).
  nil

proc title*(app: App): string =
  ## The window title ("" when None: the class name is used).
  let v = app.getProperty("title")
  result = if v.isNone: "" else: v.str

proc `title=`*(app: App; title: string) =
  ## Sets the window title.
  app.setProperty("title", toValue(title))

proc getApplicationName*(app: App): string =
  ## The title, or the class name without a trailing "App".
  ## App.get_application_name
  let v = app.getProperty("title")
  if not v.isNone:
    return v.str
  result = app.cls.name
  if result.endsWith("App"):
    result = result.substr(0, result.len - 4)

proc name*(app: App): string =
  ## The class name without "App", in lower case. App.name
  result = app.cls.name
  if result.endsWith("App"):
    result = result.substr(0, result.len - 4)
  result = result.toLowerAscii

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
  discard app.dispatch("on_start")

proc stopNow(app: App) =
  # App._stop. Like Kivy, it walks the window's children while removing
  # them, so every second root widget stays (Python list iteration).
  discard app.dispatch("on_stop")
  stopTouchApp()
  let w = app.appWindow
  if w != nil:
    var i = 0
    while i < w.children.len:
      w.removeWidget(w.children[i])
      inc i
  Window.runningApp = nil

proc run*(app: App) =
  ## Builds the app and runs it until it stops. App.run
  app.runPrepare()
  runTouchApp()
  app.stopNow()

proc stop*(app: App) =
  ## Stops the app: dispatches `on_stop` and leaves the event loop.
  ## App.stop
  # GAP: on Android the app stops like on the desktop, where Kivy calls
  # mActivity.finishAndRemoveTask(), because SDL3 has no call for it and JNI
  # is out of scope
  app.stopNow()
