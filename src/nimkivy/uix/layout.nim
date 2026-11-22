## The layout base: Kivy's `kivy/uix/layout.py` (Layout).
##
## A layout places its children in `doLayout`, which runs through a Clock
## trigger with timeout -1 (before the next frame) whenever a child's `size`,
## `size_hint`, `size_hint_min` or `size_hint_max` changes, or one of the
## layout's own properties that the subclass binds. `layoutHintWithBounds`
## shares space among hints with minimums and maximums (BoxLayout).

import std/[algorithm, assertions, opt, syncio]
import ../clock
import widget

export widget

type
  Unbind = proc () {.closure.}

  Layout* = ref object of Widget
    ## The base of the layouts. A layout's constructor makes the object,
    ## calls `initProps`, then its `init` proc, which calls `initLayout`.
    ## uix/layout.py Layout
    triggerLayout*: nil ClockEvent  ## runs `doLayout` before the next frame
    childUnbinds: seq[(WidgetBase, seq[Unbind])]  # undo what each child is bound with

method doLayout*(l: Layout) {.base.} =
  ## Places the children. Each layout overrides it. Layout.do_layout
  quit "doLayout is not implemented for this layout"

method isAbstract*(l: Layout): bool {.base.} =
  ## Whether the layout is a plain `Layout`, which cannot be used. Each
  ## layout that derives from `Layout` overrides it to return false (Kivy
  ## compares the instance's class with Layout).
  true

proc initLayout*(l: Layout) =
  ## Sets up a new layout: the layout trigger, then the widget.
  ## Layout.__init__
  if l.isAbstract():
    quit "The Layout class is abstract and cannot be used directly."
  l.childUnbinds = @[]
  l.triggerLayout = Clock.createTrigger(proc (dt: float) {.closure.} = l.doLayout(), -1)
  l.initWidget()

proc triggerNow*(l: Layout) =
  ## Triggers the layout (Kivy's `_trigger_layout()`): it runs before the
  ## next frame.
  let t = l.triggerLayout
  if t != nil: t.trigger()

proc keepUnbind*(l: Layout; child: sink WidgetBase; unbind: sink Unbind) =
  ## Remembers how to undo a binding on a child; `removeWidget` does it.
  var i = 0
  while i < l.childUnbinds.len and l.childUnbinds[i][0] != child:
    inc i
  if i == l.childUnbinds.len:
    l.childUnbinds.add (child, newSeq[Unbind]())
  l.childUnbinds[i][1].add unbind

proc bindChildPos*(l: Layout; child: sink WidgetBase) =
  ## Binds the layout trigger to a child's `pos`; `removeWidget` unbinds it.
  if child of HintedWidget:
    let h = HintedWidget(child)
    let b = h.bindPos(proc (v: (float, float)) {.closure.} = l.triggerNow())
    l.keepUnbind(child, proc () {.closure.} = h.unbindPos(b))

proc bindChildPosHint*(l: Layout; child: sink WidgetBase) =
  ## Binds the layout trigger to a child's `posHint`; `removeWidget`
  ## unbinds it.
  if child of HintedWidget:
    let h = HintedWidget(child)
    let b = h.bindPosHint(proc (v: PosHint) {.closure.} = l.triggerNow())
    l.keepUnbind(child, proc () {.closure.} = h.unbindPosHint(b))

# GAP: `widget` is not sink, because a captured sink parameter is never freed
# (planetis-m/nimony-bugs-llms#348; WindowBase's override captures it, and an
# override keeps its base's signature)
method addWidget*(l: Layout; widget: WidgetBase; index = 0; canvas = layerCanvas) =
  ## Binds the layout to the child's size and size hints, then adds it.
  ## Layout.add_widget
  if widget of HintedWidget:
    let h = HintedWidget(widget)
    let s = h.bindSize(proc (v: (float, float)) {.closure.} = l.triggerNow())
    let a = h.bindSizeHint(proc (v: (Opt[float], Opt[float])) {.closure.} = l.triggerNow())
    let b = h.bindSizeHintMax(proc (v: (Opt[float], Opt[float])) {.closure.} = l.triggerNow())
    let c = h.bindSizeHintMin(proc (v: (Opt[float], Opt[float])) {.closure.} = l.triggerNow())
    l.keepUnbind(widget, proc () {.closure.} =
      h.unbindSize(s)
      h.unbindSizeHint(a)
      h.unbindSizeHintMax(b)
      h.unbindSizeHintMin(c))
  procCall addWidget(Widget(l), widget, index, canvas)

method removeWidget*(l: Layout; widget: WidgetBase) =
  ## Unbinds everything the layout bound on the child, then removes it.
  ## Layout.remove_widget
  var i = 0
  while i < l.childUnbinds.len:
    if l.childUnbinds[i][0] == widget:
      let unbinds = l.childUnbinds[i][1]
      for unbind in unbinds:
        unbind()
      l.childUnbinds.delete(i)
    else:
      inc i
  procCall removeWidget(Widget(l), widget)

proc isClose(a, b: float; relTol = 1e-9; absTol = 0.0): bool =
  # kivy.compat.isclose: equal within a relative or an absolute tolerance.
  if a == b:
    return true
  let diff = abs(b - a)
  result = diff <= abs(relTol * b) or diff <= abs(relTol * a) or diff <= absTol

proc layoutHintWithBounds*(l: Layout; shSum, availableSpace, minBoundedSize: float;
    shMinVals, shMaxVals: seq[Opt[float]]; hint: var seq[Opt[float]]) =
  ## Turns the stretch hints `hint` (none: not stretched) into the share of
  ## `availableSpace` each child gets, keeping each within its minimum and
  ## maximum, and changes `hint` in place. Ported line for line.
  ## Layout.layout_hint_with_bounds
  if shSum == 0:
    return
  let n = hint.len
  let stretchRatio = shSum / availableSpace
  if availableSpace <= minBoundedSize or isClose(availableSpace, minBoundedSize):
    for i in 0 ..< n:
      if hint[i].isSome:
        let shMin = shMinVals[i]
        if shMin.isSome:
          hint[i] = some(shMin.get(0) * stretchRatio)
        else:
          hint[i] = some(0.0)
    return

  # The dicts of Kivy, keyed by child index: whether a key is in, its value.
  var notMinedIn = newSeq[bool](n)
  var notMinedContrib = newSeq[float](n)
  var notMaxedIn = newSeq[bool](n)
  var notMaxedContrib = newSeq[float](n)
  var shMinsAvail = newSeq[float](n)
  var shMaxsAvail = newSeq[float](n)
  var oversizeAmt = 0.0
  var undersizeAmt = 0.0
  let hintOrig = hint

  for i in 0 ..< n:
    if hint[i].isSome:
      let sh = hint[i].get(0)
      var diff = 0.0
      if shMinVals[i].isSome:
        let shMin = shMinVals[i].get(0) * stretchRatio
        diff = shMin - sh
        if diff > 0:
          hint[i] = some(shMin)
          undersizeAmt += diff
        else:
          notMinedIn[i] = true
        shMinsAvail[i] = hint[i].get(0) - shMin
      else:
        notMinedIn[i] = true
        shMinsAvail[i] = hint[i].get(0)
      if shMaxVals[i].isSome:
        let shMax = shMaxVals[i].get(0) * stretchRatio
        diff = sh - shMax
        if diff > 0:
          hint[i] = some(shMax)
          oversizeAmt += diff
        else:
          notMaxedIn[i] = true
        shMaxsAvail[i] = shMax - hint[i].get(0)
      else:
        notMaxedIn[i] = true
        shMaxsAvail[i] = shSum - hint[i].get(0)
      # Kivy's quirk: `diff` is the last one computed, from the maximum if
      # there is one.
      if notMinedIn[i]:
        notMinedContrib[i] = max(0.0, diff)
      if notMaxedIn[i]:
        notMaxedContrib[i] = max(0.0, diff)

  var margin = oversizeAmt - undersizeAmt
  if isClose(oversizeAmt, undersizeAmt, absTol = 1e-15):
    return

  var contribIn: seq[bool] = @[]
  var contribAmt: seq[float] = @[]
  var shAvailable: seq[float] = @[]
  var mult = 0.0
  var contribProportion: seq[float] = @[]   # 0 where Kivy's is None (never read)
  if margin > 1e-15:
    contribIn = notMaxedIn
    contribAmt = notMaxedContrib
    shAvailable = shMaxsAvail
    mult = 1.0
    for h in hintOrig:
      contribProportion.add(if h.isSome: h.get(0) else: 0.0)
  elif margin < -1e-15:
    margin *= -1.0
    contribIn = notMinedIn
    contribAmt = notMinedContrib
    shAvailable = shMinsAvail
    mult = -1.0
    # mn: the smallest true hint; mx: the largest hint
    var mn = 0.0
    var hasMn = false
    var mx = 0.0
    var hasMx = false
    for h in hintOrig:
      if h.isSome:
        let v = h.get(0)
        if v != 0 and (not hasMn or v < mn):
          mn = v
          hasMn = true
        if not hasMx or v > mx:
          mx = v
          hasMx = true
    let hintTop = if mn == mx: (if mn != 0: 2.0 * mn else: 1.0) else: mn + mx
    for h in hintOrig:
      contribProportion.add(if h.isSome: hintTop - h.get(0) else: 0.0)

  var contribPropSum = 0.0
  var items: seq[int] = @[]
  for i in 0 ..< n:
    if contribIn[i]:
      contribPropSum += contribProportion[i]
      items.add i
  if contribPropSum < 1e-9:
    assert mult == 1.0
    return

  var contribHeight = newSeq[float](n)
  for i in items:
    contribHeight[i] = contribAmt[i] / (contribProportion[i] / contribPropSum)
  # A stable sort by height, as Kivy's sorted().
  var byHeight: seq[(float, int)] = @[]
  for i in items:
    byHeight.add (contribHeight[i], i)
  byHeight.sort(proc (a, b: (float, int)): int = cmp(a[0], b[0]))
  for k in 0 ..< items.len:
    items[k] = byHeight[k][1]

  var j = items[0]
  var sumIContributed = contribAmt[j]
  var lastHeight = contribHeight[j]
  # sh_available_i: an insertion-ordered dict of index to available space.
  var shAvailableI: seq[(int, float)] = @[(j, shAvailable[j])]
  var contribPropSumI = contribProportion[j]
  let count = items.len
  var i = 1
  var currHeight = 0.0
  if 1 < count:
    j = items[1]
    currHeight = contribHeight[j]

  var done = false
  while not done and i < count:
    while i < count and lastHeight == currHeight:
      j = items[i]
      sumIContributed += contribAmt[j]
      contribPropSumI += contribProportion[j]
      shAvailableI.add (j, shAvailable[j])
      currHeight = contribHeight[j]
      inc i
    lastHeight = currHeight

    while not done:
      let marginHeight = (margin + sumIContributed) / (contribPropSumI / contribPropSum)
      if marginHeight - currHeight > 1e-9 and i < count:
        break
      done = true
      let snapshot = shAvailableI   # Kivy iterates over a copy
      for (k, availableSh) in snapshot:
        if marginHeight - availableSh / (contribProportion[k] / contribPropSum) > 1e-9:
          var at = 0
          while shAvailableI[at][0] != k:
            inc at
          shAvailableI.delete(at)
          sumIContributed -= contribAmt[k]
          contribPropSumI -= contribProportion[k]
          margin -= availableSh
          hint[k] = some(hint[k].get(0) + mult * availableSh)
          done = false
      if shAvailableI.len == 0:
        break

  if shAvailableI.len > 0:
    assert contribPropSumI != 0 and margin != 0
    let marginHeight = (margin + sumIContributed) / (contribPropSumI / contribPropSum)
    for (k, _) in shAvailableI:
      hint[k] = some(hint[k].get(0) + mult * (marginHeight * contribProportion[k] /
        contribPropSum - contribAmt[k]))
