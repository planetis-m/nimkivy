## The screen manager: Kivy's `kivy/uix/screenmanager.py` (Screen,
## ScreenManager, TransitionBase, NoTransition, ShaderTransition,
## FadeTransition), with the ScreenManager rule from `kivy/data/style.kv`.
##
## A ScreenManager is a FloatLayout that shows one Screen at a time, clipped
## to its box by a stencil. Setting `current` to a screen's name runs the
## `transition` from the current screen to it: the new screen gets
## `preEnter` and the old one `preLeave`; at the end the old one is removed
## from the children, and they get `enter` and `leave`. Touches are ignored
## while a transition runs.
##
## FadeTransition draws both screens into textures cleared to opaque black
## (`Fbo` in `graphics/renderer`) and shows `t*in + (1-t)*out`; during it
## neither screen is in `children`. NoTransition switches at the next frame.
##
## Build them with `newScreen`, `newScreenManager`, `newNoTransition` and
## `newFadeTransition`; a subclass's constructor makes the object, calls
## `initProps`, then the `init` proc (`initScreen`, `initScreenManager`,
## `initTransition`).
##
## Out of scope (SCOPE.md): SlideTransition, SwapTransition, CardTransition,
## WipeTransition, FallOutTransition, RiseInTransition and custom shaders.

import std/[opt, syncio]
import ../[props, clock, animation]
import ../graphics/[context_instructions, vertex_instructions, stencil_instructions,
  renderer]
import relativelayout

export relativelayout, opt

type
  TransitionState* = enum
    ## Screen.transition_state, in the order of Kivy's options.
    tsIn = "in"
    tsOut = "out"

proc warn(msg: string) =
  # Kivy's Logger.warning, on stderr in Kivy's layout.
  stderr.writeLine "[WARNING] [ScreenManager] " & msg

# ------------------------------------------------------------------ Screen

properties:
  type
    Screen* = ref object of RelativeLayout
      ## A page of a ScreenManager. uix/screenmanager.py Screen
      name* {.prop.}: string = ""  ## the name, unique in its manager
      # GAP: `manager` is a FloatLayout (convert it to ScreenManager), because
      # ScreenManager, which holds a `seq[Screen]`, cannot be declared in the
      # same `properties:` block as Screen (planetis-m/nimony-bugs-llms#337)
      manager* {.prop.}: nil FloatLayout = nil
        ## the ScreenManager that manages the screen, or nil
      transitionProgress* {.prop.}: float = 0.0
        ## 0 to 1 while the screen comes in, 1 to 0 while it goes out
      transitionState* {.prop.}: TransitionState = tsOut
        ## whether the screen is coming in or going out
      preEnter* {.event.}: proc ()   ## the screen is about to come in
      enter* {.event.}: proc ()      ## the screen came in
      preLeave* {.event.}: proc ()   ## the screen is about to go out
      leave* {.event.}: proc ()      ## the screen went out

  proc initScreen*(s: Screen) =
    ## Sets up a new screen whose properties `initProps` has set: the
    ## relative layout.
    s.initRelativeLayout()

  proc newScreen*(): Screen =
    ## An empty screen named "".
    result = Screen(canvas: newCanvas(), translate: nil)
    result.initProps()
    result.initScreen()

  proc newScreen*(name: sink string): Screen =
    ## An empty screen called `name`.
    result = newScreen()
    result.name = name

  proc mustScreen(s: sink nil Screen; what: string): Screen =
    # A transition's screen, which must be set while it runs.
    if s == nil: quit "TransitionBase: no " & what & " while running"
    result = s

# ------------------------------------------------------------------ transitions and ScreenManager

properties:
  type
    TransitionBase* = ref object of RootObj
      ## A transition between two screens; build a subclass.
      ## uix/screenmanager.py TransitionBase
      anim: nil Animation          # Kivy's `_anim`
      screenOut* {.prop.}: nil Screen = nil  ## the screen going out
      screenIn* {.prop.}: nil Screen = nil   ## the screen coming in
      duration* {.prop.}: float = 0.4        ## seconds
      manager* {.prop.}: nil ScreenManager = nil  ## the manager running it
      isActive* {.prop.}: bool = false       ## the transition is running
      progress* {.event.}: proc (progression: float)
        ## a step, 0 to 1
      complete* {.event.}: proc ()  ## the transition ended or was stopped

    NoTransition* {.defaults: (duration: 0.0).} = ref object of TransitionBase
      ## A switch without animation (duration 0). uix/screenmanager.py
      ## NoTransition

    ShaderTransition* = ref object of TransitionBase
      ## Both screens drawn into textures and mixed. Only the mix of
      ## FadeTransition exists. uix/screenmanager.py ShaderTransition
      fboIn, fboOut: nil Fbo
      renderCtx: nil FadeMix
      clearcolor* {.color.}: Rgba = [0.0, 0, 0, 1]
        ## the colour the screens' textures are cleared to

    FadeTransition* = ref object of ShaderTransition
      ## The new screen fades in over the old one. uix/screenmanager.py
      ## FadeTransition

    ScreenManager* = ref object of FloatLayout
      ## Shows one of its screens at a time. uix/screenmanager.py ScreenManager
      nameBindings: seq[(Screen, Binding)]  # the `name` binding on each screen
      current* {.prop, handler.}: Opt[string] = none[string]()
        ## the name of the screen shown, or none
      transitionValue: nil TransitionBase  # `transition`; nil until set up
      transition* {.alias: (getTransition, setTransition).}: TransitionBase
        ## the transition used when `current` changes (a NoTransition, as
        ## Kivy's default SlideTransition is out of scope)
      screens* {.prop.}: seq[Screen] = @[]
        ## the managed screens, in the order they were added; read only
      currentScreen* {.prop.}: nil Screen = nil  ## the screen shown, or nil
      screenNames* {.alias: getScreenNames, deps: screens, eager.}: seq[string]
        ## the names of the screens

  # ---------------------------------------------------------------- TransitionBase

  proc initTransition*(t: TransitionBase) =
    ## Sets up a new transition whose properties `initProps` has set.
    t.anim = nil

  proc newNoTransition*(): NoTransition =
    ## A transition that switches at the next frame.
    result = NoTransition(anim: nil)
    result.initProps()
    result.initTransition()

  proc newFadeTransition*(): FadeTransition =
    ## A fade from the old screen to the new one, over `duration` (.4 s).
    result = FadeTransition(anim: nil, fboIn: nil, fboOut: nil, renderCtx: nil)
    result.initProps()
    result.initTransition()

  proc anim*(t: TransitionBase): nil Animation {.inline.} =
    ## The Animation driving the running transition (Kivy's private
    ## `_anim`), nil when none runs.
    t.anim

  proc mustManager(t: TransitionBase): ScreenManager =
    let m = t.manager
    if m == nil: quit "TransitionBase: no manager while running"
    result = m

  proc realAddWidget*(sm: ScreenManager; screen: sink Screen)
  proc realRemoveWidget*(sm: ScreenManager; screen: Screen)

  method addScreen*(t: TransitionBase; screen: sink Screen) {.base.} =
    ## Puts the screen coming in into the manager. TransitionBase.add_screen
    t.mustManager.realAddWidget(screen)

  method removeScreen*(t: TransitionBase; screen: Screen) {.base.} =
    ## Takes the screen going out out of the manager.
    ## TransitionBase.remove_screen
    t.mustManager.realRemoveWidget(screen)

  method onComplete*(t: TransitionBase): bool {.base.} =
    ## Removes the screen going out. TransitionBase.on_complete
    t.removeScreen(t.screenOut.mustScreen("screenOut"))
    result = false

  proc animProgress*(t: TransitionBase; progress: float) =
    ## Moves the screens' `transitionProgress` and dispatches `progress`
    ## (Kivy's private `_on_progress`, which the Animation calls each frame).
    t.screenIn.mustScreen("screenIn").transitionProgress = progress
    t.screenOut.mustScreen("screenOut").transitionProgress = 1.0 - progress
    discard t.dispatchProgress(progress)

  proc animComplete(t: TransitionBase) =
    # TransitionBase._on_complete
    t.isActive = false
    discard t.dispatchComplete()
    discard t.screenIn.mustScreen("screenIn").dispatchEnter()
    discard t.screenOut.mustScreen("screenOut").dispatchLeave()
    t.anim = nil

  method start*(t: TransitionBase; manager: ScreenManager) {.base.} =
    ## Starts the transition from `screenOut` to `screenIn`; stops the
    ## program if it is already running. TransitionBase.start
    if t.isActive:
      quit "the transition is already running"
    t.manager = manager
    let a = newAnimation(newSeq[Track](), duration = t.duration, step = 0)
    t.anim = a
    discard a.bindProgress(proc (target: RootRef; progress: float): bool {.closure.} =
      t.animProgress(progress)
      result = false)
    discard a.bindComplete(proc (target: RootRef): bool {.closure.} =
      t.animComplete()
      result = false)
    let sIn = t.screenIn.mustScreen("screenIn")
    let sOut = t.screenOut.mustScreen("screenOut")
    t.addScreen(sIn)
    sIn.transitionProgress = 0
    sIn.transitionState = tsIn
    sOut.transitionProgress = 0
    sOut.transitionState = tsOut
    discard sIn.dispatchPreEnter()
    discard sOut.dispatchPreLeave()
    t.isActive = true
    a.start(t)
    discard t.dispatchProgress(0)

  method stop*(t: TransitionBase) {.base.} =
    ## Stops a running transition: it completes (`complete`) without the
    ## screens' `enter` and `leave`. TransitionBase.stop
    let a = t.anim
    if a != nil:
      a.cancel(t)
      discard t.dispatchComplete()
      t.anim = nil
    t.isActive = false

  method onComplete*(t: NoTransition): bool =
    ## Puts both screens at the manager's position, then removes the screen
    ## going out. NoTransition.on_complete
    let m = t.mustManager
    t.screenIn.mustScreen("screenIn").pos = m.pos
    t.screenOut.mustScreen("screenOut").pos = m.pos
    result = procCall onComplete(TransitionBase(t))

  # ---------------------------------------------------------------- ShaderTransition

  # GAP: only FadeTransition's mix is drawn: the other ShaderTransitions and
  # custom shaders (`fs`, `vs`) do not exist, because SDL_Renderer has no shaders
  method onProgress*(t: ShaderTransition; progression: float): bool =
    ## The mix follows the progress. ShaderTransition.on_progress
    let m = t.renderCtx
    if m != nil: m.t = progression
    result = false

  method onComplete*(t: ShaderTransition): bool =
    ## The mix shows the new screen alone, then the old one is removed.
    ## ShaderTransition.on_complete
    let m = t.renderCtx
    if m != nil: m.t = 1.0
    result = procCall onComplete(TransitionBase(t))

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

  method addScreen*(t: ShaderTransition; screen: sink Screen) =
    ## Draws the screens into textures and shows their mix; neither screen
    ## is a child of the manager meanwhile. ShaderTransition.add_screen
    let m = t.mustManager
    let sIn = t.screenIn.mustScreen("screenIn")
    let sOut = t.screenOut.mustScreen("screenOut")
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
    m.realAddWidget(t.screenIn.mustScreen("screenIn"))

  method stop*(t: ShaderTransition) =
    ## ShaderTransition.stop
    t.removeOutCanvas()
    procCall stop(TransitionBase(t))

  # ---------------------------------------------------------------- ScreenManager

  proc getScreenNames(sm: ScreenManager): seq[string] =
    # ScreenManager._get_screen_names
    result = @[]
    for s in sm.screens: result.add s.name

  proc `current=`*(sm: ScreenManager; name: sink string) =
    ## Shows the screen called `name`, through the transition.
    sm.current = some(name)

  proc getTransition(sm: ScreenManager): TransitionBase =
    # `transition`, which a manager always has once set up (Kivy's
    # ObjectProperty without allownone).
    let t = sm.transitionValue
    if t == nil: quit "ScreenManager: initScreenManager was not called"
    result = t

  proc setTransition(sm: ScreenManager; t: sink TransitionBase): bool =
    # ObjectProperty.set: a dispatch when the object changes.
    result = sm.transitionValue != t
    sm.transitionValue = t

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
    ## Sets up a new manager whose properties `initProps` has set: the float
    ## layout, its style.kv canvas, and the children following `pos`.
    ## ScreenManager.__init__
    sm.nameBindings = @[]
    # Kivy sets it before Widget.__init__, when nothing observes it yet.
    sm.transitionValue = newNoTransition()
    sm.initFloatLayout()
    sm.applyStyle()
    discard sm.bindPos(proc (v: (float, float)) {.closure.} = sm.updatePos(v))

  proc newScreenManager*(): ScreenManager =
    ## A manager without screens, with a NoTransition.
    result = ScreenManager(canvas: newCanvas(), nameBindings: @[],
      transitionValue: nil)
    result.initProps()
    result.initScreenManager()

  proc realAddWidget*(sm: ScreenManager; screen: sink Screen) =
    ## Adds the screen as a child, taking it from its previous parent first.
    ## ScreenManager.real_add_widget
    let parent = screen.parent
    if parent != nil:
      if parent of ScreenManager:
        ScreenManager(parent).realRemoveWidget(screen)
      else:
        quit "ScreenManager.realAddWidget: the screen's parent is not a ScreenManager"
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
      quit "no screen called \"" & name & "\""
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

  method onCurrentChanged*(sm: ScreenManager; v: Opt[string]) {.base.} =
    ## Runs the transition to the screen called `v`; none shows nothing.
    ## ScreenManager.on_current
    if v.isNone:
      sm.transition.stop()
      sm.currentScreen = nil
      return
    let screen = sm.getScreen(v.get(""))
    let previous = sm.currentScreen
    if previous != nil and previous == screen:
      return
    let t = sm.transition
    t.stop()
    sm.currentScreen = screen
    if previous != nil:
      t.screenIn = screen
      t.screenOut = previous
      t.start(sm)
    else:
      sm.realAddWidget(screen)
      screen.pos = sm.pos
      sm.doLayout()
      discard screen.dispatchPreEnter()
      discard screen.dispatchEnter()

  # GAP: `widget` is not sink, because a captured sink parameter is never freed
  # (planetis-m/nimony-bugs-llms#348; WindowBase's override captures it, and an
  # override keeps its base's signature)
  method addWidget*(sm: ScreenManager; widget: WidgetBase; index = 0; canvas = layerCanvas) =
    ## Manages a screen; the first one becomes `current`. Only screens that
    ## have no manager are accepted (else the program stops with Kivy's
    ## ScreenManagerException). ScreenManager.add_widget
    if not (widget of Screen):
      quit "a ScreenManager takes only Screens"
    let s = Screen(widget)
    let m = s.manager
    if m != nil:
      if m == FloatLayout(sm):
        quit "the screen is already managed by this ScreenManager " &
          "(call switchTo only with a new screen; set current to show a managed one)"
      quit "the screen is already managed by another ScreenManager"
    s.manager = sm
    # ScreenManager._screen_name_changed, bound to the screen's `name`.
    let b = s.bindName(proc (v: string) {.closure.} =
      sm.dispatchScreenNames()
      if sm.currentScreen == s:
        sm.current = v)
    sm.nameBindings.add (s, b)
    var screens = sm.screens
    screens.add s
    sm.screens = screens
    if sm.current.isNone:
      sm.current = s.name

  method removeWidget*(sm: ScreenManager; widget: WidgetBase) =
    ## Stops managing a screen; if it is shown, the next one is shown, or
    ## none if it was the only one. ScreenManager.remove_widget
    if not (widget of Screen):
      quit "a ScreenManager removes only Screens"
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
          quit "ScreenManager.removeWidget: the screen shown has no ScreenManager parent"
      else:
        sm.current = other
    s.manager = nil
    var k = 0
    while k < sm.nameBindings.len:
      if sm.nameBindings[k][0] == s:
        s.unbindName(sm.nameBindings[k][1])
        sm.nameBindings.delete(k)
      else:
        inc k
    var screens = sm.screens
    screens.delete(screens.find(s))
    sm.screens = screens

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

  proc switchTo*(sm: ScreenManager; screen: sink Screen;
      transition: sink nil TransitionBase = nil) =
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
    if screen.manager != FloatLayout(sm):
      sm.addWidget(screen)
    if sm.currentScreen == screen:
      return
    let oldCurrent = sm.currentScreen
    let t = sm.transition
    var b = Binding(0)
    b = t.bindComplete(proc (): bool {.closure.} =
      let old = oldCurrent
      if old != nil:
        if sm.children.find(WidgetBase(old)) >= 0:
          sm.removeWidget(old)
          sm.transition = oldTransition
      t.unbindComplete(b)
      result = false)
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
