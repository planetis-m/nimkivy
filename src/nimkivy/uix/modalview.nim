## The modal view: Kivy's `kivy/uix/modalview.py` (ModalView), with its rule
## from `kivy/data/style.kv`.
##
## A ModalView is an AnchorLayout that `open` adds to the Window, centred on
## it (and kept centred), over everything else. Its canvas darkens the whole
## window with `overlay_color` and draws its box in `background_color`. It
## fades in and out over `_anim_duration`. Touches inside it go to its
## content; a touch that starts outside it dismisses it when it ends, if
## `auto_dismiss` is set; every touch is swallowed. Escape (key 27)
## dismisses it too, with `auto_dismiss`.
##
## `background` is an image path for the BorderImage. Kivy's default is an
## atlas image, and atlas is out of scope (SCOPE.md), so the default here is
## `""`: a plain box of `background_color` (white).
##
## Out of scope (SCOPE.md): the deprecated `attach_to`, and Popup.

import ../[properties, animation]
import ../graphics/[context_instructions, vertex_instructions]
import ../core/image
import anchorlayout

export anchorlayout

type
  ModalView* = ref object of AnchorLayout
    ## uix/modalview.py ModalView
    touchStartedInside: int        # Kivy's `_touch_started_inside`: -1 None, 0 False, 1 True
    windowBindings: array[2, Binding] # the Window's `resize` and `keyboard` while open

proc noHandler(d: EventDispatcher; args: seq[Value]): bool =
  # The default handlers on_pre_open, on_open, on_pre_dismiss, on_dismiss.
  false

proc onAnimAlpha(d: EventDispatcher; v: Value)

let ModalViewClass* = newDispatcherClass("ModalView", AnchorLayoutClass)
  ## The class of `ModalView`, with the events `on_pre_open`, `on_open`,
  ## `on_pre_dismiss` and `on_dismiss` (an observer returning true keeps
  ## the view open).
let pAutoDismiss = ModalViewClass.addBoolean("auto_dismiss", true)
let pBackgroundColor = ModalViewClass.addColor("background_color", @[1.0, 1, 1, 1])
let pBackground = ModalViewClass.addString("background", "")
let pBorder = ModalViewClass.addList("border",
  @[toValue(16), toValue(16), toValue(16), toValue(16)])
let pOverlayColor = ModalViewClass.addColor("overlay_color", @[0.0, 0, 0, 0.7])
let pAnimAlpha = ModalViewClass.addNumeric("_anim_alpha", 0)
let pAnimDuration = ModalViewClass.addNumeric("_anim_duration", 0.1)
let pWindow = ModalViewClass.addObject("_window", noneValue(), allowNone = true)
let pIsOpen = ModalViewClass.addBoolean("_is_open", false)
for ev in ["on_pre_open", "on_open", "on_pre_dismiss", "on_dismiss"]:
  ModalViewClass.addEvent(ev, noHandler)
ModalViewClass.addPropertyHandler("_anim_alpha", onAnimAlpha)

# ------------------------------------------------------------------ accessors

proc rgba(v: Value): array[4, float] =
  let f = v.toFloats
  result = [f[0], f[1], f[2], f[3]]

proc autoDismiss*(m: ModalView): bool =
  ## Whether a touch outside or Escape dismisses the view (default true).
  pAutoDismiss.getBool(m)
proc `autoDismiss=`*(m: ModalView; v: bool) =
  ## Sets `auto_dismiss`.
  discard pAutoDismiss.set(m, toValue(v))

proc backgroundColor*(m: ModalView): array[4, float] =
  ## The colour of the box (multiplies the background image).
  rgba(pBackgroundColor.get(m))
proc `backgroundColor=`*(m: ModalView; c: array[4, float]) =
  ## Sets the box colour.
  pBackgroundColor.setFloats(m, c)

proc background*(m: ModalView): string =
  ## The image of the box's BorderImage; "" (the default) is a plain box.
  pBackground.getString(m)
proc `background=`*(m: ModalView; v: string) =
  ## Sets the background image.
  discard pBackground.set(m, toValue(v))

proc border*(m: ModalView): seq[float] =
  ## The BorderImage's borders: bottom, right, top, left (default 16).
  pBorder.getFloats(m)
proc `border=`*(m: ModalView; b: openArray[float]) =
  ## Sets the borders.
  pBorder.setFloats(m, b)

proc overlayColor*(m: ModalView): array[4, float] =
  ## The colour over the whole window behind the view (default black, .7).
  rgba(pOverlayColor.get(m))
proc `overlayColor=`*(m: ModalView; c: array[4, float]) =
  ## Sets the overlay colour.
  pOverlayColor.setFloats(m, c)

proc animAlpha*(m: ModalView): float =
  ## How far the view has faded in (Kivy's private `_anim_alpha`).
  pAnimAlpha.getNumber(m)

proc animDuration*(m: ModalView): float =
  ## The fade's duration in seconds (Kivy's private `_anim_duration`, .1).
  pAnimDuration.getNumber(m)
proc `animDuration=`*(m: ModalView; v: float) =
  ## Sets the fade's duration.
  pAnimDuration.setNumber(m, v)

proc window*(m: ModalView): nil WindowBase =
  ## The window the view is open in, or nil (Kivy's private `_window`).
  let v = pWindow.get(m)
  if v.kind == vkObject and v.obj != nil and v.obj of WindowBase: WindowBase(v.obj)
  else: nil

proc isOpen*(m: ModalView): bool =
  ## Whether the view is open (Kivy's private `_is_open`).
  pIsOpen.getBool(m)

# ------------------------------------------------------------------ canvas

proc applyStyle(m: ModalView) =
  # data/style.kv <ModalView>: Color(overlay_color with alpha times
  # _anim_alpha), a Rectangle of the window's size at (0, 0), Color
  # (background_color), BorderImage(source: background, border, pos,
  # size). Each kv binding becomes an observer; `_window` has `rebind`, so
  # the rectangle also follows the size of the window it holds.
  let overlay = newColor()
  let shade = newRectangle((0.0, 0.0), (0.0, 0.0))
  let bg = newColor()
  let box = newBorderImage(m.pos, m.size, m.border)
  proc setOverlay(m: ModalView; overlay: Color) =
    let c = m.overlayColor
    overlay.rgba = [c[0], c[1], c[2], c[3] * m.animAlpha]
  m.setOverlay(overlay)
  bg.rgba = m.backgroundColor
  box.source = m.background
  let c = m.canvas
  c.add overlay
  c.add shade
  c.add bg
  c.add box
  for name in ["overlay_color", "_anim_alpha"]:
    discard m.fbind(name, proc (d: EventDispatcher; v: Value) {.closure.} =
      m.setOverlay(overlay))
  var sizeBinding = Binding(0)
  var sizeOf: nil WindowBase = nil
  discard m.fbind("_window", proc (d: EventDispatcher; v: Value) {.closure.} =
    let old = sizeOf
    if old != nil and sizeBinding != Binding(0):
      old.unbindSize(sizeBinding)
    sizeBinding = Binding(0)
    sizeOf = nil
    let w = m.window
    if w != nil:
      shade.size = w.size
      sizeOf = w
      sizeBinding = w.bindSize(proc (v: (float, float)) {.closure.} = shade.size = v)
    else:
      shade.size = (0.0, 0.0))
  discard m.fbind("background_color", proc (d: EventDispatcher; v: Value) {.closure.} =
    bg.rgba = rgba(v))
  discard m.fbind("background", proc (d: EventDispatcher; v: Value) {.closure.} =
    box.source = v.str)
  discard m.fbind("border", proc (d: EventDispatcher; v: Value) {.closure.} =
    box.border = v.toFloats)
  discard m.bindPos(proc (v: (float, float)) {.closure.} = box.pos = v)
  discard m.bindSize(proc (v: (float, float)) {.closure.} = box.size = v)

# ------------------------------------------------------------------ construction

proc initModalView*(m: ModalView) =
  ## Sets up a new modal view: the anchor layout and its style.kv canvas.
  ## Build a subclass with `T(cls: TClass, canvas: newCanvas())`, then call
  ## it. ModalView.__init__
  m.touchStartedInside = -1
  m.windowBindings = [Binding(0), Binding(0)]
  # Phase 1 until step 5: the typed properties of the base types.
  m.initProps()
  m.initAnchorLayout()
  m.applyStyle()

proc newModalView*(): ModalView =
  ## A modal view that fills the window (size_hint 1, 1) until hinted.
  result = ModalView(cls: ModalViewClass, canvas: newCanvas(), touchStartedInside: -1,
    windowBindings: [Binding(0), Binding(0)])
  result.initModalView()

# ------------------------------------------------------------------ open, dismiss

proc alignCenter(m: ModalView) =
  # ModalView._align_center
  if m.isOpen:
    let w = m.window
    if w != nil:
      m.center = w.center

proc realRemoveWidget(m: ModalView) =
  # ModalView._real_remove_widget
  if not m.isOpen:
    return
  let w = m.window
  if w != nil:
    w.removeWidget(m)
    w.unbindResize(m.windowBindings[0])
    w.unbindKeyboard(m.windowBindings[1])
  m.windowBindings = [Binding(0), Binding(0)]
  discard pIsOpen.set(m, toValue(false))
  discard pWindow.set(m, noneValue())

proc onAnimAlpha(d: EventDispatcher; v: Value) =
  # ModalView.on__anim_alpha: removed once faded out.
  let m = ModalView(d)
  if v.num == 0 and m.isOpen:
    m.realRemoveWidget()

proc dismiss*(m: ModalView; animation = true; force = false)

proc handleKeyboard(m: ModalView; key: int): bool =
  # ModalView._handle_keyboard
  result = false
  if key == 27 and m.autoDismiss:
    m.dismiss()
    result = true

proc open*(m: ModalView; animation = true) =
  ## Adds the view to the Window, centred, and fades it in (at once
  ## without `animation`); `on_open` comes at the end. ModalView.open
  if m.isOpen:
    return
  let win = Window
  discard pWindow.set(m, toValue(RootRef(win)))
  discard pIsOpen.set(m, toValue(true))
  discard m.dispatch("on_pre_open")
  win.addWidget(m)
  m.windowBindings = [
    win.bindResize(proc (width, height: float): bool {.closure.} =
      m.alignCenter()
      result = false),
    win.bindKeyboard(proc (key, scancode: int; codepoint: string;
        modifiers: set[Modifier]): bool {.closure.} =
      m.handleKeyboard(key))]
  m.center = win.center
  # Kivy binds these on every open and never unbinds them.
  discard m.bindCenter(proc (v: (float, float)) {.closure.} = m.alignCenter())
  discard m.bindSize(proc (v: (float, float)) {.closure.} = m.alignCenter())
  if animation:
    let ani = newAnimation({"_anim_alpha": 1.0}, duration = m.animDuration)
    ani.bind("on_complete", proc (d: EventDispatcher; args: seq[Value]): bool {.closure.} =
      discard m.dispatch("on_open")
      result = false)
    ani.start(m)
  else:
    pAnimAlpha.setNumber(m, 1.0)
    discard m.dispatch("on_open")

proc dismiss*(m: ModalView; animation = true; force = false) =
  ## Fades the view out and removes it (at once without `animation`). An
  ## `on_dismiss` observer returning true keeps it open, unless `force`.
  ## ModalView.dismiss
  if not m.isOpen:
    return
  discard m.dispatch("on_pre_dismiss")
  if m.dispatch("on_dismiss"):
    if not force:
      return
  if animation:
    newAnimation({"_anim_alpha": 0.0}, duration = m.animDuration).start(m)
  else:
    pAnimAlpha.setNumber(m, 0.0)
    m.realRemoveWidget()

# ------------------------------------------------------------------ touches

method onTouchDown*(m: ModalView; touch: MotionEvent): bool =
  ## Passes a touch inside on to the content (any touch without
  ## `auto_dismiss`) and swallows it. ModalView.on_touch_down
  let inside = m.collidePoint(touch.pos[0], touch.pos[1])
  m.touchStartedInside = if inside: 1 else: 0
  if not m.autoDismiss or inside:
    discard procCall onTouchDown(AnchorLayout(m), touch)
  result = true

method onTouchMove*(m: ModalView; touch: MotionEvent): bool =
  ## Passes the move on as the touch down was, and swallows it.
  ## ModalView.on_touch_move
  if not m.autoDismiss or m.touchStartedInside == 1:
    discard procCall onTouchMove(AnchorLayout(m), touch)
  result = true

method onTouchUp*(m: ModalView; touch: MotionEvent): bool =
  ## Dismisses the view if the touch started outside and `auto_dismiss` is
  ## set; else passes the end on. Swallows it. ModalView.on_touch_up
  # Kivy tests for False explicitly: None (no touch down seen) passes on.
  if m.autoDismiss and m.touchStartedInside == 0:
    m.dismiss()
  else:
    discard procCall onTouchUp(AnchorLayout(m), touch)
  m.touchStartedInside = -1
  result = true
