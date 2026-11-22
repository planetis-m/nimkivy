## The screen manager: Kivy's `kivy/uix/screenmanager.py` (Screen,
## ScreenManager, TransitionBase, NoTransition, ShaderTransition,
## FadeTransition), with the ScreenManager rule from `kivy/data/style.kv`.
##
## A ScreenManager is a FloatLayout that shows one Screen at a time, clipped
## to its box by a stencil. Setting `current` to a screen's name runs the
## `transition` from the current screen to it: the new screen gets
## `on_pre_enter` and the old one `on_pre_leave`; at the end the old one is
## removed from the children, and they get `on_enter` and `on_leave`.
## Touches are ignored while a transition runs.
##
## FadeTransition draws both screens into textures cleared to opaque black
## (`Fbo` in `graphics/renderer`) and shows `t*in + (1-t)*out`; during it
## neither screen is in `children`. NoTransition switches at the next frame.
##
## Out of scope (SCOPE.md): SlideTransition, SwapTransition, CardTransition,
## WipeTransition, FallOutTransition, RiseInTransition and custom shaders.

import std/[opt, syncio]
import ../[properties, clock, animation]
import ../graphics/[context_instructions, vertex_instructions, stencil_instructions,
  renderer]
import relativelayout

export relativelayout, opt

type
  TransitionState* = enum
    ## Screen.transition_state, in the order of Kivy's options.
    tsIn = "in"
    tsOut = "out"

  Screen* = ref object of RelativeLayout
    ## A page of a ScreenManager. uix/screenmanager.py Screen

  TransitionBase* = ref object of EventDispatcher
    ## A transition between two screens; build a subclass. Its events are
    ## `on_progress(progression)` and `on_complete`.
    ## uix/screenmanager.py TransitionBase
    anim: nil Animation          # Kivy's `_anim`

  NoTransition* = ref object of TransitionBase
    ## A switch without animation (duration 0). uix/screenmanager.py
    ## NoTransition

  ShaderTransition* = ref object of TransitionBase
    ## Both screens drawn into textures and mixed. Only the mix of
    ## FadeTransition exists. uix/screenmanager.py ShaderTransition
    fboIn, fboOut: nil Fbo
    renderCtx: nil FadeMix

  FadeTransition* = ref object of ShaderTransition
    ## The new screen fades in over the old one. uix/screenmanager.py
    ## FadeTransition

  ScreenManager* = ref object of FloatLayout
    ## Shows one of its screens at a time. uix/screenmanager.py ScreenManager
    nameUids: seq[(Screen, int)]   # the `name` binding on each managed screen

proc warn(msg: string) =
  # Kivy's Logger.warning, on stderr in Kivy's layout.
  stderr.writeLine "[WARNING] [ScreenManager] " & msg

proc objOf(v: Value): nil RootRef =
  if v.kind == vkObject: v.obj else: nil

proc toScreen(v: Value): nil Screen =
  let o = objOf(v)
  if o != nil and o of Screen: Screen(o) else: nil

# ------------------------------------------------------------------ Screen

proc noHandler(d: EventDispatcher; args: seq[Value]): bool =
  # The default handlers that do nothing (on_pre_enter, ...).
  false

let ScreenClass* = newDispatcherClass("Screen", RelativeLayoutClass)
  ## The class of `Screen`, with the events `on_pre_enter`, `on_enter`,
  ## `on_pre_leave` and `on_leave`.
let pName = ScreenClass.addString("name", "")
let pScreenManager = ScreenClass.addObject("manager", noneValue(), allowNone = true)
let pTransitionProgress = ScreenClass.addNumeric("transition_progress", 0.0)
let pTransitionState = ScreenClass.addOption("transition_state", "out", @["in", "out"])
for ev in ["on_pre_enter", "on_enter", "on_pre_leave", "on_leave"]:
  ScreenClass.addEvent(ev, noHandler)

proc initScreen*(s: Screen) =
  ## Sets up a new screen: the relative layout. Build a subclass with
  ## `T(cls: TClass, canvas: newCanvas())`, then call it.
  # Phase 1 until step 5: the typed properties of the base types.
  s.initProps()
  s.initRelativeLayout()

proc newScreen*(): Screen =
  ## An empty screen named "".
  result = Screen(cls: ScreenClass, canvas: newCanvas(), translate: nil)
  result.initScreen()

proc newScreen*(name: string): Screen =
  ## An empty screen called `name`.
  result = newScreen()
  discard pName.set(result, toValue(name))

proc name*(s: Screen): string =
  ## The name, unique in its manager (default "").
  pName.getString(s)
proc `name=`*(s: Screen; v: string) =
  ## Renames the screen.
  discard pName.set(s, toValue(v))

proc transitionProgress*(s: Screen): float =
  ## 0 to 1 while the screen comes in, 1 to 0 while it goes out.
  pTransitionProgress.getNumber(s)
proc `transitionProgress=`*(s: Screen; v: float) =
  ## Sets the transition progress.
  pTransitionProgress.setNumber(s, v)

proc transitionState*(s: Screen): TransitionState =
  ## Whether the screen is coming in or going out.
  TransitionState(pTransitionState.getOption(s))
proc `transitionState=`*(s: Screen; v: TransitionState) =
  ## Sets the transition state.
  pTransitionState.setOption(s, ord(v))

# ------------------------------------------------------------------ TransitionBase

let TransitionBaseClass* = newDispatcherClass("TransitionBase", EventDispatcherClass)
  ## The class of `TransitionBase`.
let pScreenOut = TransitionBaseClass.addObject("screen_out")
let pScreenIn = TransitionBaseClass.addObject("screen_in")
discard TransitionBaseClass.addNumeric("duration", 0.4)
let pTransitionManager = TransitionBaseClass.addObject("manager")
let pIsActive = TransitionBaseClass.addBoolean("is_active", false)

proc screenIn*(t: TransitionBase): nil Screen =
  ## The screen coming in.
  toScreen(pScreenIn.get(t))
proc `screenIn=`*(t: TransitionBase; s: Screen) =
  ## Sets the screen coming in.
  discard pScreenIn.set(t, toValue(s))

proc screenOut*(t: TransitionBase): nil Screen =
  ## The screen going out.
  toScreen(pScreenOut.get(t))
proc `screenOut=`*(t: TransitionBase; s: Screen) =
  ## Sets the screen going out.
  discard pScreenOut.set(t, toValue(s))

proc duration*(t: TransitionBase): float =
  ## Seconds (default .4; NoTransition 0).
  # By name: NoTransition declares its own `duration` with another default.
  t.getProperty("duration").num
proc `duration=`*(t: TransitionBase; v: float) =
  ## Sets the duration.
  t.setProperty("duration", toValue(v))

proc isActive*(t: TransitionBase): bool =
  ## Whether the transition is running.
  pIsActive.getBool(t)

proc anim*(t: TransitionBase): nil Animation {.inline.} =
  ## The Animation driving the running transition (Kivy's private `_anim`),
  ## nil when none runs.
  t.anim

proc mustScreen(s: nil Screen; what: string): Screen =
  # Python's AttributeError on None.
  if s == nil: quit "AttributeError: 'NoneType' object (" & what & ") has no attribute"
  result = s

proc manager*(t: TransitionBase): nil ScreenManager =
  ## The manager running the transition.
  let o = objOf(pTransitionManager.get(t))
  if o != nil and o of ScreenManager: ScreenManager(o) else: nil

proc mustManager(t: TransitionBase): ScreenManager =
  let m = t.manager
  if m == nil: quit "AttributeError: 'NoneType' object has no attribute (transition manager)"
  result = m

# ------------------------------------------------------------------ ScreenManager class

proc getScreenNames(d: EventDispatcher): Value
proc onCurrent(d: EventDispatcher; v: Value)

let ScreenManagerClass* = newDispatcherClass("ScreenManager", FloatLayoutClass)
  ## The class of `ScreenManager`.
let pCurrent = StringProperty(name: "", index: 0, defaultValue: noneValue(),
  allowNone: true, forceDispatch: false, comparator: nil)
ScreenManagerClass.addProperty("current", pCurrent)
let pTransition = ScreenManagerClass.addObject("transition")
let pScreens = ScreenManagerClass.addList("screens")
let pCurrentScreen = ScreenManagerClass.addObject("current_screen", noneValue(),
  allowNone = true)
let pScreenNames = ScreenManagerClass.addAlias("screen_names", getScreenNames, nil,
  @["screens"])
ScreenManagerClass.addPropertyHandler("current", onCurrent)

proc manager*(s: Screen): nil ScreenManager =
  ## The manager of the screen, or nil.
  let o = objOf(pScreenManager.get(s))
  if o != nil and o of ScreenManager: ScreenManager(o) else: nil

proc screens*(sm: ScreenManager): seq[Screen] =
  ## The managed screens, in the order they were added.
  result = @[]
  for v in pScreens.get(sm).items:
    let s = toScreen(v)
    if s != nil: result.add s

proc setScreens(sm: ScreenManager; screens: seq[Screen]) =
  # A new list, so it dispatches as Kivy's in-place append and remove do.
  var items: seq[Value] = @[]
  for s in screens: items.add toValue(s)
  discard pScreens.set(sm, toValue(items))

proc getScreenNames(d: EventDispatcher): Value =
  # ScreenManager._get_screen_names
  var items: seq[Value] = @[]
  for s in ScreenManager(d).screens: items.add toValue(s.name)
  result = toValue(items)

proc screenNames*(sm: ScreenManager): seq[string] =
  ## The names of the screens.
  result = @[]
  for v in pScreenNames.get(sm).items: result.add v.str

proc current*(sm: ScreenManager): Opt[string] =
  ## The name of the screen shown, or none.
  let v = pCurrent.get(sm)
  if v.kind == vkString: some(v.str) else: none[string]()
proc `current=`*(sm: ScreenManager; name: string) =
  ## Shows the screen called `name`, through the transition.
  discard pCurrent.set(sm, toValue(name))
proc `current=`*(sm: ScreenManager; name: Opt[string]) =
  ## Shows the screen called `name`; none shows nothing.
  if name.isSome: discard pCurrent.set(sm, toValue(name.get("")))
  else: discard pCurrent.set(sm, noneValue())

proc currentScreen*(sm: ScreenManager): nil Screen =
  ## The screen shown, or nil.
  toScreen(pCurrentScreen.get(sm))

proc transition*(sm: ScreenManager): TransitionBase =
  ## The transition used when `current` changes.
  let o = objOf(pTransition.get(sm))
  if o == nil or not (o of TransitionBase):
    quit "ScreenManager without a transition"
  result = TransitionBase(o)
proc `transition=`*(sm: ScreenManager; t: TransitionBase) =
  ## Sets the transition.
  discard pTransition.set(sm, toValue(t))

proc realAddWidget*(sm: ScreenManager; screen: Screen)
proc realRemoveWidget*(sm: ScreenManager; screen: Screen)

# ------------------------------------------------------------------ transitions

method addScreen*(t: TransitionBase; screen: Screen) {.base.} =
  ## Puts the screen coming in into the manager. TransitionBase.add_screen
  t.mustManager.realAddWidget(screen)

method removeScreen*(t: TransitionBase; screen: Screen) {.base.} =
  ## Takes the screen going out out of the manager.
  ## TransitionBase.remove_screen
  t.mustManager.realRemoveWidget(screen)

proc animProgress*(t: TransitionBase; progress: float) =
  ## Moves the screens' `transition_progress` and dispatches `on_progress`
  ## (Kivy's private `_on_progress`, which the Animation calls each frame).
  t.screenIn.mustScreen("screen_in").transitionProgress = progress
  t.screenOut.mustScreen("screen_out").transitionProgress = 1.0 - progress
  discard t.dispatch("on_progress", toValue(progress))

proc animComplete(t: TransitionBase) =
  # TransitionBase._on_complete
  discard pIsActive.set(t, toValue(false))
  discard t.dispatch("on_complete")
  discard t.screenIn.mustScreen("screen_in").dispatch("on_enter")
  discard t.screenOut.mustScreen("screen_out").dispatch("on_leave")
  t.anim = nil

method start*(t: TransitionBase; manager: ScreenManager) {.base.} =
  ## Starts the transition from `screen_out` to `screen_in`; stops the
  ## program if it is already running. TransitionBase.start
  if t.isActive:
    quit "ScreenManagerException: start() is called twice!"
  discard pTransitionManager.set(t, toValue(manager))
  let a = newAnimation(newSeq[(string, Value)](), duration = t.duration, step = 0)
  t.anim = a
  a.bind("on_progress", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    t.animProgress(args[^1].num)
    result = false)
  a.bind("on_complete", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    t.animComplete()
    result = false)
  let sIn = t.screenIn.mustScreen("screen_in")
  let sOut = t.screenOut.mustScreen("screen_out")
  t.addScreen(sIn)
  sIn.transitionProgress = 0
  sIn.transitionState = tsIn
  sOut.transitionProgress = 0
  sOut.transitionState = tsOut
  discard sIn.dispatch("on_pre_enter")
  discard sOut.dispatch("on_pre_leave")
  discard pIsActive.set(t, toValue(true))
  a.start(t)
  discard t.dispatch("on_progress", toValue(0))

method stop*(t: TransitionBase) {.base.} =
  ## Stops a running transition: it completes (`on_complete`) without the
  ## screens' `on_enter` and `on_leave`. TransitionBase.stop
  let a = t.anim
  if a != nil:
    a.cancel(t)
    discard t.dispatch("on_complete")
    t.anim = nil
  discard pIsActive.set(t, toValue(false))

proc transitionOnComplete(d: EventDispatcher; args: seq[Value]): bool =
  # TransitionBase.on_complete
  let t = TransitionBase(d)
  t.removeScreen(t.screenOut.mustScreen("screen_out"))
  result = false

TransitionBaseClass.addEvent("on_progress", noHandler)
TransitionBaseClass.addEvent("on_complete", transitionOnComplete)

proc noTransitionOnComplete(d: EventDispatcher; args: seq[Value]): bool =
  # NoTransition.on_complete
  let t = TransitionBase(d)
  let m = t.mustManager
  t.screenIn.mustScreen("screen_in").pos = m.pos
  t.screenOut.mustScreen("screen_out").pos = m.pos
  result = transitionOnComplete(d, args)

let NoTransitionClass* = newDispatcherClass("NoTransition", TransitionBaseClass)
  ## The class of `NoTransition`.
discard NoTransitionClass.addNumeric("duration", 0.0)
NoTransitionClass.setEventHandler("on_complete", noTransitionOnComplete)

proc initTransition*(t: TransitionBase) =
  ## Sets up a new transition (its properties). Build it with
  ## `T(cls: TClass)`, then call it.
  t.anim = nil
  t.initEventDispatcher()

proc newNoTransition*(): NoTransition =
  ## A transition that switches at the next frame.
  result = NoTransition(cls: NoTransitionClass, anim: nil)
  result.initTransition()

proc shaderOnProgress(d: EventDispatcher; args: seq[Value]): bool =
  # ShaderTransition.on_progress: `render_ctx['t'] = progress`
  let m = ShaderTransition(d).renderCtx
  if m != nil: m.t = args[0].num
  result = false

proc shaderOnComplete(d: EventDispatcher; args: seq[Value]): bool =
  # ShaderTransition.on_complete
  let m = ShaderTransition(d).renderCtx
  if m != nil: m.t = 1.0
  result = transitionOnComplete(d, args)

let ShaderTransitionClass* = newDispatcherClass("ShaderTransition", TransitionBaseClass)
  ## The class of `ShaderTransition`.
let pClearcolor = ShaderTransitionClass.addColor("clearcolor", @[0.0, 0.0, 0.0, 1.0])
ShaderTransitionClass.setEventHandler("on_progress", shaderOnProgress)
ShaderTransitionClass.setEventHandler("on_complete", shaderOnComplete)
# GAP: only FadeTransition's mix is drawn: the other ShaderTransitions and
# custom shaders (`fs`, `vs`) do not exist, because SDL_Renderer has no shaders
let FadeTransitionClass* = newDispatcherClass("FadeTransition", ShaderTransitionClass)
  ## The class of `FadeTransition`.

proc newFadeTransition*(): FadeTransition =
  ## A fade from the old screen to the new one, over `duration` (.4 s).
  result = FadeTransition(cls: FadeTransitionClass, anim: nil, fboIn: nil, fboOut: nil,
    renderCtx: nil)
  result.initTransition()

proc clearcolor*(t: ShaderTransition): array[4, float] =
  ## The colour the screens' textures are cleared to (opaque black).
  let f = pClearcolor.getFloats(t)
  result = [f[0], f[1], f[2], f[3]]
proc `clearcolor=`*(t: ShaderTransition; c: array[4, float]) =
  ## Sets the clear colour.
  pClearcolor.setFloats(t, c)

proc makeScreenFbo(t: ShaderTransition; screen: Screen): Fbo =
  # ShaderTransition.make_screen_fbo: the screen's canvas, moved to the
  # texture's origin, in a texture of the screen's size (Fbo's size is ints).
  let (w, h) = screen.size
  result = newFbo(int(w), int(h), t.clearcolor)
  result.add newPushMatrix()
  result.add newTranslate(-screen.x, -screen.y)
  result.add screen.canvas
  result.add newPopMatrix()

proc removeOutCanvas(t: ShaderTransition) =
  # ShaderTransition._remove_out_canvas
  let sOut = t.screenOut
  if sOut != nil:
    let m = t.mustManager
    if m.canvas.indexof(sOut.canvas) >= 0 and m.children.find(WidgetBase(sOut)) < 0:
      m.canvas.remove(sOut.canvas)

method addScreen*(t: ShaderTransition; screen: Screen) =
  ## Draws the screens into textures and shows their mix; neither screen
  ## is a child of the manager meanwhile. ShaderTransition.add_screen
  let m = t.mustManager
  let sIn = t.screenIn.mustScreen("screen_in")
  let sOut = t.screenOut.mustScreen("screen_out")
  sIn.pos = sOut.pos
  sIn.size = sOut.size
  m.realRemoveWidget(sOut)
  m.canvas.add(sOut.canvas)
  # Kivy removes the old screen's canvas from the manager before the frame
  # after the first one with the mix, from a Callback instruction in the
  # render context; Callback is out of scope, so it is scheduled now, for
  # before the next frame. The mix covers it either way.
  discard Clock.scheduleOnce(proc (dt: float) {.closure.} = t.removeOutCanvas(), -1)
  let fboIn = t.makeScreenFbo(sIn)
  let fboOut = t.makeScreenFbo(sOut)
  t.fboIn = fboIn
  t.fboOut = fboOut
  m.canvas.add(fboIn)
  m.canvas.add(fboOut)
  let mix = newFadeMix(fboOut, fboIn, sIn.pos, (float(fboIn.width), float(fboIn.height)))
  t.renderCtx = mix
  m.canvas.add(mix)

method removeScreen*(t: ShaderTransition; screen: Screen) =
  ## Removes the textures and the mix and puts the new screen back.
  ## ShaderTransition.remove_screen
  let m = t.mustManager
  let fboIn = t.fboIn
  let fboOut = t.fboOut
  let mix = t.renderCtx
  if fboIn != nil: m.canvas.remove(fboIn)
  if fboOut != nil: m.canvas.remove(fboOut)
  if mix != nil: m.canvas.remove(mix)
  t.removeOutCanvas()
  m.realAddWidget(t.screenIn.mustScreen("screen_in"))

method stop*(t: ShaderTransition) =
  ## ShaderTransition.stop
  t.removeOutCanvas()
  procCall stop(TransitionBase(t))

# ------------------------------------------------------------------ ScreenManager

proc applyStyle(sm: ScreenManager) =
  # data/style.kv <ScreenManager>: canvas.before StencilPush, Rectangle of
  # the box, StencilUse; canvas.after StencilUnUse, the Rectangle,
  # StencilPop. The kv bindings become observers of pos and size.
  let mask = newRectangle(sm.pos, sm.size)
  let unmask = newRectangle(sm.pos, sm.size)
  sm.canvas.before.add newStencilPush()
  sm.canvas.before.add mask
  sm.canvas.before.add newStencilUse()
  sm.canvas.after.add newStencilUnUse()
  sm.canvas.after.add unmask
  sm.canvas.after.add newStencilPop()
  discard sm.bindPos(proc (v: (float, float)) {.closure.} =
    mask.pos = v
    unmask.pos = v)
  discard sm.bindSize(proc (v: (float, float)) {.closure.} =
    mask.size = v
    unmask.size = v)

proc updatePos(sm: ScreenManager; value: (float, float)) =
  # ScreenManager._update_pos: the children follow the manager, except the
  # screens of a running transition.
  let t = sm.transition
  let sIn = t.screenIn
  let sOut = t.screenOut
  for child in sm.widgetChildren:
    let inTransition = (sIn != nil and child == Widget(sIn)) or
      (sOut != nil and child == Widget(sOut))
    if not (t.isActive and inTransition):
      child.pos = value

proc initScreenManager*(sm: ScreenManager) =
  ## Sets up a new manager: a NoTransition (Kivy's default, SlideTransition,
  ## is out of scope), the float layout, its style.kv canvas, and the
  ## children following `pos`. ScreenManager.__init__
  sm.nameUids = @[]
  # Phase 1 until step 5: the typed properties of the base types.
  sm.initProps()
  sm.initFloatLayout()
  # Kivy sets it before Widget.__init__; here the properties exist only after.
  sm.transition = newNoTransition()
  sm.applyStyle()
  discard sm.bindPos(proc (v: (float, float)) {.closure.} = sm.updatePos(v))

proc newScreenManager*(): ScreenManager =
  ## A manager without screens, with a NoTransition.
  result = ScreenManager(cls: ScreenManagerClass, canvas: newCanvas(), nameUids: @[])
  result.initScreenManager()

proc realAddWidget*(sm: ScreenManager; screen: Screen) =
  ## Adds the screen as a child, taking it from its previous parent first.
  ## ScreenManager.real_add_widget
  let parent = screen.parent
  if parent != nil:
    if parent of ScreenManager:
      ScreenManager(parent).realRemoveWidget(screen)
    else:
      quit "AttributeError: '" & parent.cls.name & "' object has no attribute " &
        "'real_remove_widget'"
  procCall addWidget(FloatLayout(sm), screen)

proc realRemoveWidget*(sm: ScreenManager; screen: Screen) =
  ## Removes the screen from the children. ScreenManager.real_remove_widget
  procCall removeWidget(FloatLayout(sm), screen)

proc getScreen*(sm: ScreenManager; name: string): Screen =
  ## The screen called `name`; none stops the program with Kivy's
  ## ScreenManagerException. ScreenManager.get_screen
  var matches: seq[Screen] = @[]
  for s in sm.screens:
    if s.name == name: matches.add s
  if matches.len == 0:
    quit "ScreenManagerException: No Screen with name \"" & name & "\"."
  if matches.len > 1:
    warn "Multiple screens named \"" & name & "\""
  result = matches[0]

proc hasScreen*(sm: ScreenManager; name: string): bool =
  ## Whether a screen is called `name`. ScreenManager.has_screen
  result = false
  for s in sm.screens:
    if s.name == name: return true

proc next*(sm: ScreenManager): Opt[string] =
  ## The name of the screen after the current one, wrapping round; none
  ## without screens or a current screen. ScreenManager.__next__
  let screens = sm.screens
  let cur = sm.currentScreen
  let i = if cur != nil: screens.find(cur) else: -1
  if screens.len == 0 or i < 0:
    result = none[string]()
  else:
    result = some(screens[(i + 1) mod screens.len].name)

proc previous*(sm: ScreenManager): Opt[string] =
  ## The name of the screen before the current one, wrapping round.
  ## ScreenManager.previous
  let screens = sm.screens
  let cur = sm.currentScreen
  let i = if cur != nil: screens.find(cur) else: -1
  if screens.len == 0 or i < 0:
    result = none[string]()
  else:
    result = some(screens[(i - 1 + screens.len) mod screens.len].name)

proc onCurrent(d: EventDispatcher; v: Value) =
  # ScreenManager.on_current: run the transition to the named screen.
  let sm = ScreenManager(d)
  if v.kind == vkNone:
    sm.transition.stop()
    discard pCurrentScreen.set(sm, noneValue())
    return
  let screen = sm.getScreen(v.str)
  let previous = sm.currentScreen
  if previous != nil and previous == screen:
    return
  let t = sm.transition
  t.stop()
  discard pCurrentScreen.set(sm, toValue(screen))
  if previous != nil:
    t.screenIn = screen
    t.screenOut = previous
    t.start(sm)
  else:
    sm.realAddWidget(screen)
    screen.pos = sm.pos
    sm.doLayout()
    discard screen.dispatch("on_pre_enter")
    discard screen.dispatch("on_enter")

proc screenNameChanged(sm: ScreenManager): PropertyCallback =
  # ScreenManager._screen_name_changed, bound to each screen's `name`.
  result = proc (d: EventDispatcher; v: Value) {.closure.} =
    pScreenNames.dispatch(sm)
    if sm.currentScreen == Screen(d):
      sm.current = v.str

method addWidget*(sm: ScreenManager; widget: WidgetBase; index = 0; canvas = layerCanvas) =
  ## Manages a screen; the first one becomes `current`. Only screens that
  ## have no manager are accepted (else the program stops with Kivy's
  ## ScreenManagerException). ScreenManager.add_widget
  if not (widget of Screen):
    quit "ScreenManagerException: ScreenManager accepts only Screen widget."
  let s = Screen(widget)
  let m = s.manager
  if m != nil:
    if m == sm:
      quit "ScreenManagerException: Screen already managed by this ScreenManager " &
        "(are you calling `switch_to` when you should be setting `current`?)"
    quit "ScreenManagerException: Screen already managed by another ScreenManager."
  discard pScreenManager.set(s, toValue(sm))
  sm.nameUids.add (s, s.fbind("name", sm.screenNameChanged()))
  var screens = sm.screens
  screens.add s
  sm.setScreens(screens)
  if sm.current.isNone:
    sm.current = s.name

method removeWidget*(sm: ScreenManager; widget: WidgetBase) =
  ## Stops managing a screen; if it is shown, the next one is shown, or
  ## none if it was the only one. ScreenManager.remove_widget
  if not (widget of Screen):
    quit "ScreenManagerException: ScreenManager uses remove_widget only for removing Screens."
  let s = Screen(widget)
  if sm.screens.find(s) < 0:
    return
  if sm.currentScreen == s:
    let other = sm.next
    if other.isSome and s.name == other.get(""):
      sm.current = none[string]()
      let parent = s.parent
      if parent != nil and parent of ScreenManager:
        ScreenManager(parent).realRemoveWidget(s)
      else:
        quit "AttributeError: 'NoneType' object has no attribute 'real_remove_widget'"
    else:
      sm.current = other
  discard pScreenManager.set(s, noneValue())
  var k = 0
  while k < sm.nameUids.len:
    if sm.nameUids[k][0] == s:
      s.unbindUid("name", sm.nameUids[k][1])
      sm.nameUids.delete(k)
    else:
      inc k
  var screens = sm.screens
  screens.delete(screens.find(s))
  sm.setScreens(screens)

proc clearWidgets*(sm: ScreenManager; children: seq[Screen]) =
  ## Stops managing the given screens. ScreenManager.clear_widgets
  for s in children:
    sm.removeWidget(s)

proc clearWidgets*(sm: ScreenManager) =
  ## Stops managing every screen. ScreenManager.clear_widgets
  sm.clearWidgets(sm.screens)

proc generateScreenName(sm: ScreenManager): string =
  # ScreenManager._generate_screen_name
  var i = 0
  while true:
    result = "_screen" & $i
    if not sm.hasScreen(result):
      break
    inc i

proc switchTo*(sm: ScreenManager; screen: Screen; transition: nil TransitionBase = nil) =
  ## Adds the screen if it is not managed yet (renamed if its name is
  ## taken) and shows it, with `transition` if given; the screen shown
  ## before is removed when the transition completes. Kivy's other options
  ## (set on the transition) are set by the caller on the transition.
  ## ScreenManager.switch_to
  sm.transition.stop()
  if sm.screens.find(screen) < 0:
    if sm.hasScreen(screen.name):
      screen.name = sm.generateScreenName()
  let oldTransition = sm.transition
  if transition != nil:
    sm.transition = transition
  if screen.manager != sm:
    sm.addWidget(screen)
  if sm.currentScreen == screen:
    return
  let oldCurrent = sm.currentScreen
  var uid = 0
  let removeOldScreen = proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
    let old = oldCurrent
    if old != nil:
      if sm.children.find(WidgetBase(old)) >= 0:
        sm.removeWidget(old)
        sm.transition = oldTransition
    d.unbindUid("on_complete", uid)
    result = false
  uid = sm.transition.fbind("on_complete", removeOldScreen)
  sm.current = screen.name

method onTouchDown*(sm: ScreenManager; touch: MotionEvent): bool =
  ## Ignored while a transition runs. ScreenManager.on_touch_down
  if sm.transition.isActive: false
  else: procCall onTouchDown(FloatLayout(sm), touch)

method onTouchMove*(sm: ScreenManager; touch: MotionEvent): bool =
  ## Ignored while a transition runs. ScreenManager.on_touch_move
  if sm.transition.isActive: false
  else: procCall onTouchMove(FloatLayout(sm), touch)

method onTouchUp*(sm: ScreenManager; touch: MotionEvent): bool =
  ## Ignored while a transition runs. ScreenManager.on_touch_up
  if sm.transition.isActive: false
  else: procCall onTouchUp(FloatLayout(sm), touch)
