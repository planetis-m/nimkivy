## The box layout: Kivy's `kivy/uix/boxlayout.py` (BoxLayout).
##
## Children are placed side by side, left to right (`horizontal`, the
## oldest child first) or top to bottom (`vertical`, the newest child at
## the top), with `spacing` between them and `padding` around them. A child
## with a size hint on the main axis shares the space left by the others,
## within its `size_hint_min` and `size_hint_max`; a child without one keeps
## its size. On the cross axis, the hint is a share of the box, and
## `pos_hint` (`x`, `right`, `center_x` in a vertical box; `y`, `top`,
## `center_y` in a horizontal one) places the child.

import std/opt
import ../properties
import layout

export layout

type
  Orientation* = enum
    ## BoxLayout.orientation, in the order of Kivy's options.
    orientationHorizontal = "horizontal"
    orientationVertical = "vertical"

  BoxLayout* = ref object of Layout
    ## uix/boxlayout.py BoxLayout

  ChildSizes = object
    # One element of `sizes` in BoxLayout._iterate_layout:
    # (size, size_hint, pos_hint, size_hint_min, size_hint_max).
    w, h: float
    shw, shh: Opt[float]
    posHint: PosHint
    shwMin, shhMin, shwMax, shhMax: Opt[float]

  Placement = object
    # What _iterate_layout yields: (index, x, y, w, h).
    index: int
    x, y, w, h: float

let BoxLayoutClass* = newDispatcherClass("BoxLayout", LayoutClass)
  ## The class of `BoxLayout`.
let pSpacing = BoxLayoutClass.addNumeric("spacing", 0)
let pPadding = BoxLayoutClass.addVariableList("padding", @[0.0, 0.0, 0.0, 0.0])
let pOrientation = BoxLayoutClass.addOption("orientation", "horizontal",
  @["horizontal", "vertical"])
let pMinimumWidth = BoxLayoutClass.addNumeric("minimum_width", 0)
let pMinimumHeight = BoxLayoutClass.addNumeric("minimum_height", 0)
let pMinimumSize = BoxLayoutClass.addReferenceList("minimum_size",
  @[Property(pMinimumWidth), pMinimumHeight])

proc initBoxLayout*(b: BoxLayout) =
  ## Sets up a new box layout: the layout, then the trigger on its own
  ## properties. BoxLayout.__init__
  b.initLayout()
  for name in ["spacing", "padding"]:
    discard b.bindTrigger(b, name)
  discard b.bindChildren(proc (v: seq[WidgetBase]) {.closure.} = b.triggerNow())
  discard b.bindTrigger(b, "orientation")
  discard b.bindParent(proc (v: nil WidgetBase) {.closure.} = b.triggerNow())
  for name in ["size", "pos"]:
    discard b.bindTrigger(b, name)

proc newBoxLayout*(): BoxLayout =
  ## A horizontal box layout without spacing or padding.
  result = BoxLayout(cls: BoxLayoutClass, canvas: newCanvas())
  result.initBoxLayout()

proc spacing*(b: BoxLayout): float =
  ## The space between children, in pixels.
  pSpacing.getNumber(b)
proc `spacing=`*(b: BoxLayout; v: float) =
  ## Sets the space between children.
  pSpacing.setNumber(b, v)

proc padding*(b: BoxLayout): array[4, float] =
  ## `[left, top, right, bottom]`.
  let p = pPadding.getFloats(b)
  result = [p[0], p[1], p[2], p[3]]
proc `padding=`*(b: BoxLayout; p: openArray[float]) =
  ## Sets the padding from 1, 2 (`[horizontal, vertical]`) or 4 values.
  pPadding.setFloats(b, p)

proc orientation*(b: BoxLayout): Orientation =
  ## `horizontal` (the default) or `vertical`.
  Orientation(pOrientation.getOption(b))
proc `orientation=`*(b: BoxLayout; o: Orientation) =
  ## Sets the orientation.
  pOrientation.setOption(b, ord(o))

proc minimumWidth*(b: BoxLayout): float =
  ## The smallest width that holds the children (set by the layout).
  pMinimumWidth.getNumber(b)
proc minimumHeight*(b: BoxLayout): float =
  ## The smallest height that holds the children (set by the layout).
  pMinimumHeight.getNumber(b)
proc minimumSize*(b: BoxLayout): (float, float) =
  ## `(minimumWidth, minimumHeight)`.
  let v = pMinimumSize.getFloats(b)
  result = (v[0], v[1])
proc `minimumSize=`(b: BoxLayout; s: (float, float)) =
  pMinimumSize.setFloats(b, [s[0], s[1]])

proc truthy(o: Opt[float]): bool {.inline.} =
  # Python's truth value of a number or None.
  o.isSome and o.get(0) != 0

proc iterateLayout(b: BoxLayout; sizes: seq[ChildSizes]): seq[Placement] =
  # BoxLayout._iterate_layout, line for line; the generator's values are
  # collected in a seq.
  result = @[]
  let lenChildren = sizes.len
  let pad = b.padding
  let (paddingLeft, paddingTop, paddingRight, paddingBottom) = (pad[0], pad[1], pad[2], pad[3])
  let spacing = b.spacing
  let orientation = b.orientation
  let paddingX = paddingLeft + paddingRight
  let paddingY = paddingTop + paddingBottom
  var stretchSum = 0.0
  var hasBound = false
  var hint = newSeq[Opt[float]](lenChildren)
  for i in 0 ..< lenChildren: hint[i] = none[float]()
  var minimumSizeBounded = 0.0
  var minimumSizeX = 0.0
  var minimumSizeY = 0.0
  var minimumSizeNone = 0.0

  if orientation == orientationHorizontal:
    minimumSizeY = 0
    minimumSizeNone = paddingX + spacing * float(lenChildren - 1)
    for i, s in sizes:
      if s.shw.isNone:
        minimumSizeNone += s.w
      else:
        hint[i] = s.shw
        if truthy(s.shwMin):
          hasBound = true
          minimumSizeBounded += s.shwMin.get(0)
        elif s.shwMax.isSome:
          hasBound = true
        stretchSum += s.shw.get(0)
      if s.shh.isNone:
        minimumSizeY = max(minimumSizeY, s.h)
      elif truthy(s.shhMin):
        minimumSizeY = max(minimumSizeY, s.shhMin.get(0))
    minimumSizeX = minimumSizeBounded + minimumSizeNone
    minimumSizeY += paddingY
  else:
    minimumSizeX = 0
    minimumSizeNone = paddingY + spacing * float(lenChildren - 1)
    for i, s in sizes:
      if s.shh.isNone:
        minimumSizeNone += s.h
      else:
        hint[i] = s.shh
        if truthy(s.shhMin):
          hasBound = true
          minimumSizeBounded += s.shhMin.get(0)
        elif s.shhMax.isSome:
          hasBound = true
        stretchSum += s.shh.get(0)
      if s.shw.isNone:
        minimumSizeX = max(minimumSizeX, s.w)
      elif truthy(s.shwMin):
        minimumSizeX = max(minimumSizeX, s.shwMin.get(0))
    minimumSizeY = minimumSizeBounded + minimumSizeNone
    minimumSizeX += paddingX

  b.minimumSize = (minimumSizeX, minimumSizeY)
  # If the size is too small, the children are squeezed.
  let selfx = b.x
  let selfy = b.y
  var stretchSpace = 0.0
  var dim = 0
  if orientation == orientationHorizontal:
    stretchSpace = max(0.0, b.width - minimumSizeNone)
    dim = 0
  else:
    stretchSpace = max(0.0, b.height - minimumSizeNone)
    dim = 1

  if hasBound:
    var shMins: seq[Opt[float]] = @[]
    var shMaxs: seq[Opt[float]] = @[]
    for s in sizes:
      shMins.add(if dim == 0: s.shwMin else: s.shhMin)
      shMaxs.add(if dim == 0: s.shwMax else: s.shhMax)
    # if the size is zero, the hints are the minimums (or 0)
    if stretchSpace < 1e-9:
      stretchSum = 1.0
      stretchSpace = 1.0
      for i, s in sizes:
        let sh = if dim == 0: s.shw else: s.shh
        if sh.isSome:
          let shMin = shMins[i]
          if shMin.isSome:
            hint[i] = shMin
          else:
            hint[i] = some(0.0)
    else:
      b.layoutHintWithBounds(stretchSum, stretchSpace, minimumSizeBounded, shMins,
        shMaxs, hint)

  if orientation == orientationHorizontal:
    var x = paddingLeft + selfx
    let sizeY = b.height - paddingY
    var i = 0
    var k = lenChildren - 1
    while k >= 0:
      # zip(reversed(hint), reversed(sizes))
      let sh = hint[k]
      let s = sizes[k]
      var w = s.w
      var h = s.h
      var cy = selfy + paddingBottom
      if truthy(sh):
        w = max(0.0, stretchSpace * sh.get(0) / stretchSum)
      if truthy(s.shh):
        h = max(0.0, s.shh.get(0) * sizeY)
      for e in s.posHint.entries:
        if e.key in {phY, phTop, phCenterY}:
          let posy = e.value * sizeY
          if e.key == phY:
            cy += posy
          elif e.key == phTop:
            cy += posy - h
          else:
            cy += posy - h / 2.0
      result.add Placement(index: lenChildren - i - 1, x: x, y: cy, w: w, h: h)
      x += w + spacing
      inc i
      dec k
  else:
    var y = paddingBottom + selfy
    let sizeX = b.width - paddingX
    for i, s in sizes:
      let sh = hint[i]
      var w = s.w
      var h = s.h
      var cx = selfx + paddingLeft
      if truthy(sh):
        h = max(0.0, stretchSpace * sh.get(0) / stretchSum)
      if truthy(s.shw):
        w = max(0.0, s.shw.get(0) * sizeX)
      for e in s.posHint.entries:
        if e.key in {phX, phRight, phCenterX}:
          let posx = e.value * sizeX
          if e.key == phX:
            cx += posx
          elif e.key == phRight:
            cx += posx - w
          else:
            cx += posx - w / 2.0
      result.add Placement(index: i, x: cx, y: y, w: w, h: h)
      y += h + spacing

method doLayout*(b: BoxLayout) =
  ## Places the children. BoxLayout.do_layout
  let children = b.widgetChildren
  if children.len == 0:
    let p = b.padding
    b.minimumSize = (p[0] + p[2], p[1] + p[3])
    return
  var sizes: seq[ChildSizes] = @[]
  for c in children:
    let (shw, shh) = c.sizeHint
    let (shwMin, shhMin) = c.sizeHintMin
    let (shwMax, shhMax) = c.sizeHintMax
    sizes.add ChildSizes(w: c.width, h: c.height, shw: shw, shh: shh,
      posHint: c.posHint, shwMin: shwMin, shhMin: shhMin, shwMax: shwMax, shhMax: shhMax)
  for p in b.iterateLayout(sizes):
    let c = children[p.index]
    c.pos = (p.x, p.y)
    let (shw, shh) = c.sizeHint
    if shw.isNone:
      if shh.isSome:
        c.height = p.h
    elif shh.isNone:
      c.width = p.w
    else:
      c.size = (p.w, p.h)

method addWidget*(b: BoxLayout; widget: WidgetBase; index = 0; canvas = layerCanvas) =
  ## Binds the layout to the child's `posHint`, then adds it as Layout
  ## does. BoxLayout.add_widget
  b.bindChildPosHint(widget)
  procCall addWidget(Layout(b), widget, index, canvas)
