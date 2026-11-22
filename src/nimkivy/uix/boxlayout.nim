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
import layout

export layout

type
  Orientation* = enum
    ## BoxLayout.orientation, in the order of Kivy's options.
    orientationHorizontal = "horizontal"
    orientationVertical = "vertical"

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

properties:
  type
    BoxLayout* = ref object of Layout
      ## uix/boxlayout.py BoxLayout
      spacing* {.prop.}: float = 0.0  ## the space between children, in pixels
      padding* {.varlist: 4.}: array[4, float] = [0.0, 0.0, 0.0, 0.0]  ## left, top, right, bottom
      orientation* {.prop.}: Orientation = orientationHorizontal
      minimumWidth* {.prop.}: float = 0.0   ## the smallest width that holds the children
      minimumHeight* {.prop.}: float = 0.0  ## the smallest height that holds the children
      minimumSize* {.refs: (minimumWidth, minimumHeight).}: (float, float)

  proc initBoxLayout*(b: BoxLayout) =
    ## Sets up a new box layout: the layout, then the trigger on its own
    ## properties. BoxLayout.__init__
    b.initLayout()
    discard b.bindSpacing(proc (v: float) {.closure.} = b.triggerNow())
    discard b.bindPadding(proc (v: array[4, float]) {.closure.} = b.triggerNow())
    discard b.bindChildren(proc (v: seq[WidgetBase]) {.closure.} = b.triggerNow())
    discard b.bindOrientation(proc (v: Orientation) {.closure.} = b.triggerNow())
    discard b.bindParent(proc (v: nil WidgetBase) {.closure.} = b.triggerNow())
    discard b.bindSize(proc (v: (float, float)) {.closure.} = b.triggerNow())
    discard b.bindPos(proc (v: (float, float)) {.closure.} = b.triggerNow())

  proc newBoxLayout*(): BoxLayout =
    ## A horizontal box layout without spacing or padding.
    result = BoxLayout(canvas: newCanvas())
    result.initProps()
    result.initBoxLayout()

  proc nonZero(o: Opt[float]): bool {.inline.} =
    # Whether a hint is set and not 0 (Kivy tests the hint itself: `if sh:`).
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
          if nonZero(s.shwMin):
            hasBound = true
            minimumSizeBounded += s.shwMin.get(0)
          elif s.shwMax.isSome:
            hasBound = true
          stretchSum += s.shw.get(0)
        if s.shh.isNone:
          minimumSizeY = max(minimumSizeY, s.h)
        elif nonZero(s.shhMin):
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
          if nonZero(s.shhMin):
            hasBound = true
            minimumSizeBounded += s.shhMin.get(0)
          elif s.shhMax.isSome:
            hasBound = true
          stretchSum += s.shh.get(0)
        if s.shw.isNone:
          minimumSizeX = max(minimumSizeX, s.w)
        elif nonZero(s.shwMin):
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
        if nonZero(sh):
          w = max(0.0, stretchSpace * sh.get(0) / stretchSum)
        if nonZero(s.shh):
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
        if nonZero(sh):
          h = max(0.0, stretchSpace * sh.get(0) / stretchSum)
        if nonZero(s.shw):
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

  method isAbstract*(b: BoxLayout): bool =
    ## A box layout can be used.
    false

  method doLayout*(b: BoxLayout) =
    ## Places the children. BoxLayout.do_layout
    var children: seq[Widget] = @[]
    for c in b.widgetChildren: children.add c
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
