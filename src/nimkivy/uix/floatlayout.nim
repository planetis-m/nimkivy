## The float layout: Kivy's `kivy/uix/floatlayout.py` (FloatLayout).
##
## Each child is sized from its `size_hint` as a share of the layout's size,
## within its `size_hint_min` and `size_hint_max`, and placed by its
## `posHint` keys (`phX`, `phRight`, `phPos`, `phY`, `phTop`, `phCenter`,
## `phCenterX`, `phCenterY`) in the order they were given. A child without hints keeps its
## size and position.

import std/opt
import layout

export layout

type
  FloatLayout* = ref object of Layout
    ## uix/floatlayout.py FloatLayout
    posBinding: Binding      # its own `pos` binding (RelativeLayout drops it)
    posHintBinding: Binding  # and its own `posHint` binding

proc initFloatLayout*(f: FloatLayout) =
  ## Sets up a new float layout: the layout, then the trigger on its own
  ## properties. FloatLayout.__init__
  f.initLayout()
  discard f.bindChildren(proc (v: seq[WidgetBase]) {.closure.} = f.triggerNow())
  f.posBinding = f.bindPos(proc (v: (float, float)) {.closure.} = f.triggerNow())
  f.posHintBinding = f.bindPosHint(proc (v: PosHint) {.closure.} = f.triggerNow())
  discard f.bindSizeHint(proc (v: (Opt[float], Opt[float])) {.closure.} = f.triggerNow())
  discard f.bindSize(proc (v: (float, float)) {.closure.} = f.triggerNow())

proc newFloatLayout*(): FloatLayout =
  ## An empty float layout.
  result = FloatLayout(canvas: newCanvas(),
    posBinding: Binding(0), posHintBinding: Binding(0))
  result.initProps()
  result.initFloatLayout()

proc unbindOwnPos*(f: FloatLayout) =
  ## Stops laying out when the layout's own `pos` or `posHint` changes
  ## (RelativeLayout.__init__ funbinds them).
  f.unbindPos(f.posBinding)
  f.unbindPosHint(f.posHintBinding)

proc layoutIn*(f: FloatLayout; size, pos: (float, float)) =
  ## Places the children in a box of `size` at `pos`. FloatLayout.do_layout
  ## with its `size` and `pos` arguments.
  let (w, h) = size
  let (x, y) = pos
  for c in f.widgetChildren:
    let (shw, shh) = c.sizeHint
    let (shwMin, shhMin) = c.sizeHintMin
    let (shwMax, shhMax) = c.sizeHintMax
    if shw.isSome and shh.isSome:
      var cw = shw.get(0) * w
      var ch = shh.get(0) * h
      if shwMin.isSome and cw < shwMin.get(0):
        cw = shwMin.get(0)
      elif shwMax.isSome and cw > shwMax.get(0):
        cw = shwMax.get(0)
      if shhMin.isSome and ch < shhMin.get(0):
        ch = shhMin.get(0)
      elif shhMax.isSome and ch > shhMax.get(0):
        ch = shhMax.get(0)
      c.size = (cw, ch)
    elif shw.isSome:
      var cw = shw.get(0) * w
      if shwMin.isSome and cw < shwMin.get(0):
        cw = shwMin.get(0)
      elif shwMax.isSome and cw > shwMax.get(0):
        cw = shwMax.get(0)
      c.width = cw
    elif shh.isSome:
      var ch = shh.get(0) * h
      if shhMin.isSome and ch < shhMin.get(0):
        ch = shhMin.get(0)
      elif shhMax.isSome and ch > shhMax.get(0):
        ch = shhMax.get(0)
      c.height = ch

    for e in c.posHint.entries:
      case e.key
      of phX: c.x = x + e.value * w
      of phRight: c.right = x + e.value * w
      of phPos: c.pos = (x + e.pair[0] * w, y + e.pair[1] * h)
      of phY: c.y = y + e.value * h
      of phTop: c.top = y + e.value * h
      of phCenter: c.center = (x + e.pair[0] * w, y + e.pair[1] * h)
      of phCenterX: c.centerX = x + e.value * w
      of phCenterY: c.centerY = y + e.value * h

method isAbstract*(f: FloatLayout): bool =
  ## A float layout can be used.
  false

method doLayout*(f: FloatLayout) =
  ## Sizes and places the children in the layout's box.
  ## FloatLayout.do_layout
  f.layoutIn(f.size, f.pos)

# GAP: `widget` is not sink, because a captured sink parameter is never freed
# (planetis-m/nimony-bugs-llms#348; WindowBase's override captures it, and an
# override keeps its base's signature)
method addWidget*(f: FloatLayout; widget: WidgetBase; index = 0; canvas = layerCanvas) =
  ## Binds the layout to the child's `pos` and `posHint`, then adds it as
  ## Layout does. FloatLayout.add_widget
  f.bindChildPos(widget)
  f.bindChildPosHint(widget)
  procCall addWidget(Layout(f), widget, index, canvas)
