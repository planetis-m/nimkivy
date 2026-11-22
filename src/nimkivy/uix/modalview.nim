## The modal view: Kivy's `kivy/uix/modalview.py` (ModalView), with its rule
## from `kivy/data/style.kv`.
##
## A ModalView is an AnchorLayout that `open` adds to the Window, centred on
## it (and kept centred), over everything else. Its canvas darkens the whole
## window with `overlayColor` and draws its box in `backgroundColor`. It
## fades in and out over `animDuration`. Touches inside it go to its
## content; a touch that starts outside it dismisses it when it ends, if
## `autoDismiss` is set; every touch is swallowed. Escape (key 27)
## dismisses it too, with `autoDismiss`.
##
## `background` is an image path for the BorderImage. Kivy's default is an
## atlas image, and atlas is out of scope (SCOPE.md), so the default here is
## `""`: a plain box of `backgroundColor` (white).
##
## Build a modal view with `newModalView()`; a subclass's constructor makes
## the object, calls `initProps`, then `initModalView`.
##
## Out of scope (SCOPE.md): the deprecated `attach_to`, and Popup.

import ../[props, animation]
import ../graphics/[context_instructions, vertex_instructions]
import ../core/image
import anchorlayout

export anchorlayout

type
  TouchStart* = enum
    ## Where the touch being handled went down (Kivy's
    ## `_touch_started_inside`: None, False, True).
    startUnknown               ## no touch down seen
    startOutside               ## outside the view
    startInside                ## inside the view

properties:
  type
    ModalView* = ref object of AnchorLayout
      ## uix/modalview.py ModalView
      touchStartedInside: TouchStart   # Kivy's `_touch_started_inside`
      windowBindings: array[2, Binding] # the Window's `resize` and `keyboard` while open
      autoDismiss* {.prop.}: bool = true
        ## a touch outside or Escape dismisses the view
      backgroundColor* {.color.}: Rgba = [1.0, 1, 1, 1]
        ## the colour of the box (multiplies the background image)
      background* {.prop.}: string = ""
        ## the image of the box's BorderImage; "" is a plain box
      border* {.prop.}: seq[float] = @[16.0, 16, 16, 16]
        ## the BorderImage's borders: bottom, right, top, left
      overlayColor* {.color.}: Rgba = [0.0, 0, 0, 0.7]
        ## the colour over the whole window behind the view
      animAlpha* {.prop, handler.}: float = 0.0
        ## how far the view has faded in (Kivy's private `_anim_alpha`)
      animDuration* {.prop.}: float = 0.1
        ## the fade's duration in seconds (Kivy's private `_anim_duration`)
      window* {.prop.}: nil WindowBase = nil
        ## the window the view is open in, or nil (Kivy's private `_window`)
      isOpen* {.prop.}: bool = false
        ## whether the view is open (Kivy's private `_is_open`)
      preOpen* {.event.}: proc ()      ## before the view is added to the window
      open* {.event.}: proc ()         ## the view is open (after its fade)
      preDismiss* {.event.}: proc ()   ## `dismiss` was called on the open view
      dismiss* {.event.}: proc ()
        ## the view is about to close; an observer returning true keeps it open

  # ---------------------------------------------------------------- canvas

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
    discard m.bindOverlayColor(proc (v: Rgba) {.closure.} = m.setOverlay(overlay))
    discard m.bindAnimAlpha(proc (v: float) {.closure.} = m.setOverlay(overlay))
    var sizeBinding = Binding(0)
    var sizeOf: nil WindowBase = nil
    discard m.bindWindow(proc (v: nil WindowBase) {.closure.} =
      let old = sizeOf
      if old != nil and sizeBinding != Binding(0):
        old.unbindSize(sizeBinding)
      sizeBinding = Binding(0)
      sizeOf = nil
      if v != nil:
        shade.size = v.size
        sizeOf = v
        sizeBinding = v.bindSize(proc (s: (float, float)) {.closure.} = shade.size = s)
      else:
        shade.size = (0.0, 0.0))
    discard m.bindBackgroundColor(proc (v: Rgba) {.closure.} = bg.rgba = v)
    discard m.bindBackground(proc (v: string) {.closure.} = box.source = v)
    discard m.bindBorder(proc (v: seq[float]) {.closure.} = box.border = v)
    discard m.bindPos(proc (v: (float, float)) {.closure.} = box.pos = v)
    discard m.bindSize(proc (v: (float, float)) {.closure.} = box.size = v)

  # ---------------------------------------------------------------- construction

  proc initModalView*(m: ModalView) =
    ## Sets up a new modal view whose properties `initProps` has set: the
    ## anchor layout and its style.kv canvas. ModalView.__init__
    m.touchStartedInside = startUnknown
    m.windowBindings = [Binding(0), Binding(0)]
    m.initAnchorLayout()
    m.applyStyle()

  proc newModalView*(): ModalView =
    ## A modal view that fills the window (size_hint 1, 1) until hinted.
    result = ModalView(canvas: newCanvas(),
      touchStartedInside: startUnknown, windowBindings: [Binding(0), Binding(0)])
    result.initProps()
    result.initModalView()

  # ---------------------------------------------------------------- open, dismiss

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
    m.isOpen = false
    m.window = nil

  method onAnimAlphaChanged*(m: ModalView; v: float) {.base.} =
    ## Removes the view once it has faded out. ModalView.on__anim_alpha
    if v == 0 and m.isOpen:
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
    ## without `animation`); `open` is dispatched at the end. ModalView.open
    if m.isOpen:
      return
    let win = Window
    m.window = win
    m.isOpen = true
    discard m.dispatchPreOpen()
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
      let ani = newAnimation([animAlphaTo(ModalView, 1.0)], duration = m.animDuration)
      discard ani.bindComplete(proc (target: RootRef): bool {.closure.} =
        discard m.dispatchOpen()
        result = false)
      ani.start(m)
    else:
      m.animAlpha = 1.0
      discard m.dispatchOpen()

  proc dismiss*(m: ModalView; animation = true; force = false) =
    ## Fades the view out and removes it (at once without `animation`). A
    ## `dismiss` observer returning true keeps it open, unless `force`.
    ## ModalView.dismiss
    if not m.isOpen:
      return
    discard m.dispatchPreDismiss()
    if m.dispatchDismiss():
      if not force:
        return
    if animation:
      newAnimation([animAlphaTo(ModalView, 0.0)], duration = m.animDuration).start(m)
    else:
      m.animAlpha = 0.0
      m.realRemoveWidget()

  # ---------------------------------------------------------------- touches

  method onTouchDown*(m: ModalView; touch: MotionEvent): bool =
    ## Passes a touch inside on to the content (any touch without
    ## `autoDismiss`) and swallows it. ModalView.on_touch_down
    let inside = m.collidePoint(touch.pos[0], touch.pos[1])
    m.touchStartedInside = if inside: startInside else: startOutside
    if not m.autoDismiss or inside:
      discard procCall onTouchDown(AnchorLayout(m), touch)
    result = true

  method onTouchMove*(m: ModalView; touch: MotionEvent): bool =
    ## Passes the move on as the touch down was, and swallows it.
    ## ModalView.on_touch_move
    if not m.autoDismiss or m.touchStartedInside == startInside:
      discard procCall onTouchMove(AnchorLayout(m), touch)
    result = true

  method onTouchUp*(m: ModalView; touch: MotionEvent): bool =
    ## Dismisses the view if the touch started outside and `autoDismiss` is
    ## set; else passes the end on. Swallows it. ModalView.on_touch_up
    # Kivy tests for False explicitly: None (no touch down seen) passes on.
    if m.autoDismiss and m.touchStartedInside == startOutside:
      m.dismiss()
    else:
      discard procCall onTouchUp(AnchorLayout(m), touch)
    m.touchStartedInside = startUnknown
    result = true
