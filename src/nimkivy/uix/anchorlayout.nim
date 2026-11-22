## The anchor layout: Kivy's `kivy/uix/anchorlayout.py` (AnchorLayout).
##
## Every child is sized from its `size_hint` as a share of the layout's size
## less `padding`, within its `size_hint_min` and `size_hint_max`, and placed
## at the side or in the middle that `anchor_x` and `anchor_y` name.

import std/opt
import layout

export layout

type
  AnchorX* = enum
    ## AnchorLayout.anchor_x, in the order of Kivy's options.
    anchorLeft = "left"
    anchorCenterX = "center"
    anchorRight = "right"

  AnchorY* = enum
    ## AnchorLayout.anchor_y, in the order of Kivy's options.
    anchorTop = "top"
    anchorCenterY = "center"
    anchorBottom = "bottom"

let AnchorLayoutClass* = newDispatcherClass("AnchorLayout", LayoutClass)
  ## The class of `AnchorLayout`, a name only (see `WidgetClass`).

properties:
  type
    AnchorLayout* = ref object of Layout
      ## uix/anchorlayout.py AnchorLayout
      padding* {.varlist: 4.}: array[4, float] = [0.0, 0.0, 0.0, 0.0]  ## left, top, right, bottom
      anchorX* {.prop.}: AnchorX = anchorCenterX  ## where children go horizontally
      anchorY* {.prop.}: AnchorY = anchorCenterY  ## where children go vertically

  proc initAnchorLayout*(a: AnchorLayout) =
    ## Sets up a new anchor layout: the layout, then the trigger on its own
    ## properties. AnchorLayout.__init__
    a.initLayout()
    discard a.bindChildren(proc (v: seq[WidgetBase]) {.closure.} = a.triggerNow())
    discard a.bindParent(proc (v: nil WidgetBase) {.closure.} = a.triggerNow())
    discard a.bindPadding(proc (v: array[4, float]) {.closure.} = a.triggerNow())
    discard a.bindAnchorX(proc (v: AnchorX) {.closure.} = a.triggerNow())
    discard a.bindAnchorY(proc (v: AnchorY) {.closure.} = a.triggerNow())
    discard a.bindSize(proc (v: (float, float)) {.closure.} = a.triggerNow())
    discard a.bindPos(proc (v: (float, float)) {.closure.} = a.triggerNow())

  proc newAnchorLayout*(): AnchorLayout =
    ## An anchor layout that centres its children.
    result = AnchorLayout(cls: AnchorLayoutClass, canvas: newCanvas())
    result.initProps()
    result.initAnchorLayout()

  method doLayout*(a: AnchorLayout) =
    ## Sizes and places the children. AnchorLayout.do_layout
    let (px, py) = a.pos
    let width = a.width
    let height = a.height
    let anchorX = a.anchorX
    let anchorY = a.anchorY
    let pad = a.padding
    let (padLeft, padTop, padRight, padBottom) = (pad[0], pad[1], pad[2], pad[3])
    for c in a.widgetChildren:
      var x = px
      var y = py
      var (cw, ch) = c.size
      let (shw, shh) = c.sizeHint
      let (shwMin, shhMin) = c.sizeHintMin
      let (shwMax, shhMax) = c.sizeHintMax
      if shw.isSome:
        cw = shw.get(0) * (width - padLeft - padRight)
        if shwMin.isSome and cw < shwMin.get(0):
          cw = shwMin.get(0)
        elif shwMax.isSome and cw > shwMax.get(0):
          cw = shwMax.get(0)
      if shh.isSome:
        ch = shh.get(0) * (height - padTop - padBottom)
        if shhMin.isSome and ch < shhMin.get(0):
          ch = shhMin.get(0)
        elif shhMax.isSome and ch > shhMax.get(0):
          ch = shhMax.get(0)
      case anchorX
      of anchorLeft: x = x + padLeft
      of anchorRight: x = x + width - (cw + padRight)
      of anchorCenterX: x = x + (width - padRight + padLeft - cw) / 2
      case anchorY
      of anchorBottom: y = y + padBottom
      of anchorTop: y = y + height - (ch + padTop)
      of anchorCenterY: y = y + (height - padTop + padBottom - ch) / 2
      c.pos = (x, y)
      c.size = (cw, ch)
