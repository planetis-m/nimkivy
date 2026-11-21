## The anchor layout: Kivy's `kivy/uix/anchorlayout.py` (AnchorLayout).
##
## Every child is sized from its `size_hint` as a share of the layout's size
## less `padding`, within its `size_hint_min` and `size_hint_max`, and placed
## at the side or in the middle that `anchor_x` and `anchor_y` name.

import std/opt
import ../properties
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

  AnchorLayout* = ref object of Layout
    ## uix/anchorlayout.py AnchorLayout

let AnchorLayoutClass* = newDispatcherClass("AnchorLayout", LayoutClass)
  ## The class of `AnchorLayout`.
let pPadding = AnchorLayoutClass.addVariableList("padding", @[0.0, 0.0, 0.0, 0.0])
let pAnchorX = AnchorLayoutClass.addOption("anchor_x", "center",
  @["left", "center", "right"])
let pAnchorY = AnchorLayoutClass.addOption("anchor_y", "center",
  @["top", "center", "bottom"])

proc initAnchorLayout*(a: AnchorLayout) =
  ## Sets up a new anchor layout: the layout, then the trigger on its own
  ## properties. AnchorLayout.__init__
  a.initLayout()
  for name in ["children", "parent", "padding", "anchor_x", "anchor_y", "size", "pos"]:
    discard a.bindTrigger(a, name)

proc newAnchorLayout*(): AnchorLayout =
  ## An anchor layout that centres its children.
  result = AnchorLayout(cls: AnchorLayoutClass, canvas: newCanvas())
  result.initAnchorLayout()

proc padding*(a: AnchorLayout): array[4, float] =
  ## `[left, top, right, bottom]`.
  let p = pPadding.getFloats(a)
  result = [p[0], p[1], p[2], p[3]]
proc `padding=`*(a: AnchorLayout; p: openArray[float]) =
  ## Sets the padding from 1, 2 (`[horizontal, vertical]`) or 4 values.
  pPadding.setFloats(a, p)

proc anchorX*(a: AnchorLayout): AnchorX =
  ## Where children go horizontally (default `center`).
  AnchorX(pAnchorX.getOption(a))
proc `anchorX=`*(a: AnchorLayout; v: AnchorX) =
  ## Sets the horizontal anchor.
  pAnchorX.setOption(a, ord(v))
proc anchorY*(a: AnchorLayout): AnchorY =
  ## Where children go vertically (default `center`).
  AnchorY(pAnchorY.getOption(a))
proc `anchorY=`*(a: AnchorLayout; v: AnchorY) =
  ## Sets the vertical anchor.
  pAnchorY.setOption(a, ord(v))

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
