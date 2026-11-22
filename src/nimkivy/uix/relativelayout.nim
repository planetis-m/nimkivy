## The relative layout: Kivy's `kivy/uix/relativelayout.py` (RelativeLayout),
## with its rule from `kivy/data/style.kv`.
##
## A FloatLayout whose children are in its own coordinates: (0, 0) is the
## layout's bottom left corner. Its canvas is drawn translated by `pos`
## (PushMatrix and Translate in `canvas.before`, PopMatrix in
## `canvas.after`), and touches are moved into its coordinates for the
## children. Moving the layout does not lay out the children again.

import ../graphics/context_instructions
import floatlayout

export floatlayout

type
  RelativeLayout* = ref object of FloatLayout
    ## uix/relativelayout.py RelativeLayout
    translate*: nil Translate  ## the canvas translation that follows `pos`

proc applyStyle(r: RelativeLayout) =
  # data/style.kv <RelativeLayout>: canvas.before: PushMatrix, Translate
  # (xy: self.pos); canvas.after: PopMatrix. The kv binding `xy: self.pos`
  # becomes an observer of `pos`.
  let t = newTranslate(r.x, r.y)
  r.translate = t
  r.canvas.before.add newPushMatrix()
  r.canvas.before.add t
  r.canvas.after.add newPopMatrix()
  discard r.bindPos(proc (v: (float, float)) {.closure.} = t.xy = v)

proc initRelativeLayout*(r: RelativeLayout) =
  ## Sets up a new relative layout: the float layout, its canvas rule, and
  ## no layout on its own `pos` or `pos_hint`. RelativeLayout.__init__
  r.initFloatLayout()
  r.applyStyle()
  r.unbindOwnPos()

proc newRelativeLayout*(): RelativeLayout =
  ## An empty relative layout.
  result = RelativeLayout(canvas: newCanvas(), translate: nil)
  result.initProps()
  result.initRelativeLayout()

method doLayout*(r: RelativeLayout) =
  ## Places the children in the layout's own coordinates.
  ## RelativeLayout.do_layout
  r.layoutIn(r.size, (0.0, 0.0))

method toParent*(r: RelativeLayout; x, y: float; relative = false): (float, float) =
  ## Local coordinates to the parent's, whatever `relative` says.
  ## RelativeLayout.to_parent
  (x + r.x, y + r.y)

method toLocal*(r: RelativeLayout; x, y: float; relative = false): (float, float) =
  ## The parent's coordinates to local ones, whatever `relative` says.
  ## RelativeLayout.to_local
  (x - r.x, y - r.y)

proc toLocalFn(r: RelativeLayout): proc (x, y: float): (float, float) {.closure.} =
  # `self.to_local` as a callable, for apply_transform_2d.
  result = proc (x, y: float): (float, float) {.closure.} = r.toLocal(x, y)

method onTouchDown*(r: RelativeLayout; touch: MotionEvent): bool =
  ## Passes the touch on in local coordinates. RelativeLayout.on_touch_down
  touch.push()
  touch.applyTransform2d(r.toLocalFn())
  result = procCall onTouchDown(FloatLayout(r), touch)
  touch.pop()

method onTouchMove*(r: RelativeLayout; touch: MotionEvent): bool =
  ## Passes the move on in local coordinates. RelativeLayout.on_touch_move
  touch.push()
  touch.applyTransform2d(r.toLocalFn())
  result = procCall onTouchMove(FloatLayout(r), touch)
  touch.pop()

method onTouchUp*(r: RelativeLayout; touch: MotionEvent): bool =
  ## Passes the end on in local coordinates. RelativeLayout.on_touch_up
  touch.push()
  touch.applyTransform2d(r.toLocalFn())
  result = procCall onTouchUp(FloatLayout(r), touch)
  touch.pop()
