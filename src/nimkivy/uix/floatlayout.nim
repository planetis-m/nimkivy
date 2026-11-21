## The float layout: Kivy's `kivy/uix/floatlayout.py` (FloatLayout).
##
## Each child is sized from its `size_hint` as a share of the layout's size,
## within its `size_hint_min` and `size_hint_max`, and placed by its
## `pos_hint` keys (`x`, `right`, `pos`, `y`, `top`, `center`, `center_x`,
## `center_y`) in the order they were given. A child without hints keeps its
## size and position.

import std/opt
import ../properties
import layout

export layout

type
  FloatLayout* = ref object of Layout
    ## uix/floatlayout.py FloatLayout
    posUid, posHintUid: int  # its own `pos` and `pos_hint` bindings (RelativeLayout drops them)

let FloatLayoutClass* = newDispatcherClass("FloatLayout", LayoutClass)
  ## The class of `FloatLayout`.

proc initFloatLayout*(f: FloatLayout) =
  ## Sets up a new float layout: the layout, then the trigger on its own
  ## properties. FloatLayout.__init__
  f.initLayout()
  discard f.bindTrigger(f, "children")
  f.posUid = f.bindTrigger(f, "pos")
  f.posHintUid = f.bindTrigger(f, "pos_hint")
  discard f.bindTrigger(f, "size_hint")
  discard f.bindTrigger(f, "size")

proc newFloatLayout*(): FloatLayout =
  ## An empty float layout.
  result = FloatLayout(cls: FloatLayoutClass, canvas: newCanvas(), posUid: 0, posHintUid: 0)
  result.initFloatLayout()

proc unbindOwnPos*(f: FloatLayout) =
  ## Stops laying out when the layout's own `pos` or `pos_hint` changes
  ## (RelativeLayout.__init__ funbinds them).
  f.unbindUid("pos", f.posUid)
  f.unbindUid("pos_hint", f.posHintUid)

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

    for (key, value) in c.posHint:
      case key
      of "x": c.x = x + value.num * w
      of "right": c.right = x + value.num * w
      of "pos": c.pos = (x + value.items[0].num * w, y + value.items[1].num * h)
      of "y": c.y = y + value.num * h
      of "top": c.top = y + value.num * h
      of "center": c.center = (x + value.items[0].num * w, y + value.items[1].num * h)
      of "center_x": c.centerX = x + value.num * w
      of "center_y": c.centerY = y + value.num * h
      else: discard

method doLayout*(f: FloatLayout) =
  ## Sizes and places the children in the layout's box.
  ## FloatLayout.do_layout
  f.layoutIn(f.size, f.pos)

method addWidget*(f: FloatLayout; widget: WidgetBase; index = 0; canvas = "") =
  ## Binds the layout to the child's `pos` and `pos_hint`, then adds it as
  ## Layout does. FloatLayout.add_widget
  f.bindChild(widget, "pos")
  f.bindChild(widget, "pos_hint")
  procCall addWidget(Layout(f), widget, index, canvas)
